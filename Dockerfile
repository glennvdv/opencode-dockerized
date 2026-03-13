# Use Debian slim as lightweight Linux base
# Note: We only install Docker CLI to use host's Docker daemon via mounted socket
FROM debian:bookworm-slim

# Parameterize tool versions for easier updates
ARG NVM_VERSION=v0.40.1
ARG JAVA_VERSION=21.0.5-tem

# Install base dependencies and useful CLI tools for coding agents
RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    ca-certificates \
    sudo \
    zip \
    unzip \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    ripgrep \
    fd-find \
    jq \
    tree \
    less \
    procps \
    tmux \
    lsof \
    && rm -rf /var/lib/apt/lists/*

# be ready to authenticate with github
RUN (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y

# install tools for scraping youtube videos
RUN sudo apt-get install -y yt-dlp ffmpeg

# install godot for game development work
ENV GODOT_VERSION="4.6.1"
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.arm64.zip
RUN unzip -o Godot_v${GODOT_VERSION}-stable_linux.arm64.zip
RUN chmod +x Godot_v${GODOT_VERSION}-stable_linux.arm64
RUN sudo mv Godot_v${GODOT_VERSION}-stable_linux.arm64 /usr/local/bin/godot
RUN rm -f Godot_v${GODOT_VERSION}-stable_linux.arm64.zip
# set this for the MCP server
ENV GODOT_PATH="/usr/local/bin/godot"

# Install Docker CLI only (uses host Docker daemon via mounted socket)
# We don't need docker-ce (daemon) or containerd.io since we use the host's Docker
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
# Note: Docker socket group membership is handled dynamically in entrypoint.sh
# based on the host's actual Docker socket GID
RUN useradd -m -s /bin/bash -u 1000 coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install SDKMAN and Java as coder user
USER coder
WORKDIR /home/coder

# authenticate git so it can perform commands right off the bat
ADD .git-auth .
RUN gh config set -h github.com git_protocol https
RUN gh auth login --with-token < .git-auth
# setup git to use gh for auth
RUN gh auth setup-git

# clear out the file for security purposes
RUN rm .git-auth

RUN git config --global --type bool push.autoSetupRemote true

# maybe these can be parameterized at some point
RUN git config --global user.email "personaaichat@gmail.com" && git config --global user.name "OpenCode-Ryan"

# TODO: would be cool to add in auto-branch detection as well, i.e. start from this branch when you startup

RUN curl -s "https://get.sdkman.io" | bash && \
    bash -c "source /home/coder/.sdkman/bin/sdkman-init.sh && \
    sdk install java ${JAVA_VERSION} && \
    sdk default java ${JAVA_VERSION}"

# Install NVM and Node.js LTS as coder user
ENV NVM_DIR="/home/coder/.nvm"
RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash && \
    bash -c "source $NVM_DIR/nvm.sh && \
    nvm install --lts && \
    nvm alias default node && \
    nvm use default && \
    ln -sf \$(dirname \$(which node)) $NVM_DIR/default"

# Install uv (Python package manager) as coder user
# See: https://docs.astral.sh/uv/getting-started/installation/
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install ast-grep for AST-aware code search/replace (used by oh-my-opencode)
# The npm package @ast-grep/cli provides the 'ast-grep' and 'sg' binaries
# See: https://ast-grep.github.io/
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g @ast-grep/cli"

# Install Bun (fast JavaScript runtime and package manager)
# Required by oh-my-opencode for optimal performance
# See: https://bun.sh/
RUN curl -fsSL https://bun.sh/install | bash
ENV BUN_INSTALL="/home/coder/.bun"

# Add nvm, node, sdkman, uv, bun, and ast-grep to PATH
# Node.js is available via the NVM default symlink created above
ENV PATH="$BUN_INSTALL/bin:$NVM_DIR/default:/home/coder/.local/bin:/home/coder/.sdkman/candidates/java/current/bin:$PATH"
ENV JAVA_HOME="/home/coder/.sdkman/candidates/java/current"

# Install OpenCode globally
# ARG OPENCODE_BUILD_TIME is only passed during 'update' to bust cache
ARG OPENCODE_BUILD_TIME=0
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g opencode-ai@latest"

# bundle in the MCP server (if you want to use it)
RUN mkdir /home/coder/mcp
RUN git clone https://github.com/Coding-Solo/godot-mcp.git
RUN mv godot-mcp /home/coder/mcp/godot-mcp
WORKDIR /home/coder/mcp/godot-mcp
RUN npm install
RUN npm run build

# Switch back to root for entrypoint setup
USER root

# Create necessary directories with proper permissions
RUN mkdir -p /home/coder/.config/opencode && \
    mkdir -p /home/coder/.local/share/opencode && \
    mkdir -p /home/coder/.cache/opencode && \
    mkdir -p /home/coder/.cache/oh-my-opencode && \
    mkdir -p /home/coder/.gradle && \
    mkdir -p /home/coder/.npm && \
    mkdir -p /home/coder/.m2 && \
    chown -R coder:coder /home/coder

# Set working directory
WORKDIR /workspace

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint (runs as root, then switches to coder)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command is to run opencode
CMD ["opencode"]
