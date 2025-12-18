# Frappe DevContainer Setup

This is a complete Frappe development environment using Docker devcontainers.

## Architecture

### Running Containers
- **frappe-dev**: Main development container with Frappe bench
- **frappe-mariadb**: MariaDB 10.6 database
- **frappe-redis-cache**: Redis for caching
- **frappe-redis-queue**: Redis for background job queues
- **frappe-redis-socketio**: Redis for real-time communications

### Disabled in Development
Worker containers are commented out because `bench start` handles all workers locally:
- worker-default, worker-short, worker-long
- scheduler
- socketio
- nginx (optional, access directly via bench on port 8000)

## Quick Start

### 1. Open in VSCode
Open the project folder in VSCode and click "Reopen in Container" when prompted.

### 2. Verify Setup
The devcontainer will automatically:
- Build the container with all dependencies
- Initialize Frappe bench (first time only, 5-10 minutes)
- Create site at `site1.localhost`
- Configure Redis connections

### 3. Start Frappe
Inside the devcontainer terminal:
```bash
cd /workspace/development/frappe-bench
bench start
```

This starts all services:
- Web server on port 8000
- SocketIO server
- Background workers (default, short, long queues)
- Scheduler for cron jobs

### 4. Access Frappe
Open browser to: http://localhost:8000

**Login credentials:**
- Username: `Administrator`
- Password: `admin`

## Configuration

### Environment Variables
Located in `.devcontainer/.env`:
- `FRAPPE_SITE_NAME`: Default site name (default: site1.localhost)
- `ADMIN_PASSWORD`: Administrator password (default: admin)
- `DB_HOST`: MariaDB hostname (default: mariadb)
- `DB_PASSWORD`: Database root password (default: frappe)
- `CUSTOM_APPS`: Comma-separated list of apps to auto-install (see below)

### Ports
- `8000`: Frappe web server (bench start)
- `9000`: SocketIO server
- `6787`: File watcher
- `8081`: Nginx (if enabled with --profile production)

## Common Commands

### Bench Commands
```bash
# Start all services
bench start

# Create new site
bench new-site mysite.localhost

# Install app
bench get-app erpnext
bench --site site1.localhost install-app erpnext

# Update bench
bench update

# Migrate site
bench --site site1.localhost migrate

# Console
bench --site site1.localhost console

# Run tests
bench --site site1.localhost run-tests
```

### Database Access
```bash
# MySQL client
mysql -h mariadb -u root -pfrappe

# Frappe database console
bench --site site1.localhost mariadb
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
  development/
    frappe-bench/          # Bench directory
      apps/                # Frappe apps
        frappe/            # Core Frappe framework
      sites/               # Sites
        site1.localhost/   # Default site
        common_site_config.json
      env/                 # Python virtual environment
      config/              # Configuration files
      logs/                # Log files
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
cd /workspace/development/frappe-bench

# Get app from GitHub
bench get-app https://github.com/frappe/erpnext

# Or get specific branch
bench get-app --branch develop https://github.com/frappe/erpnext

# Or get from Frappe marketplace
bench get-app erpnext

# Install app to site
bench --site site1.localhost install-app erpnext

# Restart bench (Ctrl+C then bench start)
```

**Option 3: Get App from Local Development Repo**

```bash
cd /workspace/development/frappe-bench

# Clone your repo to apps directory
cd apps
git clone https://github.com/your-org/your-app
cd ..

# Install app to site
bench --site site1.localhost install-app your-app
```

### Code Changes
- Edit files directly in `/workspace/development/frappe-bench/apps/`
- Changes are live-reloaded automatically
- For Python changes, restart `bench start`
- For JS/CSS changes, run `bench build` or `bench watch`

### Branch Switching
```bash
cd /workspace/development/frappe-bench/apps/your-app

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

# Test connection
docker exec frappe-dev mysql -h mariadb -u root -pfrappe -e "SHOW DATABASES;"
```

### Redis Connection Issues
```bash
# Check Redis containers
docker ps --filter "name=redis"

# Test connections
docker exec frappe-dev redis-cli -h redis-cache ping
docker exec frappe-dev redis-cli -h redis-queue ping
docker exec frappe-dev redis-cli -h redis-socketio ping
```

### Reset Everything
```bash
# Stop and remove containers
docker compose -f .devcontainer/docker-compose.yml down

# Remove volumes (WARNING: deletes all data)
docker volume rm mariadb-data-frappe redis-cache-data-frappe redis-queue-data-frappe redis-socketio-data-frappe

# Remove bench directory
rm -rf /workspace/development/frappe-bench

# Rebuild container
# In VSCode: Rebuild Container
```

## Production Deployment

To enable nginx and worker containers for production:
```bash
# Uncomment worker services in docker-compose.yml
# Start with production profile
docker compose -f .devcontainer/docker-compose.yml --profile production up -d
```

## Version Information

- **Frappe**: Version 15 (version-15 branch)
- **Python**: 3.10
- **Node.js**: 20.x
- **MariaDB**: 10.6
- **Redis**: Alpine (latest)
- **Bench**: 5.27.0

## Support Files

- `Dockerfile`: Container image definition
- `docker-compose.yml`: Multi-container setup
- `devcontainer.json`: VSCode devcontainer configuration
- `setup-frappe.sh`: Automated bench initialization script
- `.env.example`: Environment variable template
- `nginx.conf`: Nginx reverse proxy configuration (optional)
