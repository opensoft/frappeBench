# Frappe Development Environment

A complete Frappe development environment with devcontainer support for VSCode, Claude Code, Codex, and Warp.

## Prerequisites

- Docker and Docker Compose
- VSCode with Dev Containers extension
- Git

## Stack Components

### Core Services
- **Frappe Web Container**: Custom dev container with Frappe framework backend and development tools (this is where you work)
- **MariaDB**: Database server (10.6) with UTF-8 support
- **Redis Cache**: Memory cache with LRU eviction policy
- **Redis Queue**: Background job queue storage
- **Redis SocketIO**: Real-time communication state

### Background Processing
- **Worker Default**: Processes default queue jobs
- **Worker Short**: Handles short-running background tasks
- **Worker Long**: Handles long-running background tasks
- **Scheduler**: Manages cron jobs and scheduled tasks

### Additional Services
- **SocketIO Server**: Handles WebSocket connections for real-time features
- **Nginx**: Reverse proxy for HTTP/WebSocket routing

## Getting Started

1. **Create a workspace**:
   ```bash
   ./scripts/new-frappe-workspace.sh alpha
   ```
   This creates `workspaces/alpha/` with a workspace-specific `.devcontainer` and `.env`.

2. **Open the workspace in VSCode**:
   - Open `workspaces/alpha/` in VSCode
   - Click "Reopen in Container" when prompted
   - Or use Command Palette: "Dev Containers: Reopen in Container"

3. **Initialize Frappe** (first time only):
   ```bash
   ./scripts/setup-frappe.sh
   ```
   This runs automatically on first container build; re-run if needed.

4. **Start Frappe**:
   ```bash
   cd /workspace/bench
   bench start
   ```

5. **Access the site**:
   - Open browser to `http://localhost:${HOST_PORT}` from `workspaces/alpha/.devcontainer/.env`
   - Defaults: alpha → 8001, bravo → 8002
   - Credentials: Administrator / admin (or as set in `.devcontainer/.env`)

## Development

### AI Tools Included
- **Claude Code**: Anthropic's AI assistant
- **Cody**: Sourcegraph's AI coding assistant  
- **Continue**: Open-source AI code assistant

### Python Tools
- Black (formatter)
- isort (import organizer)
- flake8 (linter)
- pytest (testing)
- ipython (interactive shell)

### Bench Commands
```bash
# Create a new app
bench new-app app_name

# Install an app to site
bench --site ${SITE_NAME} install-app app_name

# Run migrations
bench --site ${SITE_NAME} migrate

# Access MariaDB
bench --site ${SITE_NAME} mariadb

# Clear cache
bench clear-cache
```

## Configuration

- `workspaces/<name>/.devcontainer/.env`: Environment variables for containers
- `workspaces/<name>/.devcontainer/devcontainer.json`: VSCode devcontainer config
- `workspaces/<name>/.devcontainer/docker-compose.yml`: Container orchestration
- `workspaces/<name>/.devcontainer/Dockerfile`: Custom dev container image

## Architecture

### Container Image Layers

frappeBench uses the workBenches multi-layer architecture:

**Layer 0** (`workbench-base:brett`) - System base from [workBenches](../../CONTAINER-ARCHITECTURE.md#layer-0-system-base-workbench-base)
- Ubuntu 24.04, git, editors (vim, neovim), modern CLI tools (zoxide, fzf, bat)

**Layer 1a** (`devbench-base:brett`) - Development tools from [workBenches](../../CONTAINER-ARCHITECTURE.md#layer-1a-development-base-devbench-base)
- Python 3, Node.js LTS, AI CLIs (Claude, Copilot, Gemini, OpenCode, Letta)
- Python dev tools (black, flake8, pytest, ipython)

**Layer 2** (`frappe-bench:brett`) - Frappe-specific tools (this bench)
- MariaDB client, Nginx, Redis tools
- Python profiling (py-spy, web-pdb)
- Network diagnostics (dig, nc)
- Log viewing (multitail)
- Frappe diagnostic aliases

### Service Architecture

The devcontainer mounts the project at `/workspace` and creates a Frappe bench at `/workspace/bench`. All services communicate over the `frappe-network` Docker network.

For detailed Layer 2 tools and rationale, see [Architecture Documentation](docs/ARCHITECTURE.md).

## Notes

- User permissions are configured to match your host user
- Data persists in Docker volumes across container restarts
- The setup script is idempotent and safe to run multiple times
