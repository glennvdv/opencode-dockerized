#!/bin/bash

# OpenCode Docker Wrapper Script
# This script makes it easy to run OpenCode in a secure Docker container

set -e

# Resolve symlinks so SCRIPT_DIR points to the real source directory
# This allows the script to be invoked via a symlink in PATH (e.g. ~/.local/bin)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
IMAGE_NAME="opencode-dockerized:latest"

# Colors for output (defined before sourcing config-lib so it picks them up)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source the shared config module
source "$SCRIPT_DIR/config-lib.sh"

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to verify OpenSpec is installed in the Docker image
# Called when OPENSPEC_SUPPORT is enabled to confirm the binary is available
check_openspec() {
    if [ "$OPENSPEC_SUPPORT" != true ]; then
        return 0
    fi

    if ! docker run --rm --entrypoint bash "$IMAGE_NAME" -c "command -v openspec" >/dev/null 2>&1; then
        print_warning "OpenSpec support is enabled but 'openspec' was not found in the image"
        print_info "Rebuild the image to install OpenSpec: $0 build"
        return 1
    fi
    return 0
}

# Function to build the Docker image
build_image() {
    print_info "Building OpenCode Docker image..."
    # Regular build uses Docker layer cache normally.
    # Only the 'update' command passes OPENCODE_BUILD_TIME to bust the npm cache.
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    print_success "Docker image built successfully"
}

# Function to check required configuration files
check_config() {
    local missing_files=()

    if [ ! -f "$HOME/.config/opencode/opencode.json" ] && [ ! -f "$HOME/.config/opencode/opencode.jsonc" ]; then
        missing_files+=("$HOME/.config/opencode/opencode.json (or opencode.jsonc)")
    fi

    if [ ! -d "$HOME/.local/share/opencode" ]; then
        missing_files+=("$HOME/.local/share/opencode/")
    fi

    if [ ! -d "$HOME/.local/state/opencode" ]; then
        missing_files+=("$HOME/.local/state/opencode/")
    fi

    if [ ${#missing_files[@]} -gt 0 ]; then
        print_warning "Some OpenCode configuration files are missing:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        print_info "OpenCode will run but may need configuration. Run 'opencode auth login' inside the container."
    fi

    # Ensure OpenCode storage directories exist
    # According to docs: https://opencode.ai/docs/troubleshooting/#storage
    ensure_opencode_dirs
}

# Function to run OpenCode authentication
run_auth() {
    check_image "$IMAGE_NAME" || exit 1

    print_info "Running OpenCode authentication..."

    # Ensure OpenCode directories exist
    ensure_opencode_dirs

    # Parse custom config and build docker arguments
    parse_config
    build_mount_args
    build_env_args
    build_common_docker_args

    # Build volume mount arguments for auth
    local -a auth_volume_args=(
        -v "$HOME/.local/share/opencode:/home/coder/.local/share/opencode"
        -v "$HOME/.cache/opencode:/home/coder/.cache/opencode"
        # Config directory read-write for writing opencode.json during auth
        -v "$HOME/.config/opencode:/home/coder/.config/opencode"
    )

    # Run OpenCode auth login in Docker
    if ! docker run -it \
        --name "opencode-auth-$$" \
        "${DOCKER_COMMON_ARGS[@]}" \
        "${auth_volume_args[@]}" \
        "${DOCKER_MOUNT_ARGS[@]}" \
        "${DOCKER_ENV_ARGS[@]}" \
        "$IMAGE_NAME" \
        opencode auth login; then
        print_error "Authentication failed"
        exit 1
    fi

    print_success "Authentication complete! Your credentials are saved in $HOME/.local/share/opencode"
}

# Function to run OpenCode
run_opencode() {
    local project_dir="${1:-$(pwd)}"
    local dry_run="${DRY_RUN:-false}"

    # Validate project directory exists
    if [ ! -d "$project_dir" ]; then
        print_error "Project directory does not exist: $project_dir"
        exit 1
    fi

    # Convert to absolute path
    project_dir="$(cd "$project_dir" && pwd)"

    check_image "$IMAGE_NAME" || exit 1

    # Generate unique container name based on project directory and random suffix
    local dir_name
    dir_name=$(sanitize_container_name "$(basename "$project_dir")")
    local random_suffix
    random_suffix=$(generate_random_suffix)
    local container_name="opencode-${dir_name}-${random_suffix}"

    print_info "Starting OpenCode in Docker..."
    print_info "Project directory: $project_dir"
    print_info "Container name: $container_name"

    # Parse custom config and build docker arguments
    parse_config
    build_mount_args
    build_env_args
    build_common_docker_args
    build_standard_volume_args "$project_dir" true

    # Verify OpenSpec is available in the image if enabled
    check_openspec

    # Build the full docker run command as an array
    # CONTAINER_WORKDIR is set by build_standard_volume_args (host path with $HOME stripped)
    local -a docker_cmd=(
        docker run -it
        --name "$container_name"
        --workdir "$CONTAINER_WORKDIR"
        -e "OPENCODE_WORKDIR=$CONTAINER_WORKDIR"
        "${DOCKER_COMMON_ARGS[@]}"
        "${VOLUME_ARGS[@]}"
        "${GIT_WORKTREE_ARGS[@]}"
        "${DOCKER_MOUNT_ARGS[@]}"
        "${DOCKER_ENV_ARGS[@]}"
        "$IMAGE_NAME"
        opencode
    )

    if [ "$dry_run" = true ]; then
        print_info "Dry run — would execute:"
        echo "${docker_cmd[*]}"
        return 0
    fi

    # Note: Each run gets a unique container name, so no cleanup needed
    # The --rm flag ensures automatic cleanup when the container exits
    if ! "${docker_cmd[@]}"; then
        print_error "OpenCode exited with an error"
        exit 1
    fi
}

# Function to update OpenCode
update_opencode() {
    check_image "$IMAGE_NAME" || {
        print_info "Image not found, building fresh..."
        docker build --build-arg "OPENCODE_BUILD_TIME=$(date +%s)" -t "$IMAGE_NAME" "$SCRIPT_DIR"
        print_success "OpenCode image built successfully"
        return 0
    }

    # Show current version before update
    print_info "Current OpenCode version:"
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "source \$NVM_DIR/nvm.sh && npm list -g opencode-ai --depth=0" 2>/dev/null || true
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "source \$NVM_DIR/nvm.sh && npm list -g @fission-ai/openspec --depth=0" 2>/dev/null || true

    # Rebuild with cache-busting to force fresh npm install
    print_info "Rebuilding image with latest OpenCode and OpenSpec..."
    docker build --build-arg "OPENCODE_BUILD_TIME=$(date +%s)" -t "$IMAGE_NAME" "$SCRIPT_DIR"

    # Show new version after update
    print_info "Updated OpenCode version:"
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "source \$NVM_DIR/nvm.sh && npm list -g opencode-ai --depth=0" 2>/dev/null || true
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "source \$NVM_DIR/nvm.sh && npm list -g @fission-ai/openspec --depth=0" 2>/dev/null || true

    print_success "OpenCode updated successfully"
}

# Function to clean up Docker image
clean_image() {
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        print_info "Removing Docker image '$IMAGE_NAME'..."
        docker rmi "$IMAGE_NAME"
        print_success "Docker image removed"
    else
        print_info "Docker image '$IMAGE_NAME' does not exist"
    fi
}

# Function to show or edit configuration
show_config() {
    local subcommand="${1:-show}"

    case "$subcommand" in
        show)
            parse_config
            print_config
            ;;
        edit)
            if [ -z "$EDITOR" ]; then
                print_error "EDITOR environment variable is not set"
                exit 1
            fi
            if [ ! -f "$CONFIG_FILE" ]; then
                print_warning "Config file does not exist. Running setup first..."
                "$SCRIPT_DIR/setup.sh"
            else
                "$EDITOR" "$CONFIG_FILE"
            fi
            ;;
        path)
            echo "$CONFIG_FILE"
            ;;
        *)
            print_error "Unknown config subcommand: $subcommand"
            echo "Usage: $0 config [show|edit|path]"
            exit 1
            ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
OpenCode Docker Wrapper

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    run [DIR]           Run OpenCode in Docker (default: current directory)
    auth                Run OpenCode authentication (opencode auth login)
    build               Build the Docker image
    update              Update OpenCode to the latest version
    version             Show OpenCode version in the container
    config [show|edit|path]  Show, edit, or print config file path
    clean               Remove the Docker image
    help                Show this help message

Environment Variables:
    DRY_RUN=true        Print the Docker command without executing it

Examples:
    $0 run                          # Run in current directory
    $0 run /path/to/project         # Run in specific directory
    $0 auth                         # Authenticate with your LLM provider
    $0 build                        # Build the Docker image
    $0 update                       # Update OpenCode to latest version
    $0 config show                  # Show current configuration
    $0 config edit                  # Edit config in \$EDITOR
    $0 clean                        # Remove Docker image
    DRY_RUN=true $0 run             # Show Docker command without running

Getting Started:
    1. ./setup.sh                   # First-time setup (creates config directories)
    2. $0 build                     # Build the Docker image
    3. $0 auth                      # Authenticate with your LLM provider
    4. $0 run /path/to/project      # Run OpenCode

Security Features:
    - Isolated environment: only access to mounted project directory
    - Read-only config mounts: configuration files are mounted read-only
    - Non-root user: runs as non-root user inside container
    - Automatic cleanup: containers are removed on exit (--rm)

OpenSpec (Spec-Driven Development):
    When enabled (setting.openspec_support=true in config), OpenSpec is available
    inside the container. On first run for a project, 'openspec init --tools opencode'
    is automatically executed. On every run, 'openspec update' regenerates instruction
    files to stay in sync with the installed CLI version.
    See: https://github.com/Fission-AI/OpenSpec/

Note: Docker socket is mounted for Docker-in-Docker support. This grants the
container full access to the host Docker daemon. Disable by removing the socket
mount in the config if not needed.

For more information, see README.md
EOF
}

# Function to show version
show_version() {
    check_image "$IMAGE_NAME" || exit 1
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "source \$NVM_DIR/nvm.sh && opencode --version"

    # Show OpenSpec version if support is enabled
    parse_config
    if [ "$OPENSPEC_SUPPORT" = true ]; then
        print_info "OpenSpec version:"
        docker run --rm --entrypoint bash "$IMAGE_NAME" -c "command -v openspec >/dev/null 2>&1 && openspec --version || echo 'openspec not found in image'"
    fi
}

# Main script logic
main() {
    check_docker

    local command="${1:-run}"
    shift || true

    case "$command" in
        run)
            check_config
            run_opencode "$@"
            ;;
        auth)
            run_auth
            ;;
        build)
            build_image
            ;;
        update)
            update_opencode
            ;;
        version)
            show_version
            ;;
        config)
            show_config "$@"
            ;;
        clean)
            clean_image
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
