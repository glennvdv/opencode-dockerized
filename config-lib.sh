#!/bin/bash

# config-lib.sh - Shared configuration module for opencode-dockerized
# This file is sourced by other scripts (not executed directly)
# Provides: config parsing, docker arg building, shared volume logic, and interactive prompts

# NOTE: Do not use "set -e" here — this is a library file sourced by callers.
# Let calling scripts control their own error handling.

# ============================================
# CONSTANTS
# ============================================

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/opencode-dockerized}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/config}"

# ============================================
# COLOR DEFINITIONS (with defaults if not set)
# ============================================

: "${RED:='\033[0;31m'}"
: "${GREEN:='\033[0;32m'}"
: "${YELLOW:='\033[1;33m'}"
: "${BLUE:='\033[0;34m'}"
: "${NC:='\033[0m'}"

# ============================================
# LOGGING FUNCTIONS (use caller's style if available)
# ============================================

config_info() {
    if type print_info >/dev/null 2>&1; then
        print_info "$1"
    else
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

config_success() {
    if type print_success >/dev/null 2>&1; then
        print_success "$1"
    else
        echo -e "${GREEN}✓${NC} $1"
    fi
}

config_warning() {
    if type print_warning >/dev/null 2>&1; then
        print_warning "$1"
    else
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

config_error() {
    if type print_error >/dev/null 2>&1; then
        print_error "$1"
    else
        echo -e "${RED}✗${NC} $1"
    fi
}

# ============================================
# CONFIG STATE (global arrays, populated by parse_config)
# ============================================

declare -a CUSTOM_MOUNTS=()      # Array of "host_path:container_path[:rw]"
declare -a CUSTOM_ENV_VARS=()    # Array of "VARIABLE_NAME"
declare -a DOCKER_MOUNT_ARGS=()  # Array of docker -v arguments (populated by build_mount_args)
declare -a DOCKER_ENV_ARGS=()    # Array of docker -e arguments (populated by build_env_args)
declare -a VOLUME_ARGS=()        # Array of standard volume mount arguments (populated by build_standard_volume_args)
declare -a GIT_WORKTREE_ARGS=()  # Array of docker args for git worktree support (populated by build_git_worktree_args)
SSH_AGENT_SUPPORT=false          # Boolean flag for SSH agent forwarding support
OPENSPEC_SUPPORT=false           # Boolean flag for OpenSpec (spec-driven development) support

# ============================================
# SHARED HELPERS
# ============================================

# Compute the container mount path for a project directory.
# Strips $HOME prefix so the path is portable across machines/users.
# Example: /home/user/projects/acme/frontend -> /projects/acme/frontend
#          /opt/work/myproject                -> /opt/work/myproject (unchanged)
# Usage: container_path=$(compute_container_path "/home/user/projects/myapp")
compute_container_path() {
    local host_path="$1"

    if [[ "$host_path" == "$HOME"/* ]]; then
        echo "${host_path#"$HOME"}"
    else
        echo "$host_path"
    fi
}

# Ensure all required OpenCode directories exist on host
ensure_opencode_dirs() {
    mkdir -p "$HOME/.local/share/opencode" 2>/dev/null || true
    mkdir -p "$HOME/.local/state/opencode" 2>/dev/null || true
    mkdir -p "$HOME/.cache/opencode" 2>/dev/null || true
    mkdir -p "$HOME/.cache/oh-my-opencode" 2>/dev/null || true
    mkdir -p "$HOME/.config/opencode" 2>/dev/null || true

    # Create OpenSpec directories if OpenSpec support is enabled
    if [ "$OPENSPEC_SUPPORT" = true ]; then
        mkdir -p "$HOME/.cache/openspec" 2>/dev/null || true
        mkdir -p "$HOME/.config/openspec" 2>/dev/null || true
    fi
}

# Check if Docker image exists locally
# Usage: check_image "$IMAGE_NAME"
check_image() {
    local image_name="$1"
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        config_error "Docker image '$image_name' not found. Run '$0 build' first."
        return 1
    fi
}

# Sanitize a string for use as part of a Docker container name
# Docker container names must match [a-zA-Z0-9][a-zA-Z0-9_.-]
# Usage: sanitize_container_name "my project dir"
sanitize_container_name() {
    local name="$1"
    name=$(echo "$name" | tr -cd '[:alnum:]._-')
    # Ensure it starts with alphanumeric
    while [[ "$name" =~ ^[^[:alnum:]] ]]; do name="${name#?}"; done
    [ -z "$name" ] && name="project"
    echo "$name"
}

# Generate a random hex suffix for container names
generate_random_suffix() {
    printf '%04x%04x' $RANDOM $RANDOM
}

# Detect if a directory is a git worktree and return the main repo's .git directory path
# A worktree has a .git FILE (not directory) containing "gitdir: <path>"
# Returns (via stdout): "<git_common_dir>" if worktree, empty string otherwise
# Usage: main_git_dir=$(detect_git_worktree "/path/to/worktree")
detect_git_worktree() {
    local project_dir="$1"

    # Quick check: if .git is a directory (normal repo) or doesn't exist, not a worktree
    if [ ! -f "$project_dir/.git" ]; then
        return 0
    fi

    # Use git to reliably resolve paths (handles relative/absolute gitdir pointers)
    if ! command -v git >/dev/null 2>&1; then
        config_warning "Git worktree detected but 'git' is not installed on the host — git info will be unavailable in container"
        return 0
    fi

    # git rev-parse --git-common-dir gives us the shared .git directory
    local git_common_dir
    git_common_dir=$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null) || return 0

    # Resolve to absolute path
    if [[ "$git_common_dir" != /* ]]; then
        git_common_dir=$(cd "$project_dir" && cd "$git_common_dir" && pwd)
    else
        git_common_dir=$(cd "$git_common_dir" && pwd)
    fi

    # Sanity check: the common dir should be a real .git directory
    if [ ! -d "$git_common_dir/objects" ] || [ ! -d "$git_common_dir/refs" ]; then
        return 0
    fi

    echo "$git_common_dir"
}

# Build Docker volume/bind args needed for git worktree support
# When the project is a git worktree, the .git file points to the main repo's
# .git directory which lives outside the project dir. We mount the main .git
# directory (read-only) at its real host path so the gitdir pointer resolves
# correctly inside the container.
#
# Read-only is intentional: it preserves the sandbox boundary (container only
# has write access to the mounted project directory). Read operations like
# git log, status, diff, and branch work. Write operations (commit, stash,
# fetch) will fail — run those on the host.
#
# Populates GIT_WORKTREE_ARGS array
# Usage: build_git_worktree_args "/path/to/project"
build_git_worktree_args() {
    local project_dir="$1"

    GIT_WORKTREE_ARGS=()

    local git_common_dir
    git_common_dir=$(detect_git_worktree "$project_dir")

    if [ -z "$git_common_dir" ]; then
        return 0
    fi

    config_info "Git worktree detected — mounting main .git directory (read-only) for git support"
    config_info "Main git directory: $git_common_dir"

    # Mount the main repo's .git directory at its real host path (read-only)
    GIT_WORKTREE_ARGS+=(-v "$git_common_dir:$git_common_dir:ro")
}

# Build common Docker run arguments shared by run_opencode and run_auth
# Populates DOCKER_COMMON_ARGS array
# Usage: build_common_docker_args
build_common_docker_args() {
    # shellcheck disable=SC2034  # DOCKER_COMMON_ARGS is used by callers that source this file
    DOCKER_COMMON_ARGS=(
        --rm
        --network host
        -e "HOST_UID=$(id -u)"
        -e "HOST_GID=$(id -g)"
        -e "TERM=${TERM:-xterm-256color}"
        -e "OPENSPEC_SUPPORT=$OPENSPEC_SUPPORT"
    )

    # Pass terminal identification variables so applications inside the container
    # can detect the host terminal and use its capabilities correctly.
    # Required for kitty OSC 99 terminal-mediated desktop notifications, true-color
    # rendering, and other terminal-specific features. All are conditional so they
    # have no effect on non-kitty terminals.
    [ -n "$TERM_PROGRAM" ]         && DOCKER_COMMON_ARGS+=(-e "TERM_PROGRAM=$TERM_PROGRAM")
    [ -n "$TERM_PROGRAM_VERSION" ] && DOCKER_COMMON_ARGS+=(-e "TERM_PROGRAM_VERSION=$TERM_PROGRAM_VERSION")
    [ -n "$KITTY_WINDOW_ID" ]      && DOCKER_COMMON_ARGS+=(-e "KITTY_WINDOW_ID=$KITTY_WINDOW_ID")
    [ -n "$COLORTERM" ]            && DOCKER_COMMON_ARGS+=(-e "COLORTERM=$COLORTERM")
}

# Build standard volume mount arguments for OpenCode directories
# Populates VOLUME_ARGS and CONTAINER_WORKDIR
# The project is mounted at a path derived from the host path (with $HOME stripped)
# so that OpenCode stores a unique, meaningful directory per project in its session DB.
# Usage: build_standard_volume_args "/path/to/project" [include_docker_socket]
build_standard_volume_args() {
    local project_dir="$1"
    local include_docker_socket="${2:-false}"

    VOLUME_ARGS=()

    # Compute container-side mount path: strip $HOME prefix for portability
    # e.g. /home/user/projects/acme/frontend -> /projects/acme/frontend
    CONTAINER_WORKDIR=$(compute_container_path "$project_dir")

    # Project directory (read-write) — mounted at the computed path
    VOLUME_ARGS+=(-v "$project_dir:$CONTAINER_WORKDIR")

    # Git worktree support: mount main .git directory if project is a worktree
    build_git_worktree_args "$project_dir"

    # OpenCode configuration directory (read-only)
    # Includes: opencode.json, AGENTS.md, .env, agent/, command/, plugin/, node_modules/, etc.
    if [ -d "$HOME/.config/opencode" ]; then
        VOLUME_ARGS+=(-v "$HOME/.config/opencode:/home/coder/.config/opencode:ro")
    else
        config_warning "OpenCode config directory not found at $HOME/.config/opencode"
    fi

    # OpenCode data directory (read-write for auth, logs, sessions, storage)
    if [ -d "$HOME/.local/share/opencode" ]; then
        VOLUME_ARGS+=(-v "$HOME/.local/share/opencode:/home/coder/.local/share/opencode")
    else
        config_warning "OpenCode data directory not found at $HOME/.local/share/opencode"
        config_info "You'll need to run 'opencode auth login' inside the container"
    fi

    # OpenCode state directory (TUI preferences, UI state, etc.)  (read-write)
    if [ -d "$HOME/.local/state/opencode" ]; then
        VOLUME_ARGS+=(-v "$HOME/.local/state/opencode:/home/coder/.local/state/opencode")
    fi

    # OpenCode provider package cache (improves startup time and prevents API errors)
    # See: https://opencode.ai/docs/troubleshooting/#ai_apicallerror-and-provider-package-issues
    if [ -d "$HOME/.cache/opencode" ]; then
        VOLUME_ARGS+=(-v "$HOME/.cache/opencode:/home/coder/.cache/opencode")
    fi

    # Oh My OpenCode cache directory
    if [ -d "$HOME/.cache/oh-my-opencode" ]; then
        VOLUME_ARGS+=(-v "$HOME/.cache/oh-my-opencode:/home/coder/.cache/oh-my-opencode")
    fi

    # OpenSpec cache directory (only when OpenSpec support is enabled)
    if [ "$OPENSPEC_SUPPORT" = true ] && [ -d "$HOME/.cache/openspec" ]; then
        VOLUME_ARGS+=(-v "$HOME/.cache/openspec:/home/coder/.cache/openspec")
        config_info "OpenSpec support enabled — cache directory mounted"
    fi

    # OpenSpec config directory (only when OpenSpec support is enabled)
    if [ "$OPENSPEC_SUPPORT" = true ] && [ -d "$HOME/.config/openspec" ]; then
        VOLUME_ARGS+=(-v "$HOME/.config/openspec:/home/coder/.config/openspec:ro")
        config_info "OpenSpec config directory mounted"
    fi

    # MCP authentication directory (optional)
    if [ -d "$HOME/.mcp-auth" ]; then
        VOLUME_ARGS+=(-v "$HOME/.mcp-auth:/home/coder/.mcp-auth:ro")
    fi

    # Gradle properties (optional)
    if [ -f "$HOME/.gradle/gradle.properties" ]; then
        VOLUME_ARGS+=(-v "$HOME/.gradle/gradle.properties:/home/coder/.gradle/gradle.properties:ro")
    fi

    # Git configuration (optional) — ensures commits use the host user's name and email
    if command -v git >/dev/null 2>&1 && [ -f "$HOME/.gitconfig" ]; then
        VOLUME_ARGS+=(-v "$HOME/.gitconfig:/home/coder/.gitconfig:ro")
    fi

    # NPM configuration (optional)
    if [ -f "$HOME/.npmrc" ]; then
        VOLUME_ARGS+=(-v "$HOME/.npmrc:/home/coder/.npmrc:ro")
    fi

    # Docker socket (optional, for Docker-in-Docker operations)
    if [ "$include_docker_socket" = true ] && [ -S /var/run/docker.sock ]; then
        VOLUME_ARGS+=(-v /var/run/docker.sock:/var/run/docker.sock)
    fi
}

# ============================================
# CONFIG FILE OPERATIONS
# ============================================

# Check if config file exists
config_exists() {
    [ -f "$CONFIG_FILE" ]
}

# Initialize config file with header
init_config_file() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << 'EOF'
# OpenCode Dockerized User Configuration
# Generated by setup.sh - edit manually or re-run setup.sh to modify

# Settings
# SSH Agent Forwarding (enables git over SSH in container)
# Automatically mounts SSH_AUTH_SOCK socket and passes the environment variable
# setting.ssh_agent_support=false

# OpenSpec Support (spec-driven development for AI coding assistants)
# When enabled, OpenSpec is available inside the container for spec-driven workflows
# On first run, 'openspec init --tools opencode' is automatically executed in new projects
# Then 'openspec update' runs on every launch to keep instruction files in sync
# See: https://github.com/Fission-AI/OpenSpec/
# setting.openspec_support=false

# Custom volume mounts (read-only by default)
# Format: mount.<name>=<host_path>:<container_path>[:rw]
# Examples:
#   mount.gitconfig=~/.gitconfig:/home/coder/.gitconfig
#   mount.ssh=~/.ssh:/home/coder/.ssh:rw
#   mount.gitignore_global=~/.config/git/gitignore_global:/home/coder/.config/git/gitignore_global

# Environment variables to pass from host to container
# Format: env.<name>=<variable_name>
# Examples:
#   env.aws_bedrock=AWS_BEARER_TOKEN_BEDROCK
#   env.context7=CONTEXT7_API_KEY
EOF
    config_success "Created config file at $CONFIG_FILE"
}

# Load config file into arrays
load_config() {
    if ! config_exists; then
        config_warning "Config file not found at $CONFIG_FILE"
        return 1
    fi

    CUSTOM_MOUNTS=()
    CUSTOM_ENV_VARS=()

    # Read mounts (lines starting with "mount.")
    while IFS='=' read -r key value; do
        # Skip comments and non-mount lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ "$key" =~ ^[[:space:]]*mount\. ]] || continue
        # Remove leading/trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [ -n "$value" ] && CUSTOM_MOUNTS+=("$value")
    done < "$CONFIG_FILE"

    # Read env vars (lines starting with "env.")
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ "$key" =~ ^[[:space:]]*env\. ]] || continue
        # Remove leading/trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [ -n "$value" ] && CUSTOM_ENV_VARS+=("$value")
    done < "$CONFIG_FILE"

    # Read settings (lines starting with "setting.")
    SSH_AGENT_SUPPORT=false
    OPENSPEC_SUPPORT=false
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ "$key" =~ ^[[:space:]]*setting\. ]] || continue
        # Remove leading/trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ "$key" =~ ssh_agent_support ]] && [[ "$value" == "true" ]] && SSH_AGENT_SUPPORT=true
        [[ "$key" =~ openspec_support ]] && [[ "$value" == "true" ]] && OPENSPEC_SUPPORT=true
    done < "$CONFIG_FILE"

    return 0
}

# Save current arrays to config file
save_config() {
    mkdir -p "$CONFIG_DIR"

    {
        echo "# OpenCode Dockerized User Configuration"
        echo "# Generated by setup.sh - edit manually or re-run setup.sh to modify"
        echo ""
        echo "# Settings"
        echo "# SSH Agent Forwarding (enables git over SSH in container)"
        echo "# Automatically mounts SSH_AUTH_SOCK socket and passes the environment variable"
        echo "setting.ssh_agent_support=$SSH_AGENT_SUPPORT"
        echo ""
        echo "# OpenSpec Support (spec-driven development for AI coding assistants)"
        echo "# When enabled, OpenSpec is available inside the container for spec-driven workflows"
        echo "# See: https://github.com/Fission-AI/OpenSpec/"
        echo "setting.openspec_support=$OPENSPEC_SUPPORT"
        echo ""
        echo "# Custom volume mounts (read-only by default)"
        echo "# Format: mount.<name>=<host_path>:<container_path>[:rw]"

        if [ ${#CUSTOM_MOUNTS[@]} -gt 0 ]; then
            for i in "${!CUSTOM_MOUNTS[@]}"; do
                echo "mount.custom$(( i + 1 ))=${CUSTOM_MOUNTS[$i]}"
            done
        fi

        echo ""
        echo "# Environment variables to pass from host to container"
        echo "# Format: env.<name>=<variable_name>"

        if [ ${#CUSTOM_ENV_VARS[@]} -gt 0 ]; then
            for i in "${!CUSTOM_ENV_VARS[@]}"; do
                echo "env.custom$(( i + 1 ))=${CUSTOM_ENV_VARS[$i]}"
            done
        fi
    } > "$CONFIG_FILE"

    config_success "Saved configuration to $CONFIG_FILE"
}

# ============================================
# CONFIG PARSING (used at runtime by all scripts)
# ============================================

# Parse config file into global arrays
parse_config() {
    load_config || return 0  # Continue even if load fails
}

# Build docker volume mount arguments from CUSTOM_MOUNTS array
# Populates DOCKER_MOUNT_ARGS array with -v arguments
build_mount_args() {
    DOCKER_MOUNT_ARGS=()

    for mount in "${CUSTOM_MOUNTS[@]}"; do
        # Expand all occurrences of ~ to home directory
        mount="${mount//\~/$HOME}"

        # Extract host_path, container_path, and mode
        local host_path="${mount%%:*}"
        local rest="${mount#*:}"
        local container_path="${rest%:*}"
        local mode="${rest##*:}"

        # Validate mode is either not set or "rw"
        if [ "$mode" = "$container_path" ]; then
            # No mode specified, default to read-only
            DOCKER_MOUNT_ARGS+=(-v "$host_path:$container_path:ro")
        elif [ "$mode" = "rw" ]; then
            DOCKER_MOUNT_ARGS+=(-v "$host_path:$container_path:rw")
        else
            # Mode was specified, use it as-is
            DOCKER_MOUNT_ARGS+=(-v "$host_path:$container_path:$mode")
        fi
    done

    # Handle SSH agent forwarding if enabled
    if [ "$SSH_AGENT_SUPPORT" = true ]; then
        if [ -n "$SSH_AUTH_SOCK" ]; then
            if [ -S "$SSH_AUTH_SOCK" ]; then
                DOCKER_MOUNT_ARGS+=(-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK")
            else
                config_warning "SSH agent support enabled but socket not found at $SSH_AUTH_SOCK"
            fi
        else
            config_warning "SSH agent support enabled but SSH_AUTH_SOCK is not set"
        fi
    fi
}

# Build docker environment variable arguments from CUSTOM_ENV_VARS array
# Populates DOCKER_ENV_ARGS array with -e arguments
build_env_args() {
    DOCKER_ENV_ARGS=()

    for var_name in "${CUSTOM_ENV_VARS[@]}"; do
        # Validate variable name matches expected pattern
        if ! [[ "$var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            config_warning "Invalid variable name in config: $var_name (must be uppercase with underscores, skipping)"
            continue
        fi

        # Get the value from the current environment
        local var_value="${!var_name}"

        # Only add if the variable is set in the environment
        if [ -n "$var_value" ]; then
            DOCKER_ENV_ARGS+=(-e "$var_name=$var_value")
        else
            config_warning "Environment variable '$var_name' not set in host environment (skipping)"
        fi
    done

    # Handle SSH agent forwarding if enabled
    if [ "$SSH_AGENT_SUPPORT" = true ]; then
        if [ -n "$SSH_AUTH_SOCK" ]; then
            DOCKER_ENV_ARGS+=(-e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
        fi
    fi
}

# ============================================
# CONFIG MANAGEMENT (used by setup.sh)
# ============================================

# Add a mount entry to arrays and optionally save
# add_mount <host_path> <container_path> [rw]
add_mount() {
    local host_path="$1"
    local container_path="$2"
    local mode="${3:-}"

    if [ -z "$host_path" ] || [ -z "$container_path" ]; then
        config_error "add_mount requires host_path and container_path"
        return 1
    fi

    # Validate host path exists
    local expanded_path="${host_path/\~/$HOME}"
    if [ ! -e "$expanded_path" ]; then
        config_warning "Host path does not exist: $expanded_path"
    fi

    if [ -n "$mode" ] && [ "$mode" != "ro" ] && [ "$mode" != "rw" ]; then
        config_error "Invalid mode: $mode (must be 'ro' or 'rw')"
        return 1
    fi

    local mount_entry="$host_path:$container_path"
    [ -n "$mode" ] && mount_entry="$mount_entry:$mode"

    CUSTOM_MOUNTS+=("$mount_entry")
}

# Add an environment variable entry to arrays
# add_env_var <VARIABLE_NAME>
add_env_var() {
    local var_name="$1"

    if [ -z "$var_name" ]; then
        config_error "add_env_var requires variable name"
        return 1
    fi

    CUSTOM_ENV_VARS+=("$var_name")
}

# Remove a mount entry by index
# remove_mount <index>
remove_mount() {
    local index="$1"

    if [ -z "$index" ]; then
        config_error "remove_mount requires index"
        return 1
    fi

    if [ "$index" -lt 0 ] || [ "$index" -ge ${#CUSTOM_MOUNTS[@]} ]; then
        config_error "Invalid index: $index"
        return 1
    fi

    unset 'CUSTOM_MOUNTS[$index]'
    CUSTOM_MOUNTS=("${CUSTOM_MOUNTS[@]}")  # Reindex array
}

# Remove an env var entry by index
# remove_env_var <index>
remove_env_var() {
    local index="$1"

    if [ -z "$index" ]; then
        config_error "remove_env_var requires index"
        return 1
    fi

    if [ "$index" -lt 0 ] || [ "$index" -ge ${#CUSTOM_ENV_VARS[@]} ]; then
        config_error "Invalid index: $index"
        return 1
    fi

    unset 'CUSTOM_ENV_VARS[$index]'
    CUSTOM_ENV_VARS=("${CUSTOM_ENV_VARS[@]}")  # Reindex array
}

# ============================================
# INTERACTIVE PROMPTS (used by setup.sh)
# ============================================

# Suggest a container path based on host path
# suggest_container_path <host_path> [default]
suggest_container_path() {
    local host_path="$1"
    local default="${2:-/home/coder/$(basename "$host_path")}"

    # For common paths, suggest sensible defaults
    if [[ "$host_path" == *"/.gitconfig" ]]; then
        echo "/home/coder/.gitconfig"
    elif [[ "$host_path" == *"/.ssh" ]]; then
        echo "/home/coder/.ssh"
    elif [[ "$host_path" == *"/.config/git"* ]]; then
        echo "/home/coder/.config/git/$(basename "$host_path")"
    elif [[ "$host_path" == *"/.gradle"* ]]; then
        echo "/home/coder/.gradle/$(basename "$host_path")"
    else
        echo "$default"
    fi
}

# Ask user how to handle existing config
# Sets global: CONFIG_MODE ("append", "overwrite", or "skip")
prompt_config_mode() {
    if ! config_exists; then
        CONFIG_MODE="new"
        return 0
    fi

    echo ""
    config_info "Configuration file already exists at $CONFIG_FILE"

    PS3="Choose an option: "
    select mode in "Append (add new entries)" "Overwrite (replace config)" "Skip (keep existing)"; do
        case "$mode" in
            "Append (add new entries)")
                CONFIG_MODE="append"
                config_success "Will append new entries to existing config"
                break
                ;;
            "Overwrite (replace config)")
                CONFIG_MODE="overwrite"
                config_warning "Will replace existing config"
                break
                ;;
            "Skip (keep existing)")
                CONFIG_MODE="skip"
                config_info "Skipping config setup"
                break
                ;;
            *)
                config_error "Invalid option"
                ;;
        esac
    done
}

# Interactive mount addition
# Prompts user repeatedly until they enter a blank line
prompt_custom_mounts() {
    echo ""
    config_info "Configure custom volume mounts (optional)"
    echo "Enter host paths to mount in the container (read-only by default)"
    echo "Press Enter with empty input to finish"
    echo ""

    while true; do
        read -r -p "Host path: " host_path

        # Allow blank to exit
        if [ -z "$host_path" ]; then
            break
        fi

        # Expand ~ for validation
        local expanded_path="${host_path/\~/$HOME}"

        if [ ! -e "$expanded_path" ]; then
            config_warning "Path does not exist: $expanded_path"
            read -r -p "Continue anyway? (y/N): " proceed
            [[ "$proceed" =~ ^[Yy]$ ]] || continue
        fi

        # Suggest container path
        local suggested
        suggested=$(suggest_container_path "$host_path")
        read -r -p "Container path [$suggested]: " container_path
        container_path="${container_path:-$suggested}"

        # Ask about read-write
        read -r -p "Read-write? (y/N): " rw_mode
        local mode=""
        if [[ "$rw_mode" =~ ^[Yy]$ ]]; then
            mode="rw"
        fi

        # Add the mount
        add_mount "$host_path" "$container_path" "$mode"
        config_success "Added mount: $host_path -> $container_path${mode:+ ($mode)}"
        echo ""
    done
}

# Interactive environment variable addition
# Prompts user repeatedly until they enter a blank line
prompt_env_vars() {
    echo ""
    config_info "Configure environment variables (optional)"
    echo "Specify host environment variables to pass to the container"
    echo "Press Enter with empty input to finish"
    echo ""

    echo "Common examples:"
    echo "  AWS_BEARER_TOKEN_BEDROCK - AWS Bedrock API key"
    echo "  CONTEXT7_API_KEY - Context7 API key"
    echo ""

    while true; do
        read -r -p "Environment variable name: " var_name

        # Allow blank to exit
        if [ -z "$var_name" ]; then
            break
        fi

        # Validate variable name (basic check)
        if ! [[ "$var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            config_error "Invalid variable name: $var_name (must be uppercase with underscores)"
            continue
        fi

        # Check if variable is set in environment
        if [ -z "${!var_name}" ]; then
            config_warning "Variable '$var_name' is not set in current environment"
            read -r -p "Add anyway? (y/N): " proceed
            [[ "$proceed" =~ ^[Yy]$ ]] || continue
        fi

        # Add the variable
        add_env_var "$var_name"
        config_success "Added environment variable: $var_name"
        echo ""
    done
}

# Interactive SSH agent support prompt
# If SSH_AGENT_SUPPORT is already set (from a previous config), show current value
# and only ask if user wants to change it
prompt_ssh_agent_support() {
    echo ""
    config_info "SSH Agent Forwarding Support"

    if [ "$SSH_AGENT_SUPPORT" = true ]; then
        config_success "SSH agent forwarding is currently enabled"
        read -r -p "Keep SSH agent forwarding enabled? (Y/n): " ssh_agent
        if [[ "$ssh_agent" =~ ^[Nn]$ ]]; then
            SSH_AGENT_SUPPORT=false
            config_info "SSH agent forwarding support disabled"
        else
            config_success "SSH agent forwarding support remains enabled"
        fi
    else
        echo "Enable this if you use SSH agent forwarding for git operations over SSH."
        echo "This automatically mounts the SSH socket and passes the SSH_AUTH_SOCK variable."
        echo ""

        read -r -p "Enable SSH agent forwarding support? (y/N): " ssh_agent
        if [[ "$ssh_agent" =~ ^[Yy]$ ]]; then
            SSH_AGENT_SUPPORT=true
            config_success "SSH agent forwarding support enabled"
        else
            SSH_AGENT_SUPPORT=false
            config_info "SSH agent forwarding support disabled"
        fi
    fi
}

# Interactive OpenSpec support prompt
# If OPENSPEC_SUPPORT is already set (from a previous config), show current value
# and only ask if user wants to change it
prompt_openspec_support() {
    echo ""
    config_info "OpenSpec Support (https://github.com/Fission-AI/OpenSpec/)"

    if [ "$OPENSPEC_SUPPORT" = true ]; then
        config_success "OpenSpec support is currently enabled"
        read -r -p "Keep OpenSpec enabled? (Y/n): " openspec
        if [[ "$openspec" =~ ^[Nn]$ ]]; then
            OPENSPEC_SUPPORT=false
            config_info "OpenSpec support disabled"
        else
            config_success "OpenSpec support remains enabled"
        fi
    else
        echo "OpenSpec adds spec-driven development (SDD) to AI coding assistants."
        echo "It helps you agree on what to build before any code is written."
        echo "When enabled, 'openspec init --tools opencode' runs automatically on first"
        echo "launch for each project, then 'openspec update' keeps instruction files in"
        echo "sync on every run. The 'openspec' CLI is also available in the container."
        echo ""

        read -r -p "Enable OpenSpec support? (y/N): " openspec
        if [[ "$openspec" =~ ^[Yy]$ ]]; then
            OPENSPEC_SUPPORT=true
            config_success "OpenSpec support enabled"
        else
            OPENSPEC_SUPPORT=false
            config_info "OpenSpec support disabled"
        fi
    fi
}

# Print current configuration (for debugging/info)
print_config() {
    echo ""
    echo "Current configuration:"
    echo "  Config file: $CONFIG_FILE"
    echo "  SSH agent forwarding: $SSH_AGENT_SUPPORT"
    echo "  OpenSpec support: $OPENSPEC_SUPPORT"

    if [ ${#CUSTOM_MOUNTS[@]} -gt 0 ]; then
        echo ""
        echo "  Custom mounts:"
        for i in "${!CUSTOM_MOUNTS[@]}"; do
            echo "    [$i] ${CUSTOM_MOUNTS[$i]}"
        done
    else
        echo ""
        echo "  Custom mounts: (none)"
    fi

    if [ ${#CUSTOM_ENV_VARS[@]} -gt 0 ]; then
        echo ""
        echo "  Environment variables:"
        for i in "${!CUSTOM_ENV_VARS[@]}"; do
            echo "    [$i] ${CUSTOM_ENV_VARS[$i]}"
        done
    else
        echo ""
        echo "  Environment variables: (none)"
    fi
    echo ""
}

# ============================================
# SETUP ORCHESTRATION (used by setup.sh)
# ============================================

# Main entry point for interactive configuration setup
# Handles: mode selection, prompts, config persistence
interactive_config_setup() {
    prompt_config_mode

    case "$CONFIG_MODE" in
        skip)
            echo ""
            echo "Skipping custom configuration setup."
            echo "You can run setup.sh again later to configure custom mounts and environment variables."
            ;;
        append|overwrite)
            [ "$CONFIG_MODE" = "append" ] && load_config
            prompt_ssh_agent_support
            prompt_openspec_support
            prompt_custom_mounts
            prompt_env_vars
            save_config
            print_config
            ;;
        new)
            read -r -p "Would you like to configure custom mounts and environment variables now? (y/N): " setup_custom
            if [[ "$setup_custom" =~ ^[Yy]$ ]]; then
                prompt_ssh_agent_support
                prompt_openspec_support
                prompt_custom_mounts
                prompt_env_vars
                if [ ${#CUSTOM_MOUNTS[@]} -gt 0 ] || [ ${#CUSTOM_ENV_VARS[@]} -gt 0 ] || [ "$SSH_AGENT_SUPPORT" = true ] || [ "$OPENSPEC_SUPPORT" = true ]; then
                    save_config
                    print_config
                else
                    config_info "No custom configuration added."
                fi
            else
                init_config_file
                config_info "You can run setup.sh again later to configure custom mounts and environment variables."
            fi
            ;;
    esac
}
