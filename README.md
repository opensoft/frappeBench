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

1. **Copy environment file**:
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env
   ```

2. **Open in VSCode**:
   - Open this folder in VSCode
   - Click "Reopen in Container" when prompted
   - Or use Command Palette: "Dev Containers: Reopen in Container"

3. **Initialize Frappe** (first time only):
   ```bash
   ./.devcontainer/setup-frappe.sh
   ```

4. **Start Frappe**:
   ```bash
   cd /workspace/development/frappe-bench
   bench start
   ```

5. **Access the site**:
   - Open browser to http://localhost:8080
   - Default credentials: Administrator / admin (or as set in .env)

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
bench --site site1.localhost install-app app_name

# Run migrations
bench --site site1.localhost migrate

# Access MariaDB
bench --site site1.localhost mariadb

# Clear cache
bench clear-cache
```

## Configuration

- `.devcontainer/.env`: Environment variables for containers
- `.devcontainer/devcontainer.json`: VSCode devcontainer config
- `.devcontainer/docker-compose.yml`: Container orchestration
- `.devcontainer/Dockerfile`: Custom dev container image

## Architecture

The devcontainer mounts the project at `/workspace` and creates a Frappe bench at `/workspace/development/frappe-bench`. All services communicate over the `frappe-network` Docker network.

## Notes

- User permissions are configured to match your host user
- Data persists in Docker volumes across container restarts
- The setup script is idempotent and safe to run multiple times
