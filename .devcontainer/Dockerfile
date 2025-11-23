FROM ubuntu:22.04

# Container version labels for runtime identification
LABEL devcontainer.version="1.0.0"
LABEL devcontainer.template="frappe-devcontainer-1.0.0"
LABEL devcontainer.description="Frappe DevContainer Template"
LABEL devcontainer.created="2025-01-16T00:00:00Z"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Build arguments for user management
ARG USER_NAME=frappe
ARG USER_UID=1000
ARG USER_GID=1000

# Install system-level dependencies for Frappe
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    # Python development
    python3-dev \
    python3-pip \
    python3.10-venv \
    libffi-dev \
    libssl-dev \
    # Image processing
    libjpeg-dev \
    zlib1g-dev \
    # Database client
    libmariadb-dev \
    libmariadb-dev-compat \
    mariadb-client \
    # PDF generation
    wkhtmltopdf \
    xvfb \
    libfontconfig1 \
    # Version control
    git \
    # Utilities
    curl \
    wget \
    jq \
    iputils-ping \
    net-tools \
    cron \
    # User management
    sudo \
    # Shells
    zsh \
    bash \
    # Dev tools
    vim \
    nano \
    less \
    tree \
    # Locales
    locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure locales
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Yarn package manager
RUN npm install -g yarn

# Install AI assistant CLIs (requires Node.js/npm)
RUN npm install -g @anthropic-ai/claude-code @openai/codex || \
    echo "AI CLI tools installation failed, skipping"

# Install Python packages for Frappe development
RUN pip install --upgrade pip \
    && pip install \
    redis \
    mysqlclient \
    requests \
    click \
    aiohttp \
    gevent \
    eventlet \
    PyJWT \
    black \
    flake8 \
    isort \
    pylint \
    pytest \
    ipython \
    frappe-bench

# ========================================
# USER SETUP - Match host UID/GID
# ========================================

# Create user with matching host UID/GID (with conflict handling)
RUN set -eux && \
    if getent passwd "$USER_UID" >/dev/null; then \
        userdel --force --remove $(getent passwd "$USER_UID" | cut -d: -f1) || true; \
    fi && \
    if getent group "$USER_GID" >/dev/null; then \
        groupdel $(getent group "$USER_GID" | cut -d: -f1) || true; \
    fi && \
    groupadd --gid $USER_GID $USER_NAME && \
    useradd --uid $USER_UID --gid $USER_GID -m -s /bin/zsh $USER_NAME && \
    echo $USER_NAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USER_NAME && \
    chmod 0440 /etc/sudoers.d/$USER_NAME

# Install Oh My Zsh for better developer experience
USER $USER_NAME
RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended || \
    echo "Oh My Zsh installation failed, using default zsh"

# Add bench to PATH
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# Override bash profile to run zsh instead of bash
RUN echo '# Force zsh when bash is requested' >> ~/.bash_profile && \
    echo 'if [ -n "$PS1" ] && [ -z "$ZSH_VERSION" ]; then' >> ~/.bash_profile && \
    echo '    exec /bin/zsh -l' >> ~/.bash_profile && \
    echo 'fi' >> ~/.bash_profile && \
    echo '' >> ~/.bash_profile && \
    echo '# Fallback: source bashrc if we somehow end up in bash' >> ~/.bash_profile && \
    echo '[ -f ~/.bashrc ] && source ~/.bashrc' >> ~/.bash_profile

# Safety command: Ensure the user shell is set to zsh
USER root
RUN chsh -s /bin/zsh $USER_NAME

# Switch back to user
USER $USER_NAME

# Create workspace directories with proper ownership
RUN sudo mkdir -p /workspace/development && \
    sudo chown -R $USER_NAME:$USER_NAME /workspace

# Set working directory
WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
