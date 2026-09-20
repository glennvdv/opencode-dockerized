# Agent Guidelines for OpenCode Dockerized

## Project Overview

Shell script-based Docker wrapper for running [OpenCode](https://opencode.ai) in secure, isolated containers. Sandboxes OpenCode so its blast radius is limited to the mounted project directory. Supports [Oh My OpenCode](https://github.com/code-yeongyu/oh-my-opencode) plugin and [OpenSpec](https://github.com/Fission-AI/OpenSpec/) spec-driven development. All source is Bash shell scripts and a Dockerfile — no compiled code, no JS/Python source, no package manager files.

**Key files:**
- `opencode-dockerized.sh` — Main wrapper (build, run, auth, update, config, clean commands)
- `config-lib.sh` — Shared library sourced by other scripts (config parsing, mount/env arg building, shared volume logic, interactive prompts). **Not executable directly.**
- `Dockerfile` — Container image (Debian bookworm-slim + Node.js/NVM + Java 21/SDKMAN + Bun + OpenCode + OpenSpec)
- `entrypoint.sh` — Container entrypoint (UID/GID mapping, Docker socket permissions)
- `setup.sh` — First-time config directory initialization
- `run-simple.sh` — Simplified alternative runner (uses shared logic from config-lib.sh)
- `config.example` — Example user config (INI-style), in `examples/`
- `.dockerignore` — Excludes non-essential files from Docker build context
- Completion scripts: `completions/{bash,zsh}.sh`

## Build / Test / Lint Commands

```bash
# Core operations
./opencode-dockerized.sh build          # Build Docker image (uses layer cache)
./opencode-dockerized.sh run [DIR]      # Run OpenCode (default: current dir)
./opencode-dockerized.sh auth           # Authenticate OpenCode
./opencode-dockerized.sh update         # Update OpenCode (cache-busting rebuild)
./opencode-dockerized.sh version        # Show OpenCode version
./opencode-dockerized.sh config show    # Show parsed configuration
./opencode-dockerized.sh config edit    # Edit config in $EDITOR
./opencode-dockerized.sh config path    # Print config file path
./opencode-dockerized.sh clean          # Remove Docker image
./opencode-dockerized.sh help           # Show help
DRY_RUN=true ./opencode-dockerized.sh run  # Print docker command without running

# Validation (no test framework exists — these are the only checks)
bash -n script.sh                       # Syntax-check one script
bash -n *.sh                            # Syntax-check all scripts
shellcheck script.sh                    # Lint one script (shellcheck not in repo; install separately)
shellcheck *.sh                         # Lint all scripts

# Docker operations
docker build -t opencode-dockerized:latest .                    # Manual build
docker build --no-cache -t opencode-dockerized:latest .         # Force rebuild (no cache)
docker run --rm opencode-dockerized:latest opencode --version   # Verify version
```

There are **no automated tests** — validate changes with `bash -n` and `shellcheck`.

## Code Style Guidelines

### File Header

Every executable shell script starts with:
```bash
#!/bin/bash
set -e  # Exit on first error
```

**Exception:** `config-lib.sh` is a library file sourced by callers — it must **not** use `set -e` to avoid affecting callers' error handling.

### Script Initialization

Resolve own directory (following symlinks), then source shared module:
```bash
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/config-lib.sh"
```

### Naming Conventions

| Type              | Convention         | Examples                                      |
|-------------------|--------------------|-----------------------------------------------|
| Shell scripts     | kebab-case.sh      | `opencode-dockerized.sh`, `run-simple.sh`     |
| Functions         | snake_case         | `check_docker()`, `build_image()`             |
| Constants         | UPPER_SNAKE        | `IMAGE_NAME`, `SCRIPT_DIR`, `CONFIG_DIR`      |
| Local variables   | lower_snake        | `project_dir`, `container_name`               |
| Global arrays     | UPPER_SNAKE        | `CUSTOM_MOUNTS=()`, `DOCKER_MOUNT_ARGS=()`   |
| Booleans          | UPPER_SNAKE=false  | `SSH_AGENT_SUPPORT=false`, `OPENSPEC_SUPPORT=false` |
| Docker images     | kebab-case:tag     | `opencode-dockerized:latest`                  |
| Container names   | kebab-case-suffix  | `opencode-myproject-abc123`                   |

### Variable Handling

- **Always quote variables:** `"$variable"` not `$variable`
- **Command substitution:** `$()` not backticks
- **Declare and assign separately:** `local dir_name; dir_name=$(...)` (SC2155)
- **Absolute paths:** `SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"`
- **Defaults with `:=`:** `CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/opencode-dockerized}"`
- **Color defaults in modules:** `: "${RED:='\033[0;31m'}"` (avoid overwriting caller-defined values)
- **Use arrays for Docker args:** Never build docker args as strings — use arrays and `"${array[@]}"`

### Color Output / Logging

```bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
```

In `config-lib.sh`, use fallback wrappers that delegate to caller's functions if defined:
```bash
config_info() {
    if type print_info >/dev/null 2>&1; then print_info "$1"
    else echo -e "${BLUE}ℹ${NC} $1"; fi
}
```

### Error Handling

- Check prerequisites before operations (e.g., `check_docker`, `check_image` before Docker commands)
- Validate project directory exists before `cd`: `if [ ! -d "$dir" ]; then print_error ...; exit 1; fi`
- Print explicit error with `print_error()` then `exit 1`
- Suppress expected failures: `2>/dev/null || true`
- Graceful fallback in parsers: `load_config || return 0`
- Wrap `docker run` in error-handling: `if ! docker run ...; then print_error ...; exit 1; fi`
- Always use `read -r` to prevent backslash interpretation (SC2162)
- Validate env var names from config: `[[ "$var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]]`

### Shared Logic (config-lib.sh)

All volume mount logic lives in `config-lib.sh` to eliminate duplication:
- `build_standard_volume_args "$project_dir" [include_docker_socket]` — populates `VOLUME_ARGS` array
- `build_common_docker_args` — populates `DOCKER_COMMON_ARGS` array (--rm, --network host, UID/GID, TERM)
- `ensure_opencode_dirs` — creates required host directories
- `check_image "$IMAGE_NAME"` — validates Docker image exists
- `sanitize_container_name "$name"` — strips invalid Docker container name characters
- `generate_random_suffix` — produces random hex for unique container names

### Main Entry Point Pattern

```bash
main() {
    check_docker
    local command="${1:-run}"
    shift || true
    case "$command" in
        run)    check_config; run_opencode "$@" ;;
        build)  build_image ;;
        config) show_config "$@" ;;
        clean)  clean_image ;;
        help|--help|-h) show_help ;;
        *)      print_error "Unknown command: $command"; show_help; exit 1 ;;
    esac
}
main "$@"
```

### Config File Format

INI-style (`key.name=value`), parsed with `while IFS='=' read -r key value` loops:
```ini
setting.ssh_agent_support=true
setting.openspec_support=true
mount.gitconfig=~/.gitconfig:/home/coder/.gitconfig
env.aws_bedrock=AWS_BEARER_TOKEN_BEDROCK
```

### Dockerfile Conventions

- Base image: `debian:bookworm-slim` (pinned, not `latest`)
- Parameterize tool versions via `ARG`: `ARG NVM_VERSION=v0.40.1`, `ARG JAVA_VERSION=21.0.5-tem`
- Clean apt cache in same RUN layer: `&& rm -rf /var/lib/apt/lists/*`
- Install Docker CLI only (`docker-ce-cli`), never the daemon
- System packages as root; dev tools (NVM, SDKMAN, uv, Bun) as non-root `coder` user
- Non-root user: `useradd -m -s /bin/bash -u 1000 coder`
- Create NVM default symlink for PATH: `ln -sf $(dirname $(which node)) $NVM_DIR/default`
- Cache-busting `ARG OPENCODE_BUILD_TIME` only used by `update`, not regular `build`
- Use official installers from trusted sources

### Security Rules

- Config files mounted read-only (`:ro`); data directories read-write
- **Never commit:** `.env`, `auth.json`, `*.pem`, `*.key`, credentials
- Docker socket: mount host socket, no privileged mode, handle GID dynamically in entrypoint
- Run as non-root `coder` inside container; map UID/GID to match host via `entrypoint.sh`
- Use `--rm` for automatic container cleanup; `--network host` for simplicity
- Custom user mounts default to read-only
- Only pass environment variables explicitly listed in config
- Container names sanitized to prevent injection via directory names

## Volume Mounts Reference

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `$PROJECT_DIR` | `$PROJECT_DIR` (with `$HOME` stripped) | rw | Project files |
| `~/.config/opencode/` | `/home/coder/.config/opencode/` | ro | Config, skills, agents |
| `~/.local/share/opencode/` | `/home/coder/.local/share/opencode/` | rw | Auth, sessions |
| `~/.local/state/opencode/` | `/home/coder/.local/state/opencode` | rw | TUI preferences, UI state |
| `~/.cache/opencode/` | `/home/coder/.cache/opencode/` | rw | Provider cache |
| `~/.cache/oh-my-opencode/` | `/home/coder/.cache/oh-my-opencode/` | rw | Plugin cache |
| `~/.cache/openspec/` | `/home/coder/.cache/openspec/` | rw | OpenSpec cache (when enabled) |
| `~/.config/openspec/` | `/home/coder/.config/openspec/` | ro | OpenSpec config (when enabled) |
| `/var/run/docker.sock` | `/var/run/docker.sock` | rw | Docker socket |
