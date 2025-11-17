# Frappe Development Environment - Warp Instructions

## Project Structure

Complete production-ready Frappe development environment with full Docker Compose stack:

### Core Services
- **Frappe Web Container**: Custom devcontainer (main workspace)
- **MariaDB 10.6**: Database with health checks
- **Redis Cache**: LRU memory cache (256MB limit)
- **Redis Queue**: Job queue storage
- **Redis SocketIO**: Real-time state management

### Background Processing
- **Worker Default**: Default queue processor
- **Worker Short**: Short-running tasks
- **Worker Long**: Long-running tasks  
- **Scheduler**: Cron jobs and scheduled tasks

### Additional Services
- **SocketIO Server**: WebSocket handler
- **Nginx**: Reverse proxy on port 8080
- **AI Tools**: Claude Code, Cody, Continue, Warp

## Devcontainer Files

- **Dockerfile**: Custom Frappe dev image with development tools
- **docker-compose.yml**: Full Frappe stack orchestration
- **devcontainer.json**: VSCode integration with AI tools
- **nginx.conf**: Reverse proxy configuration
- **.env.example**: Environment template (copy to .env)
- **setup-frappe.sh**: Automated Frappe bench initialization

## Quick Start

```bash
# 1. Copy environment file
cp .devcontainer/.env.example .devcontainer/.env

# 2. Open in VSCode and reopen in container
# (VSCode will build and start all services)

# 3. Initialize Frappe (first time only)
./.devcontainer/setup-frappe.sh

# 4. Start Frappe development server
cd /workspace/development/frappe-bench
bench start
```

## Architecture Notes

- Main workspace mounted at `/workspace`
- Frappe bench created at `/workspace/development/frappe-bench`
- User configured to match host user via `${localEnv:USER}`
- All services communicate over `frappe-network`
- Data persists in named Docker volumes
- Accessible at http://localhost:8080

## AI Development Tools

- **Claude Code** (anthropic.claude-dev)
- **Cody** (sourcegraph.cody-ai) 
- **Continue** (continue.continue)
- All pre-configured in devcontainer.json extensions

## Environment Variables

Key variables in `.devcontainer/.env`:
- `DB_PASSWORD`: MariaDB root password
- `USER`, `UID`, `GID`: Match host user for permissions
- `FRAPPE_SITE_NAME`: Default site name
- `ADMIN_PASSWORD`: Administrator password

## Git Repository

This is a standalone project directory that can be initialized as a git repository if needed.
