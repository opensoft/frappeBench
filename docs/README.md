# Frappe DevContainer Setup

This is a complete Frappe development environment using Docker devcontainers.

## Architecture

### Running Containers
- **frappe-bench**: Main development container (service: `frappe`)
- **frappe-mariadb**: MariaDB 10.6 database
- **frappe-redis-cache**: Redis for caching
- **frappe-redis-queue**: Redis for background job queues
- **frappe-redis-socketio**: Redis for real-time communications

### Optional in Development
Worker containers are available via the `workers` compose profile if you want them separate. By default, `bench start` runs workers locally:
- worker-default, worker-short, worker-long
- scheduler
- socketio
- nginx (optional, access via `http://localhost:${NGINX_HOST_PORT}` when enabled)

## Quick Start

### 1. Create a Workspace
From the repo root:
```bash
./scripts/new-frappe-workspace.sh alpha
```
This creates `workspaces/alpha/` with a workspace-specific `.devcontainer`.

### 2. Open in VSCode
Open `workspaces/alpha/` in VSCode and click "Reopen in Container" when prompted.

### 3. Verify Setup
The devcontainer will automatically:
- Use the prebuilt layered image (`frappe-bench:${USER}`); build it with `./build-layer2.sh --user <name>` if needed
- Initialize Frappe bench (first time only, 5-10 minutes)
- Create site at `${SITE_NAME}` (from `.devcontainer/.env`)
- Configure Redis connections

### 4. Start Frappe
Inside the devcontainer terminal:
```bash
cd /workspace/bench
bench start
```

This starts all services:
- Web server on port 8000 (container)
- SocketIO server
- Background workers (default, short, long queues)
- Scheduler for cron jobs

### 5. Access Frappe
Open browser to: `http://localhost:${HOST_PORT}` from `workspaces/alpha/.devcontainer/.env`
Defaults: alpha → 8001, bravo → 8002

**Login credentials:**
- Username: `Administrator`
- Password: `admin`

## Configuration

### Environment Variables
Located in `workspaces/<name>/.devcontainer/.env`:
- `SITE_NAME` (or `FRAPPE_SITE_NAME`): Default site name (default: ${SITE_NAME})
- `ADMIN_PASSWORD`: Administrator password (default: admin)
- `DB_HOST`: MariaDB hostname (default: mariadb)
- `DB_PASSWORD`: Database root password (default: frappe)
- `CUSTOM_APPS`: Comma-separated list of apps to auto-install (see below)

### Ports
- `${HOST_PORT}` → `8000`: Frappe web server (bench start)
- `9000`: SocketIO server (container)
- `6787`: File watcher (container)
- `${NGINX_HOST_PORT}` → `80`: Nginx (if enabled with --profile production)

## Common Commands

### Bench Commands
```bash
# Start all services
bench start

# Create new site
bench new-site mysite.localhost

# Install app
bench get-app erpnext
bench --site ${SITE_NAME} install-app erpnext

# Update bench
bench update

# Migrate site
bench --site ${SITE_NAME} migrate

# Console
bench --site ${SITE_NAME} console

# Run tests
bench --site ${SITE_NAME} run-tests
```

### Database Access
```bash
# MySQL client
mysql -h mariadb -u root -pfrappe

# Frappe database console
bench --site ${SITE_NAME} mariadb
```

### Redis Access
```bash
# Redis cache
redis-cli -h redis-cache

# Redis queue
redis-cli -h redis-queue

# Redis socketio
redis-cli -h redis-socketio
```

## Development Workflow

### File Structure
```
/workspace/
  bench/                   # Bench directory
    apps/                  # Frappe apps
      frappe/              # Core Frappe framework
    sites/                 # Sites
      ${SITE_NAME}/     # Default site
      common_site_config.json
    env/                   # Python virtual environment
    config/                # Configuration files
    logs/                  # Log files
```

### Adding Custom Apps

**Option 1: Using Environment Variable (Recommended for initial setup)**

Edit `.devcontainer/.env` before building container:
```bash
# Format: app_name:repo_url:branch or app_name:repo_url or just app_name
CUSTOM_APPS=dartwing:https://github.com/opensoft/dartwing-frappe:develop,erpnext
```

Then rebuild container:
- **VSCode**: Cmd/Ctrl+Shift+P → "Dev Containers: Rebuild Container"

**Option 2: Manual Installation (for adding apps to existing container)**

```bash
cd /workspace/bench

# Get app from GitHub
bench get-app https://github.com/frappe/erpnext

# Or get specific branch
bench get-app --branch develop https://github.com/frappe/erpnext

# Or get from Frappe marketplace
bench get-app erpnext

# Install app to site
bench --site ${SITE_NAME} install-app erpnext

# Restart bench (Ctrl+C then bench start)
```

**Option 3: Get App from Local Development Repo**

```bash
cd /workspace/bench

# Clone your repo to apps directory
cd apps
git clone https://github.com/your-org/your-app
cd ..

# Install app to site
bench --site ${SITE_NAME} install-app your-app
```

### Code Changes
- Edit files directly in `/workspace/bench/apps/`
- Changes are live-reloaded automatically
- For Python changes, restart `bench start`
- For JS/CSS changes, run `bench build` or `bench watch`

### Branch Switching
```bash
cd /workspace/bench/apps/your-app

# Switch to different branch
git checkout develop  # or main, or feature/xyz
git pull

# Go back to bench directory
cd ../..

# Restart bench to apply changes
# Press Ctrl+C, then run: bench start
```

## Troubleshooting

### Container Won't Start
```bash
# Rebuild container
# In VSCode: Cmd/Ctrl+Shift+P -> "Dev Containers: Rebuild Container"

# Or from command line
cd workspaces/<name>
docker compose -f .devcontainer/docker-compose.yml down
docker compose -f .devcontainer/docker-compose.yml up -d frappe
```

### Bench Init Failed
Check logs in `.devcontainer/` or rebuild container to retry initialization.

### Can't Connect to Database
```bash
# Check MariaDB container
docker ps --filter "name=mariadb"

# Check MariaDB logs
docker logs frappe-mariadb

# Test connection (from workspace root)
docker compose -f .devcontainer/docker-compose.yml exec frappe \
  mysql -h mariadb -u root -pfrappe -e "SHOW DATABASES;"
```

### Redis Connection Issues
```bash
# Check Redis containers
docker ps --filter "name=redis"

# Test connections (from workspace root)
docker compose -f .devcontainer/docker-compose.yml exec frappe redis-cli -h redis-cache ping
docker compose -f .devcontainer/docker-compose.yml exec frappe redis-cli -h redis-queue ping
docker compose -f .devcontainer/docker-compose.yml exec frappe redis-cli -h redis-socketio ping
```

### Reset Everything
```bash
# Stop and remove containers
cd workspaces/<name>
docker compose -f .devcontainer/docker-compose.yml down

# Remove volumes (WARNING: deletes all data)
docker volume rm mariadb-data-frappe redis-cache-data-frappe redis-queue-data-frappe redis-socketio-data-frappe

# Remove bench directory
rm -rf /workspace/bench

# Rebuild container
# In VSCode: Rebuild Container
```

## Production Deployment

To enable nginx and worker containers for production:
```bash
# Start workers or nginx via compose profiles
cd workspaces/<name>
docker compose -f .devcontainer/docker-compose.yml --profile workers up -d
docker compose -f .devcontainer/docker-compose.yml --profile production up -d
```

## Version Information

- **Frappe**: Version 15 (version-15 branch)
- **Python**: 3.x (from devbench-base)
- **Node.js**: 20.x (from devbench-base)
- **MariaDB**: 10.6
- **Redis**: Alpine (latest)
- **Bench**: `frappe-bench` (from Layer 2 image)

## Support Files

- `Dockerfile.layer2`: Layer 2 image definition
- `build-layer2.sh`: Layer 2 image build script
- `devcontainer.example/docker-compose.yml`: Template (copied into workspaces)
- `devcontainer.example/devcontainer.json`: Template (copied into workspaces)
- `scripts/setup-frappe.sh`: Automated bench initialization script
- `devcontainer.example/.env.example`: Environment variable template
- `devcontainer.example/nginx.conf`: Nginx reverse proxy configuration (optional)
