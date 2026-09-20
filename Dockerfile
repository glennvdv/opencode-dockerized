# Use Debian slim as lightweight Linux base
# Note: We only install Docker CLI to use host's Docker daemon via mounted socket
FROM debian:bookworm-slim

# Parameterize tool versions for easier updates
ARG NVM_VERSION=v0.40.1
ARG JAVA_11_VERSION=11.0.25-tem
ARG JAVA_17_VERSION=17.0.13-tem
ARG JAVA_21_VERSION=21.0.5-tem
ARG JAVA_25_VERSION=25.0.3-tem

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

# Install SDKMAN and Java LTS versions (11, 17, 21) as coder user; default is 21
USER coder
WORKDIR /home/coder
RUN curl -s "https://get.sdkman.io" | bash && \
    bash -c "source /home/coder/.sdkman/bin/sdkman-init.sh && \
    sdk install java ${JAVA_11_VERSION} && \
    sdk install java ${JAVA_17_VERSION} && \
    sdk install java ${JAVA_21_VERSION} && \
    sdk install java ${JAVA_25_VERSION} && \
    sdk default java ${JAVA_21_VERSION}"

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

# Install OpenCode and OpenSpec globally
# OpenSpec: Spec-driven development (SDD) for AI coding assistants
# See: https://github.com/Fission-AI/OpenSpec/
# ARG OPENCODE_BUILD_TIME is only passed during 'update' to bust cache
ARG OPENCODE_BUILD_TIME=0
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g opencode-ai@latest @fission-ai/openspec@latest"

# Switch back to root for entrypoint setup
USER root

# Create necessary directories with proper permissions
RUN mkdir -p /home/coder/.config/opencode && \
    mkdir -p /home/coder/.config/openspec && \
    mkdir -p /home/coder/.local/share/opencode && \
    mkdir -p /home/coder/.local/state/opencode && \
    mkdir -p /home/coder/.cache/opencode && \
    mkdir -p /home/coder/.cache/oh-my-opencode && \
    mkdir -p /home/coder/.cache/openspec && \
    mkdir -p /home/coder/.gradle && \
    mkdir -p /home/coder/.npm && \
    mkdir -p /home/coder/.m2 && \
    chown -R coder:coder /home/coder

# Default working directory (overridden at runtime by --workdir)
WORKDIR /

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint (runs as root, then switches to coder)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command is to run opencode
CMD ["opencode"]
