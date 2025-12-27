# Project Context

## Purpose
frappeBench is a multi-workspace Frappe Framework development environment using Docker devcontainers. It enables developers to run multiple isolated Frappe instances simultaneously with shared infrastructure (MariaDB, Redis), supporting parallel development across different projects or branches.

**Goals:**
- Provide rapid workspace provisioning for Frappe development
- Enable multiple concurrent isolated environments on a single machine
- Share infrastructure resources efficiently across workspaces
- Standardize developer environment setup with reproducible containers

## Tech Stack
- **Containerization**: Docker, Docker Compose
- **IDE Integration**: VSCode Dev Containers
- **Framework**: Frappe Framework v15
- **Database**: MariaDB 10.6 (shared instance)
- **Cache/Queue**: Redis Alpine (3 instances: cache, queue, socketio)
- **Reverse Proxy**: Nginx Alpine (production profile)
- **Scripting**: Bash (automation scripts)
- **Spec Management**: OpenSpec (spec-driven development)
- **Base Images**: Custom layered images (workbench-base → devbench-base → frappe-bench)

## Project Conventions

### Code Style
- **Shell Scripts**: Use `#!/usr/bin/env bash` shebang
- **Functions**: Document with inline comments describing purpose
- **Variables**: Use `UPPER_SNAKE_CASE` for environment variables, `lower_snake_case` for local variables
- **Error Handling**: Use `set -euo pipefail` where appropriate; check exit codes explicitly
- **Quoting**: Always quote variables (`"${VAR}"`) to prevent word splitting
- **Sourcing**: Use `source` keyword (not `.`) for library includes
- **Library Pattern**: Common utilities in `scripts/lib/` with `common.sh` as base

### Architecture Patterns

**Three-Layer Docker Image Architecture:**
```
Layer 0: workbench-base      (Ubuntu 24.04, git, vim, neovim, zoxide, fzf, bat)
    ↓
Layer 1a: devbench-base      (Python 3, Node.js LTS, AI CLIs, dev tools)
    ↓
Layer 2: frappe-bench        (MariaDB client, frappe-bench CLI, bench template)
```

**Shared Infrastructure Pattern:**
- Single `infrastructure/docker-compose.yml` runs MariaDB + Redis
- All workspaces connect via `frappe-network` Docker bridge
- Infrastructure starts automatically via `initializeCommand`

**Workspace Isolation:**
- Each workspace gets unique directory under `workspaces/<name>/`
- NATO alphabet naming (alpha, bravo, charlie...) for port mapping consistency
- Ports: alpha=8001, bravo=8002, etc. (base 8000 + alphabet index)
- Each workspace has independent `.devcontainer/` copied from template

**Idempotent Script Design:**
- All scripts check existing state before acting
- Safe to re-run without side effects
- Use marker files and state checks for operation tracking

### Testing Strategy
- **Smoke Tests**: `setup-frappe.sh` includes health checks and site validation
- **Manual Testing**: Workspace creation/deletion verified through scripts
- **No Automated Unit Tests**: Currently relies on idempotent design and manual verification
- **Recommended**: Add shellcheck and bats tests for script validation (future improvement)

### Git Workflow
- **Main Branch**: `main` is the primary development branch
- **Commit Style**: Conventional commits preferred (`feat:`, `fix:`, `docs:`, `chore:`)
- **PR Requirement**: Changes should go through pull requests
- **OpenSpec Integration**: Use spec-driven workflow for significant changes

## Domain Context

**Frappe Framework Concepts:**
- **Bench**: A directory containing the Frappe framework, sites, and apps
- **Site**: A Frappe installation with its own database (e.g., `dev.localhost`)
- **App**: A Frappe application module (erpnext, payments, dartwing)
- **DocType**: Frappe's data model abstraction (similar to Django models)

**Key Frappe Commands:**
- `bench init` - Initialize a new bench
- `bench new-site` - Create a new site
- `bench get-app` - Clone an app from Git
- `bench --site <site> install-app` - Install app on a site
- `bench start` - Run development server

**frappe-stack.json Configuration:**
- Defines which apps to install in each workspace
- Specifies sites and their app configurations
- Read by `setup_stack.sh` during container initialization

## Important Constraints

**Technical Constraints:**
- Maximum 26 concurrent workspaces (NATO alphabet limit)
- Layer 2 image must be pre-built for fast startup (otherwise falls back to slow `bench init`)
- All workspaces share single MariaDB instance (database isolation via site names)
- Container memory defaults to 4GB (may need tuning for large sites)

**Port Allocation:**
- Ports 8001-8026 reserved for workspace web servers
- Infrastructure uses standard ports (MariaDB: 3306, Redis: 6379)

**Path Conventions:**
- Bench directory: `/workspace/bench` inside container
- Template location: `/opt/frappe-bench-template` (baked into Layer 2)
- Scripts symlinked from project root to workspace

## External Dependencies

**Container Registries:**
- Docker Hub: `mariadb:10.6`, `redis:alpine`, `nginx:alpine`
- Custom Registry: `devbench-base:brett`, `frappe-bench:brett` (Layer 1a, Layer 2)

**Git Repositories:**
- Frappe Framework: `https://github.com/frappe/frappe`
- ERPNext: `https://github.com/frappe/erpnext`
- Payments: `https://github.com/frappe/payments`
- Dartwing: Custom app (configured in frappe-stack.json)

**Network:**
- Docker network: `frappe-network` (bridge mode)
- Host SSH keys mounted for Git operations
- AI provider credentials mounted (optional, for AI-assisted development)

**Configuration Files:**
- `.env` - Per-workspace environment variables
- `frappe-stack.json` - App/site installation manifest
- `devcontainer.json` - VSCode container configuration
