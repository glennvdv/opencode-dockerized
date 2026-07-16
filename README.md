# OpenCode Dockerized - Secure Sandbox Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Run OpenCode in a secure, isolated Docker container with controlled access to your projects. This setup provides OpenCode with just enough access to be useful while maintaining strong security boundaries.

## Table of Contents

- [Security Features](#-security-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Usage](#-usage)
- [Configuration](#-configuration)
- [Portability & Sharing](#-portability--sharing)
- [Advanced Usage](#-advanced-usage)
- [Performance Optimizations](#-performance-optimizations)
- [Testcontainers Support](#-testcontainers-support)
- [Troubleshooting](#-troubleshooting)
- [File Reference](#-file-reference)

## 🔒 Security Features

- **Isolated Environment** - OpenCode only has access to the mounted project directory
- **Read-only Configuration** - All configuration files are mounted read-only (except session storage)
- **Session Persistence** - Logs and project session data persist across container restarts
- **Non-root User** - Runs as non-root user with UID/GID matching your host user
- **Limited Blast Radius** - Commands like `rm -rf .` only affect the project directory, not your entire system

## 📋 Prerequisites

1. **Docker** installed and running
2. **Optional configuration files** (if you have them):
   - `~/.gradle/gradle.properties` - Gradle configuration
   - `~/.npmrc` - NPM configuration

**No local OpenCode installation required!** Authentication and all OpenCode operations run through Docker.

## 🚀 Quick Start

### First-Time Setup

```bash
# 1. Navigate to the setup directory
cd /path/to/opencode-dockerized

# 2. Run setup script (creates config directories, installs globally)
./setup.sh

# 3. Build the Docker image
opencode-dockerized build

# 4. Authenticate with your LLM provider (no local OpenCode needed!)
opencode-dockerized auth

# 5. Run OpenCode in your project (from any directory!)
opencode-dockerized run
# or
opencode-dockerized run /path/to/your/project
```

### Authentication

**No local OpenCode installation required!** You can authenticate directly through Docker:

```bash
# Authenticate with your LLM provider (Anthropic, OpenAI, etc.)
./opencode-dockerized.sh auth

# This will:
# - Run 'opencode auth login' inside the container
# - Save credentials to ~/.local/share/opencode on your host
# - Make authentication available to all future OpenCode runs
```

Your authentication is stored on the host machine and persists across container restarts.

### Daily Usage

```bash
# Run in current directory (works from anywhere after setup)
opencode-dockerized run

# Run in specific project
opencode-dockerized run ~/projects/my-app

# Check version
opencode-dockerized version

# Update OpenCode
opencode-dockerized update
```

### Global Installation

The `setup.sh` script offers to install `opencode-dockerized` globally by creating a symlink in `~/.local/bin`. This means you can run `opencode-dockerized` from any directory without navigating to the project first.

If you skipped global installation during setup, you can do it manually:

```bash
# Create symlink (one-time)
mkdir -p ~/.local/bin
ln -sf /path/to/opencode-dockerized/opencode-dockerized.sh ~/.local/bin/opencode-dockerized

# Ensure ~/.local/bin is in PATH (add to ~/.bashrc or ~/.zshrc if not)
export PATH="$HOME/.local/bin:$PATH"
```

### Create an Alias (Alternative)

If you prefer aliases over the global symlink:

```bash
# For Bash users - add to ~/.bashrc
echo "alias ocd='/path/to/opencode-dockerized/opencode-dockerized.sh'" >> ~/.bashrc
echo "alias ocdr='/path/to/opencode-dockerized/opencode-dockerized.sh run'" >> ~/.bashrc
source ~/.bashrc

# For Zsh users - add to ~/.zshrc
echo "alias ocd='/path/to/opencode-dockerized/opencode-dockerized.sh'" >> ~/.zshrc
echo "alias ocdr='/path/to/opencode-dockerized/opencode-dockerized.sh run'" >> ~/.zshrc
source ~/.zshrc

# Then use it anywhere
cd ~/my-project
ocd run
```

### Shell Completion (Optional)

Autocompletion support is available for both Bash and Zsh:

**For Bash:**
```bash
# Source the completion file
source /path/to/opencode-dockerized/completions/bash.sh

# Or add to ~/.bashrc for permanent installation
echo "source /path/to/opencode-dockerized/completions/bash.sh" >> ~/.bashrc
```

**For Zsh:**
```bash
# Source the completion file
source /path/to/opencode-dockerized/completions/zsh.sh

# Or add to ~/.zshrc for permanent installation
echo "source /path/to/opencode-dockerized/completions/zsh.sh" >> ~/.zshrc

# For system-wide installation (requires sudo)
sudo cp /path/to/opencode-dockerized/completions/zsh.sh /usr/local/share/zsh/site-functions/_opencode-dockerized
```

After installation, you'll get:
- Command completion (`run`, `build`, `update`, `version`, `auth`, `config`, `clean`, `help`)
- Subcommand completion for `config` (`show`, `edit`, `path`)
- Directory completion for the `run` command
- Helpful descriptions for each command
- Works with `opencode-dockerized.sh`, the global `opencode-dockerized` command, and the `ocd` alias

## 📖 Usage

### Available Commands

```bash
opencode-dockerized build          # Build Docker image
opencode-dockerized auth           # Authenticate with LLM provider
opencode-dockerized run [DIR]      # Run OpenCode (default: current dir)
opencode-dockerized update         # Update OpenCode version
opencode-dockerized version        # Show version
opencode-dockerized config show    # Show parsed configuration
opencode-dockerized config edit    # Edit config in $EDITOR
opencode-dockerized config path    # Print config file path
opencode-dockerized clean          # Remove the Docker image
opencode-dockerized help           # Show help
```

### Dry Run Mode

Preview the `docker run` command without executing it:

```bash
DRY_RUN=true opencode-dockerized run /path/to/project
```

This prints the full Docker command with all volume mounts, environment variables, and flags — useful for debugging configuration issues.

### Alternative Runners

**Simple Runner**:
```bash
./run-simple.sh /path/to/your/project
```

### Inside the Container

Once OpenCode starts:

```bash
# Initialize OpenCode for the project
/init

# Ask questions about your code
How is authentication handled in @src/auth.ts

# Make changes
Add error handling to the login function

# Create plans before implementing
<TAB>  # Switch to Plan mode
Let's add a new feature for user profiles
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file (copy from `examples/.env.example`):

```bash
# Project directory to work on
PROJECT_DIR=/home/youruser/projects/myproject

# User/Group IDs (auto-detected by default)
HOST_UID=1000
HOST_GID=1000

# Terminal type
TERM=xterm-256color
```

### Volume Mounts

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `$PROJECT_DIR` | `$PROJECT_DIR` (with `$HOME` stripped) | read-write | Your project files |
| `~/.config/opencode/` | `/home/coder/.config/opencode/` | read-only | OpenCode & oh-my-opencode config, skills, commands, agents |
| `~/.local/share/opencode/` | `/home/coder/.local/share/opencode/` | read-write | Auth, logs, sessions, storage |
| `~/.local/state/opencode/` | `/home/coder/.local/state/opencode/` | read-write | TUI preferences, UI state |
| `~/.cache/opencode/` | `/home/coder/.cache/opencode/` | read-write | Provider package cache |
| `~/.cache/oh-my-opencode/` | `/home/coder/.cache/oh-my-opencode/` | read-write | Oh My OpenCode cache |
| `~/.gradle/gradle.properties` | `/home/coder/.gradle/gradle.properties` | read-only | Gradle config (optional) |
| `~/.npmrc` | `/home/coder/.npmrc` | read-only | NPM config (optional) |
| `~/.mcp-auth/` | `/home/coder/.mcp-auth/` | read-only | MCP authentication (optional) |


### Custom Global Configuration (Optional)

**Advanced Users:** You can configure custom volume mounts and environment variables to be automatically mounted in the container for all projects. This is useful for:

- **SSH agent forwarding**: Enable `setting.ssh_agent_support=true` for secure git over SSH (recommended)
- **Global git configuration**: Mount `~/.gitconfig` and global gitignore
- **Environment variables**: Pass API keys and other credentials

#### Getting Started with Custom Global Config

```bash
# During setup, you'll be prompted to add custom mounts and env vars
./setup.sh

# Or manually edit the config file
~/.config/opencode-dockerized/config
```

#### Config Format

Configuration is stored in `~/.config/opencode-dockerized/config` (INI format):

```ini
# Settings (built-in features)
# Format: setting.<name>=<value>
setting.ssh_agent_support=true
setting.openspec_support=true

# Custom volume mounts (read-only by default)
# Format: mount.<name>=<host_path>:<container_path>[:rw]
mount.gitconfig=~/.gitconfig:/home/coder/.gitconfig

# Environment variables to pass from host to container
# Format: env.<name>=<VARIABLE_NAME>
env.aws_bedrock=AWS_BEARER_TOKEN_BEDROCK
env.context7=CONTEXT7_API_KEY
```

#### Examples

**Example 1: Git configuration with SSH agent forwarding (Recommended)**
```ini
setting.ssh_agent_support=true
mount.gitconfig=~/.gitconfig:/home/coder/.gitconfig
```

**Example 2: API keys and credentials**
```ini
env.aws_bedrock=AWS_BEARER_TOKEN_BEDROCK
env.context7=CONTEXT7_API_KEY
```

**Note:** 
- **SSH Agent Support**: Use `setting.ssh_agent_support=true` instead of manually mounting `~/.ssh` or passing `SSH_AUTH_SOCK`
- Mounts are **read-only by default** (append `:rw` for read-write)
- Paths use `~` which is expanded to your home directory at runtime
- Environment variables must be set in your host environment to be passed
- Re-run `./setup.sh` anytime to update your custom configuration

## 🌍 Portability & Sharing

**This setup is fully portable!** It uses `$HOME` instead of hardcoded paths and works across different users and systems.

### How to Share

**Method 1: Git Repository (Recommended)**

```bash
git init
git add .
git commit -m "Initial OpenCode Docker setup"
git remote add origin <your-repo-url>
git push -u origin main
```

Users can then:
```bash
git clone <your-repo-url>
cd opencode-dockerized
./setup.sh              # Sets up config + installs globally
opencode-dockerized build
opencode-dockerized run
```

**Method 2: Archive Distribution**

```bash
tar -czf opencode-docker.tar.gz opencode-dockerized/
```

Users extract and run:
```bash
tar -xzf opencode-docker.tar.gz
cd opencode-dockerized
./setup.sh              # Sets up config + installs globally
opencode-dockerized build
```

**Method 3: Docker Hub**

```bash
docker build -t yourusername/opencode-dockerized:latest .
docker push yourusername/opencode-dockerized:latest
```

Update scripts to use `yourusername/opencode-dockerized:latest`

### Platform Compatibility

- **Linux**: Works out of the box
- **macOS**: Works with Docker Desktop
- **Windows (WSL2)**: Works in WSL2 terminal
- **Windows (Native)**: Use WSL2 instead

### What to Share

✅ Safe to share:
- Dockerfile
- Shell scripts
- Documentation
- .gitignore

❌ Never share:
- `.env` file with secrets
- Personal `auth.json`
- Personal `opencode.json` (may contain API keys)
- Personal `.gradle/gradle.properties`
- Personal `.npmrc`

## 🔍 Advanced Usage

### Oh My OpenCode Support

The container includes full support for [Oh My OpenCode](https://github.com/code-yeongyu/oh-my-opencode), the popular OpenCode plugin that provides specialized agents, LSP/AST tools, and productivity features.

**Pre-installed tools for oh-my-opencode:**
- **Bun** - Fast JavaScript runtime (preferred by oh-my-opencode)
- **ast-grep** - AST-aware code search and replace
- **tmux** - Terminal multiplexer for background agents and interactive sessions
- **lsof** - Port detection for tmux integration

**To use oh-my-opencode:**

1. Install the plugin on your host:
   ```bash
   bunx oh-my-opencode install
   ```

2. Your config at `~/.config/opencode/` is automatically mounted (read-only)

3. The cache directory `~/.cache/oh-my-opencode/` is mounted for persistence

**Features that work in Docker:**
- ✅ Sisyphus orchestrator agent
- ✅ Background agents (explore, librarian, oracle)
- ✅ AST-grep search/replace tools
- ✅ LSP tools (if language servers are installed)
- ✅ Tmux integration for interactive sessions
- ✅ All built-in skills and commands

For more information, see the [Oh My OpenCode documentation](https://github.com/code-yeongyu/oh-my-opencode).

### OpenSpec Support

The container includes [OpenSpec](https://github.com/Fission-AI/OpenSpec/), a spec-driven development (SDD) framework for AI coding assistants. OpenSpec helps you agree on what to build before any code is written.

**To enable OpenSpec:**

1. During setup, answer "y" when prompted for OpenSpec support:
   ```bash
   ./setup.sh
   # ... when prompted:
   # Enable OpenSpec support? (y/N): y
   ```

2. Or manually set in `~/.config/opencode-dockerized/config`:
   ```ini
   setting.openspec_support=true
   ```

**To use OpenSpec inside the container:**

```bash
# Initialize OpenSpec in your project (first time)
openspec init

# Start a new spec-driven change
/opsx:new add-dark-mode

# Fast-forward through planning artifacts
/opsx:ff

# Implement the planned tasks
/opsx:apply

# Archive completed change
/opsx:archive
```

**Features:**
- Spec-driven workflows with `/opsx:*` slash commands
- Supports 20+ AI coding assistants (including OpenCode)
- Lightweight spec layer for predictable AI coding
- Works within the mounted project directory

For more information, see the [OpenSpec documentation](https://github.com/Fission-AI/OpenSpec/).

### Python Development with uv

The container includes [uv](https://docs.astral.sh/uv/), a fast Python package manager and project manager. Use it for:

```bash
# Inside the container or via OpenCode commands
uv init my-project              # Create a new Python project
uv add requests                 # Add dependencies
uv run python script.py         # Run scripts in isolated environment
uv pip install package          # Install packages (pip-compatible)
uv venv                         # Create virtual environments
uv python install 3.12          # Install specific Python versions
```

**Benefits:**
- ✅ 10-100x faster than pip
- ✅ Deterministic dependency resolution
- ✅ Built-in virtual environment management
- ✅ Works seamlessly with existing pip workflows

For more information, see the [uv documentation](https://docs.astral.sh/uv/).

### Adding Additional Tools

Edit `Dockerfile`:

```dockerfile
RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    ca-certificates \
    python3 \
    python3-pip \
    jq \
    && rm -rf /var/lib/apt/lists/*
```

### Using Different Base Images

```dockerfile
# For Alpine (smaller size)
FROM node:20-alpine

# For specific Node version
FROM node:22-slim

# For Ubuntu-based
FROM ubuntu:22.04
# (then install Node.js manually)
```

## 🐛 Troubleshooting

### Permission Denied on Scripts

```bash
chmod +x opencode-dockerized.sh run-simple.sh setup.sh entrypoint.sh
```

### Config Files Not Found

```bash
# Run setup script
./setup.sh

# Or manually create
mkdir -p ~/.config/opencode ~/.local/share/opencode
echo '{}' > ~/.config/opencode/opencode.json  # or opencode.jsonc
```

### Permission Issues with Files

```bash
# Check if UID/GID match
echo "UID: $(id -u), GID: $(id -g)"

# Rebuild image
opencode-dockerized build
```

### Container Won't Start

```bash
# Check Docker is running
docker info

# View container logs
docker logs opencode-dockerized

# Remove and rebuild
docker rm -f opencode-dockerized
opencode-dockerized build
```

### OpenCode Not Updating

```bash
# Force rebuild without cache
docker build --no-cache -t opencode-dockerized:latest .

# Or use update command
opencode-dockerized update
```

## 📁 File Reference

### Core Files

- **`Dockerfile`** - Container image definition (Debian + Node.js/NVM + Java/SDKMAN + Bun + OpenCode + OpenSpec)
- **`entrypoint.sh`** - UID/GID mapping for file permissions

### User Scripts

- **`opencode-dockerized.sh`** - Main wrapper with all features (build, run, auth, update, version, config, clean, help)
- **`run-simple.sh`** - Simplified runner script
- **`setup.sh`** - First-time initialization (creates config directories, prompts for custom config)

### Shared Modules

- **`config-lib.sh`** - Shared configuration library (sourced by other scripts, handles mounts and env vars)

### Shell Completion (`completions/`)

- **`completions/bash.sh`** - Bash shell completion script
- **`completions/zsh.sh`** - Zsh shell completion script

### Examples (`examples/`)

- **`examples/.env.example`** - Template for environment variables
- **`examples/config.example`** - Example custom configuration file

### Configuration
- **`.gitignore`** - Excludes sensitive files from Git
- **`.dockerignore`** - Excludes non-essential files from Docker build context

### How It Works

1. **Base Image**: Uses Debian Bookworm slim for minimal footprint
2. **Docker CLI Only**: Installs only Docker CLI (uses host's Docker daemon via socket)
3. **Development Tools**: Includes Node.js (via NVM), Java (via SDKMAN), Python tooling (via uv), Bun, ast-grep, tmux, Git, and essential CLI tools
4. **OpenCode & OpenSpec Installation**: Installs latest OpenCode and OpenSpec via npm
5. **Oh My OpenCode Support**: Pre-configured with tools needed for oh-my-opencode plugin (ast-grep, tmux, bun)
6. **User Management**: Creates non-root `coder` user with UID/GID matching
7. **Entrypoint**: Adjusts permissions and switches to non-root user
8. **Volume Mounting**: Mounts only necessary directories with appropriate permissions

### The Blast Radius Concept

If OpenCode runs a dangerous command like `rm -rf .`:

- ❌ **Without Docker**: Could delete your entire home directory
- ✅ **With Docker**: Only affects the mounted project directory

This significantly reduces risk while maintaining full functionality.

## 📚 Additional Resources

- [OpenCode Documentation](https://opencode.ai/docs)
- [OpenCode GitHub Repository](https://github.com/sst/opencode)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

## ⚠️ Important Notes

1. **Docker Socket**: Container uses host's Docker daemon via mounted socket (no privileged mode needed)
2. **Network Access**: Container uses host network mode by default for convenience
3. **Configuration Updates**: Config files are read-only. Modify on host and restart container
4. **Persistent Data**: Only files in mounted project directory persist
5. **Not a Replacement for Caution**: Review OpenCode's actions, especially with `--allow-all-tools`

## 🚀 Performance Optimizations

This setup is optimized for minimal overhead:

- **Docker CLI Only**: Only installs Docker CLI (not the full daemon), saving ~200MB
- **Host Docker Daemon**: Uses your existing Docker daemon via socket mounting
- **No Privileged Mode**: No need for `--privileged` flag or Docker-in-Docker
- **Shared Resources**: Shares Docker images/containers with host (no duplication)
- **Fast Startup**: No daemon initialization delay

## 🧪 Testcontainers Support

**Full Testcontainers support is included!** Your integration tests can spin up Docker containers.

### How It Works

When you run tests with Testcontainers (Java, Node.js, Python, etc.):

1. Testcontainers library detects the Docker socket at `/var/run/docker.sock`
2. Containers are created on your **host's Docker daemon** (not inside the OpenCode container)
3. Test containers appear in `docker ps` on your host machine
4. Containers are automatically cleaned up after tests complete

### Example Use Cases

```java
// Java/Spring Boot with Testcontainers
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

@Container
static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
    .withExposedPorts(6379);
```

```javascript
// Node.js with Testcontainers
const { GenericContainer } = require("testcontainers");

const container = await new GenericContainer("postgres:15-alpine")
  .withExposedPorts(5432)
  .start();
```

### Benefits

✅ **Works out of the box** - No special configuration needed  
✅ **Fast performance** - Containers run directly on host (no nested virtualization)  
✅ **Shared images** - Downloaded images are shared with your host Docker  
✅ **Easy debugging** - Use `docker ps` and `docker logs` on your host to inspect test containers  
✅ **Network access** - Test containers can communicate with your application  

### Important Notes

- Test containers run on the **host**, not inside the OpenCode container
- Cleanup happens automatically via Testcontainers' cleanup hooks
- Volume mounts in test containers use host paths, not container paths
- Network modes (bridge, host) work as expected

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Software

This project uses and packages the following third-party software:

- **[OpenCode](https://github.com/sst/opencode)** - Apache 2.0 License (packaged in container)
- **[OpenSpec](https://github.com/Fission-AI/OpenSpec/)** - MIT License (packaged in container)
- **[Oh My OpenCode](https://github.com/code-yeongyu/oh-my-opencode)** - MIT License (optional plugin support)
- **Docker CLI** - Apache 2.0 License (packaged in container)
- **Node.js** - MIT License (packaged in container)
- **Bun** - MIT License (packaged in container)
- **ast-grep** - MIT License (packaged in container)

Each component retains its original license. This wrapper script and configuration are provided under the MIT License.

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Make your changes** and test them
4. **Commit your changes** (`git commit -m 'Add amazing feature'`)
5. **Push to the branch** (`git push origin feature/amazing-feature`)
6. **Open a Pull Request**

### Guidelines

- Follow existing shell script style (see [AGENTS.md](AGENTS.md) for conventions)
- Test changes with both `opencode-dockerized.sh` and `run-simple.sh`
- Update documentation for new features
- Keep security as a priority

### Reporting Issues

Found a bug or have a suggestion? Please [open an issue](../../issues) with:
- Clear description of the problem/suggestion
- Steps to reproduce (for bugs)
- Your environment (OS, Docker version)

---

**Made with 🔒 by developers who like AI but trust carefully**
