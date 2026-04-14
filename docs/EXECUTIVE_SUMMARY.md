# Frappe DevContainer - Executive Summary

## 🎯 Core Strategy

This devcontainer provides a **complete, containerized Frappe development environment** using Docker and VSCode. It follows standard Frappe best practices for app management and development workflows.

### Key Benefits
1. **Reproducible Environment** - Identical setup across all developers
2. **Zero Local Dependencies** - Everything runs in Docker containers
3. **Full Frappe Stack** - MariaDB, Redis, Workers, Scheduler all included
4. **Standard Workflow** - Uses native `bench` commands for all operations
5. **Instant Dev Setup** - From clone to running in under 10 minutes

---

## 🏗️ Architecture

### Container Stack
```
frappe-bench        Main development container (service: frappe)
frappe-mariadb      Database server (MariaDB 10.6)
frappe-redis-*      Cache, Queue, SocketIO (3x Redis instances)
frappe-worker-*     Background job processors (3x workers)
frappe-scheduler    Cron job scheduler
frappe-socketio     Real-time WebSocket server
frappe-nginx        Reverse proxy (optional, for production profile)
```

### File Structure
```
/workspace/
└── development/
    └── frappe-bench/              # Frappe bench directory
        ├── apps/                  # All Frappe apps
        │   ├── frappe/            # Core framework (auto-installed)
        │   └── your-app/          # Custom apps (via bench get-app)
        ├── sites/                 # Frappe sites
        │   ├── ${SITE_NAME}/   # Default site
        │   └── apps.txt           # Installed apps list
        ├── env/                   # Python virtual environment
        ├── config/                # Bench configuration
        └── logs/                  # Application logs
```

---

## 📦 App Management Philosophy

### Standard Frappe Approach (What This Setup Uses)

Apps are cloned directly into the bench using native Frappe tools:

```bash
# Clone app into bench
bench get-app https://github.com/your-org/your-app

# Or clone specific branch
bench get-app --branch develop https://github.com/your-org/your-app

# Install to site
bench --site ${SITE_NAME} install-app your-app
```

**Why this is simple:**
- ✅ Works exactly as documented in Frappe docs
- ✅ No custom scripting or workarounds needed
- ✅ Compatible with all bench commands
- ✅ Easy to troubleshoot (standard setup)
- ✅ Clear separation: one app = one folder

**Trade-offs:**
- ⚠️ One branch active per app at a time
- ⚠️ Use `git checkout` to switch branches
- ⚠️ Cannot run dev and prod simultaneously (use separate sites instead)

---

## 🚀 Quick Start

### 1. Clone and Create a Workspace

```bash
# Clone this repo
git clone <this-repo-url>
cd frappeBench

# Create a workspace (alpha, bravo, ...)
./scripts/new-frappe-workspace.sh alpha
```

### 2. Open in VSCode

```
File → Open Folder → workspaces/alpha/
Click "Reopen in Container" when prompted
```

### 3. Wait for Setup

First time: ~10 minutes
- Builds Docker image
- Initializes Frappe bench
- Creates default site
- Installs custom apps (if configured)

### 4. Start Developing

```bash
cd /workspace/bench
bench start
```

Access at: http://localhost:${HOST_PORT} (admin/admin)

---

## 🔧 Common Workflows

### Adding Apps

**Method 1: Environment Variable (before container build)**

Edit `workspaces/<name>/.devcontainer/.env`:
```bash
CUSTOM_APPS=dartwing:https://github.com/opensoft/dartwing-frappe:develop,erpnext
```

Rebuild container: VSCode → Rebuild Container

**Method 2: Manual (after container is running)**

```bash
cd /workspace/bench
bench get-app https://github.com/opensoft/dartwing-frappe
bench --site ${SITE_NAME} install-app dartwing
```

### Switching Branches

```bash
cd apps/your-app
git checkout develop  # or any branch
git pull
cd ../..
bench restart
```

### Creating Features

```bash
# Make changes in apps/your-app/
# Python changes: Restart bench (Ctrl+C, then bench start)
# JS/CSS changes: bench build (or bench watch for auto-rebuild)

# Commit
cd apps/your-app
git add .
git commit -m "Add feature X"
git push
```

### Running Tests

```bash
bench --site ${SITE_NAME} run-tests --app your-app
```

---

## 📊 How Setup Works

### Phase 1: initializeCommand (Host)
- Cleans up temporary extension files

### Phase 2: Container Start (Layered Images)
- Uses prebuilt layered image `frappe-bench:${USER}` (Layer 3)
- Layer chain: `workbench-base:latest` → `dev-bench-base:latest` → `frappe-bench:latest` → `frappe-bench:${USER}`
- No monolithic package installs during devcontainer startup
- Build Layer 2 and Layer 3 when needed: `./build-layer.sh --user <name>`
- Starts service containers (MariaDB, Redis, etc.)

### Phase 3: postCreateCommand (Container)
- Runs `setup-frappe.sh`:
  1. Initializes Frappe bench (if not exists)
  2. Gets custom apps (from CUSTOM_APPS env var)
  3. Creates default site
  4. Configures Redis connections
  5. Validates bench health

### Phase 4: postAttachCommand
- Prints success message
- Environment ready for development

---

## 🎛️ Configuration

### Environment Variables (workspaces/<name>/.devcontainer/.env)

```bash
# Project settings
PROJECT_NAME=frappeBench
SITE_NAME=alpha.localhost
ADMIN_PASSWORD=admin

# Custom apps (comma-separated)
# Format: app:repo:branch or app:repo or just app
CUSTOM_APPS=

# Resources
CONTAINER_MEMORY=4g
CONTAINER_CPUS=2

# Database
DB_PASSWORD=frappe
```

### Container Resources

Adjust in `workspaces/<name>/.devcontainer/.env`:
```bash
CONTAINER_MEMORY=8g  # Increase for large databases
CONTAINER_CPUS=4     # Increase for parallel builds
```

---

## 🐛 Troubleshooting

### Container Won't Start
```bash
cd workspaces/<name>
docker compose -f .devcontainer/docker-compose.yml down
docker compose -f .devcontainer/docker-compose.yml up -d
# Or in VSCode: Rebuild Container
```

### App Not Found
```bash
# Check apps.txt
cat sites/apps.txt

# Add app if missing
echo "your-app" >> sites/apps.txt

# Install to site
bench --site ${SITE_NAME} install-app your-app
```

### Database Connection Failed
```bash
# Check MariaDB is healthy
docker ps --filter "name=mariadb"

# Test connection
docker compose -f .devcontainer/docker-compose.yml exec frappe \
  mysql -h mariadb -u root -pfrappe -e "SHOW DATABASES;"

# Restart MariaDB
docker restart frappe-mariadb
```

### Bench Validation Failed
```bash
# Check bench health
cd /workspace/bench
bench doctor

# Rebuild bench if corrupted
rm -rf /workspace/bench
# Rebuild container to reinitialize
```

---

## 🌟 Why This Approach

### Rejected Alternatives

#### ❌ Git Worktrees with Different Folder Names
**Problem**: Frappe requires `folder name == app name == Python module name`
- Cannot use `dartwing-dev` and `dartwing-prod` folders
- Python module imports would fail (hyphens not allowed)
- No configuration to override this hardcoded assumption

**Research**: See ARCHITECTURE.md for detailed technical analysis

#### ❌ Symbolic Links
**Problem**: Added complexity for minimal benefit
- Still only one active environment at a time
- Fragile (symlink breaks, bench breaks)
- Requires switching script and manual management

#### ❌ Separate Benches
**Problem**: Resource intensive
- 2x disk space (duplicate bench directories)
- 2x memory (duplicate service containers)
- More complex Docker Compose setup

### ✅ Standard Frappe Clone (Current Approach)

**Benefits**:
- Works exactly as documented
- No custom infrastructure to maintain
- Easy onboarding for new developers
- Compatible with all Frappe tools
- Simplest mental model

**Acceptable Trade-offs**:
- Only one branch per app at a time
- Use git checkout to switch branches
- Testing multiple versions requires separate sites (still faster than separate benches)

---

## 📚 Documentation

- **[README.md](./README.md)** - Quick start and common commands
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Technical deep-dive
- **[Dockerfile.layer2](../Dockerfile.layer2)** - Layer 2 image definition
- **[build-layer2.sh](../build-layer2.sh)** - Layer 2 image build script
- **[devcontainer.example/docker-compose.yml](../devcontainer.example/docker-compose.yml)** - Service orchestration template
- **[devcontainer.example/devcontainer.json](../devcontainer.example/devcontainer.json)** - Devcontainer template
- **[scripts/setup-frappe.sh](../scripts/setup-frappe.sh)** - Bench initialization script

---

## 🎉 Summary

This devcontainer provides a **production-ready Frappe development environment** using industry-standard Docker practices and native Frappe tooling. No workarounds, no hacks, just a clean, reproducible setup that works.

**Getting Started**: Clone → Open in VSCode → Wait 10 minutes → Start coding

**App Management**: `bench get-app` to add, `git checkout` to switch branches

**Philosophy**: Simple > Complex. Standard > Custom. Working > Perfect.
