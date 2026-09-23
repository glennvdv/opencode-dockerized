#!/bin/bash

# Alternative simple runner for OpenCode Docker
# Uses shared volume logic from config-lib.sh but with minimal overhead

set -e

# Resolve symlinks so SCRIPT_DIR points to the real source directory
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
IMAGE_NAME="opencode-dockerized:latest"

# Source the shared config module
source "$SCRIPT_DIR/config-lib.sh"

# Show help if requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ]; then
    cat << EOF
OpenCode Docker Simple Runner

Usage: $(basename "$0") [DIR]

Runs OpenCode in a Docker container with a simplified setup.
Uses the same shared configuration as opencode-dockerized.sh.

Arguments:
    DIR     Project directory to mount (default: current directory)

Options:
    --help, -h    Show this help message

For full feature set, use opencode-dockerized.sh instead.
EOF
    exit 0
fi

# Get project directory (default to current directory)
PROJECT_DIR="${1:-$(pwd)}"

# Validate project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    config_error "Project directory does not exist: $PROJECT_DIR"
    exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Build image if it doesn't exist
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    config_info "Docker image not found, building..."
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
fi

# Parse custom config
parse_config
build_mount_args
build_env_args
build_common_docker_args

# Build standard volume mount arguments (with Docker socket)
build_standard_volume_args "$PROJECT_DIR" true

# Generate unique container name
local_dir_name=$(sanitize_container_name "$(basename "$PROJECT_DIR")")
local_random_suffix=$(generate_random_suffix)
CONTAINER_NAME="opencode-${local_dir_name}-${local_random_suffix}"

# Run OpenCode in Docker
# CONTAINER_WORKDIR is set by build_standard_volume_args (host path with $HOME stripped)
# --standalone keeps the server inside the container instead of attaching to a host server
docker run -it \
    --name "$CONTAINER_NAME" \
    --workdir "$CONTAINER_WORKDIR" \
    -e "OPENCODE_WORKDIR=$CONTAINER_WORKDIR" \
    "${DOCKER_COMMON_ARGS[@]}" \
    "${VOLUME_ARGS[@]}" \
    "${GIT_WORKTREE_ARGS[@]}" \
    "${DOCKER_MOUNT_ARGS[@]}" \
    "${DOCKER_ENV_ARGS[@]}" \
    "$IMAGE_NAME" \
    opencode --standalone
