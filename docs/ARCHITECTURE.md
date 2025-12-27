# Frappe DevContainer Architecture

## Executive Summary

This devcontainer provides a **complete Frappe development environment** using Docker and VSCode Dev Containers. It follows standard Frappe practices with no custom workarounds or complex infrastructure.

### Key Design Principles

1. **Standard Over Custom** - Use native Frappe tools (`bench`) for all operations
2. **Simplicity Over Flexibility** - One straightforward way to do things
3. **Reproducibility** - Identical environment across all developers
4. **Zero Host Dependencies** - Everything runs in containers
5. **Documentation as Code** - Self-documenting configuration files

---

## System Architecture

### Container Stack

```
┌─────────────────────────────────────────────────────────────┐
│ VSCode Dev Container (frappe-bench)                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ /workspace/bench/                    │ │
│ │ ├── apps/          # Frappe apps (cloned via bench)     │ │
│ │ ├── sites/         # Frappe sites                       │ │
│ │ ├── env/           # Python virtualenv                  │ │
│ │ └── config/        # Bench configuration                │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ Services:                                                    │
│ - frappe-mariadb (MariaDB 10.6)                             │
│ - frappe-redis-cache (Redis for caching)                    │
│ - frappe-redis-queue (Redis for background jobs)            │
│ - frappe-redis-socketio (Redis for real-time)               │
│ - frappe-worker-default (Background worker)                 │
│ - frappe-worker-short (Short-running tasks)                 │
│ - frappe-worker-long (Long-running tasks)                   │
│ - frappe-scheduler (Cron jobs)                              │
│ - frappe-socketio (WebSocket server)                        │
│ - frappe-nginx (Reverse proxy, optional)                    │
└─────────────────────────────────────────────────────────────┘
```

### Network Architecture

All services communicate via Docker network (`frappe-network`):
- Service names resolve via Docker DNS (e.g., `mariadb`, `redis-cache`)
- No port mapping needed for inter-service communication
- Bench is exposed via `${HOST_PORT}` → `8000` (set per workspace in `.devcontainer/.env`)
- Nginx (optional) uses `${NGINX_HOST_PORT}` → `80` when production profile is enabled
- VSCode forwards ports 8081 (default nginx), 9000, and 1455 automatically

---

## Setup Flow

### Phase 0: Pre-Container (Host Machine)

**Trigger**: VSCode initiates "Reopen in Container"

**File**: `.devcontainer/devcontainer.json`
```json
"initializeCommand": "bash .devcontainer/scripts/start-infra.sh && rm -rf /tmp/vscode-extensions-* || true"
```

**Actions**:
- Cleans up temporary VSCode extension caches
- Non-fatal (continues even if fails)

**Why**: Prevents stale extension data from previous containers

---

### Phase 1: Container Image (Layered)

**Trigger**: Docker Compose starts services and uses a prebuilt image

**Files**:
- `.devcontainer/docker-compose.yml` - Service orchestration (uses `frappe-bench:${USER}`)
- [Dockerfile.layer2](../Dockerfile.layer2) - Layer 2 image definition (only used when building)
- [build-layer2.sh](../build-layer2.sh) - Builds Layer 2 image

#### Layered Image Chain

`workbench-base:{user}` (Layer 0) → `devbench-base:{user}` (Layer 1a) → `frappe-bench:{user}` (Layer 2)

- Layer 0 + 1a are built once in `workBenches/` and reused across benches.
- Layer 2 is built in this repo with `./build-layer2.sh --user <name>`.
- The devcontainer does not install OS packages at runtime; it reuses the prebuilt image.

#### User Setup

The container user matches host UID/GID and is baked into Layer 2 so file ownership stays correct across host and container.

#### Service Containers

All services start in parallel:

1. **mariadb** - UTF-8 configured, health-checked
2. **redis-cache** - LRU eviction (256MB max)
3. **redis-queue** - No eviction (persistent queue)
4. **redis-socketio** - No eviction (session state)
5. **worker-default** - Processes default queue
6. **worker-short** - Handles short tasks
7. **worker-long** - Handles long tasks
8. **scheduler** - Runs cron jobs
9. **socketio** - WebSocket server
10. **nginx** - Reverse proxy (production profile only)

---

### Phase 2: Post-Create Setup

**Trigger**: Container created, services healthy

**File**: `.devcontainer/devcontainer.json`
```json
"postCreateCommand": "cp --update=none .devcontainer/.env.example .devcontainer/.env || true && bash scripts/setup-frappe.sh && bash scripts/setup_stack.sh"
```

#### Setup Script Flow

**File**: `scripts/setup-frappe.sh`

##### Step 1: Environment Loading ([setup-frappe.sh:8-23](setup-frappe.sh#L8-L23))

```bash
# Load .env (excluding UID/GID to avoid conflicts)
source <(grep -v '^#' .devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')

# Defaults
FRAPPE_SITE_NAME=${SITE_NAME}
FRAPPE_BRANCH=version-15
BENCH_DIR=/workspace/bench
```

##### Step 2: Bench Initialization ([setup-frappe.sh:88-101](setup-frappe.sh#L88-L101))

```bash
ensure_bench_ready() {
    if bench_is_initialized; then
        # Keep existing bench
        bench setup requirements
    else
        # Create new bench
        bench init frappe-bench \
            --frappe-branch version-15 \
            --python python3.10 \
            --skip-redis-config-generation
    fi
}
```

**Smart Logic**:
- Checks if `env/bin/python` and `apps/frappe` exist
- If yes: Keep existing bench (idempotent)
- If no: Run `bench init` to create new bench

##### Step 3: Custom Apps ([setup-frappe.sh:211-255](setup-frappe.sh#L211-L255))

```bash
get_custom_apps() {
    if [ -n "${CUSTOM_APPS:-}" ]; then
        IFS=',' read -ra APPS <<< "$CUSTOM_APPS"
        for app_spec in "${APPS[@]}"; do
            # Parse: app:repo:branch or app:repo or just app
            bench get-app [--branch branch] repo
            bench --site ${SITE_NAME} install-app app
        done
    fi
}
```

**Supported Formats**:
- `app_name` - Get from Frappe marketplace
- `app_name:repo_url` - Clone from GitHub
- `app_name:repo_url:branch` - Clone specific branch

**Example**:
```bash
CUSTOM_APPS=dartwing:https://github.com/opensoft/dartwing-frappe:develop,erpnext
```

##### Step 4: Site Creation ([setup-frappe.sh:116-134](setup-frappe.sh#L116-L134))

```bash
ensure_site() {
    if [ ! -d "$BENCH_DIR/sites/$FRAPPE_SITE_NAME" ]; then
        bench new-site ${SITE_NAME} \
            --db-name site1 \
            --db-password frappe \
            --mariadb-root-password frappe \
            --admin-password admin \
            --db-host mariadb \
            --no-mariadb-socket
    fi
}
```

**Database Connection**:
- Host: `mariadb` (Docker service name)
- Port: 3306 (TCP, no Unix socket)
- Root password: From `$DB_PASSWORD` env var
- Database: Created automatically

##### Step 5: Redis Configuration ([setup-frappe.sh:136-170](setup-frappe.sh#L136-L170))

Updates `sites/common_site_config.json`:
```json
{
  "db_host": "mariadb",
  "redis_cache": "redis://redis-cache:6379",
  "redis_queue": "redis://redis-queue:6379",
  "redis_socketio": "redis://redis-socketio:6379"
}
```

**Why Separate Redis Instances**:
- `redis-cache`: LRU eviction (non-critical data)
- `redis-queue`: No eviction (job queue must persist)
- `redis-socketio`: No eviction (session state must persist)

##### Step 6: Health Validation ([setup-frappe.sh:179-202](setup-frappe.sh#L179-L202))

```bash
validate_bench_start() {
    timeout 20s bench start
    # Check for errors: ECONNREFUSED, Traceback, etc.
    if healthy; then
        return 0
    else
        # Rebuild bench and retry
        rebuild_bench
        retry
    fi
}
```

**Smoke Test**:
- Starts bench for 20 seconds
- Checks for connection errors
- If fails: Rebuilds bench and retries once
- If still fails: Exits with error for manual inspection

---

### Phase 3: Post-Attach

**Trigger**: VSCode connects to running container

**File**: [devcontainer.json:123](devcontainer.json#L123)
```json
"postAttachCommand": "echo 'Connected to Frappe development environment'"
```

**Result**: Environment ready for development!

---

## App Management

### How Frappe Discovers Apps

#### 1. apps.txt Registry

**File**: `sites/apps.txt`
```
frappe
your-app
```

**Purpose**: Tells Frappe which apps are available in this bench

**Updated By**:
- `bench get-app` - Adds app automatically
- Manual: `echo "app-name" >> sites/apps.txt`

#### 2. Python Module Resolution

**Mechanism**: `.pth` files in virtualenv

**Location**: `env/lib/python3.10/site-packages/`

**Example** (`your-app.pth`):
```
/workspace/bench/apps/your-app
```

**How It Works**:
1. `bench get-app` clones repo to `apps/your-app/`
2. Runs `pip install -e apps/your-app/` (editable install)
3. Creates `.pth` file pointing to app directory
4. Python can now `import your-app` from anywhere

#### 3. Hardcoded Requirement

**CRITICAL**: `folder name MUST equal app name`

**File**: `frappe/__init__.py:1588`
```python
app_hooks = get_module(f"{app}.hooks")
# Becomes: import your-app.hooks
```

**Why**:
- Frappe uses `importlib.import_module(app_name)`
- Python module names must be valid identifiers
- Folder name = module name (no hyphens allowed!)

**This Breaks**:
```
apps/your-app-dev/    ❌ Cannot import "your-app-dev"
apps/your-app-prod/   ❌ Cannot import "your-app-prod"
apps/your_app/        ✅ Can import "your_app"
apps/your-app/        ❌ Hyphens invalid in Python modules
```

**Workaround Research**: See "Why Worktrees Don't Work" section below

---

## Development Workflows

### Adding New App

**Method 1: Environment Variable (Pre-Build)**

```bash
# Edit .devcontainer/.env
CUSTOM_APPS=dartwing:https://github.com/opensoft/dartwing-frappe:develop

# Rebuild container
VSCode → Dev Containers: Rebuild Container
```

**Method 2: Manual (Post-Build)**

```bash
cd /workspace/bench

# Clone app
bench get-app https://github.com/opensoft/dartwing-frappe

# Or clone specific branch
bench get-app --branch develop https://github.com/opensoft/dartwing-frappe

# Install to site
bench --site ${SITE_NAME} install-app dartwing
```

**Method 3: Direct Clone**

```bash
cd /workspace/bench/apps

# Clone directly
git clone https://github.com/opensoft/dartwing-frappe dartwing

# Install to bench
cd ..
pip install -e apps/dartwing

# Add to apps.txt
echo "dartwing" >> sites/apps.txt

# Install to site
bench --site ${SITE_NAME} install-app dartwing
```

### Switching Branches

```bash
cd /workspace/bench/apps/dartwing

# Switch branch
git checkout main      # or develop, or feature/xyz
git pull

# Return to bench
cd ../..

# Restart bench
# Ctrl+C to stop, then: bench start
```

**Important**:
- Python changes: Requires bench restart
- JS/CSS changes: Run `bench build` or use `bench watch`

### Making Changes

```bash
# Edit files in apps/your-app/
vim apps/dartwing/dartwing/api/v1.py

# Python changes: Restart bench
# JS/CSS changes: bench build

# Test changes
curl http://localhost:${HOST_PORT}/api/v1/test

# Commit
cd apps/dartwing
git add .
git commit -m "Add new API endpoint"
git push
```

---

## Why Worktrees Don't Work

### Problem Statement

**Goal**: Have `dartwing-dev` and `dartwing-prod` folders with different branches

**Reality**: Frappe requires `folder name == app name`

### Technical Analysis

#### Import Mechanism

**File**: `frappe/__init__.py:1452-1454`
```python
def get_module(modulename):
    return importlib.import_module(modulename)
```

**File**: `frappe/__init__.py:1588`
```python
app_hooks = get_module(f"{app}.hooks")
```

**When `apps.txt` contains `dartwing-dev`**:
```python
# Frappe tries to execute:
import dartwing-dev.hooks

# Python interprets as:
import dartwing - dev.hooks  # Syntax error!
```

**Python Module Name Rules**:
```python
# Valid:
import dartwing
import dartwing_dev
import dartwing2

# Invalid:
import dartwing-dev    # Hyphen not allowed
import dartwing.dev    # Must be module.submodule
```

#### Path Resolution

**File**: `frappe/__init__.py:1503-1513`
```python
def get_pymodule_path(modulename, *joins):
    module = get_module(scrub(modulename))
    return dirname(module.__file__)
```

**Dependency Chain**:
```
get_app_path("dartwing-dev")
  → get_pymodule_path("dartwing-dev")
    → get_module("dartwing-dev")
      → importlib.import_module("dartwing-dev")
        → SyntaxError!
```

### Attempted Solutions

#### Solution 1: Symbolic Links ⚠️

**Concept**:
```bash
apps/
├── dartwing-dev/      # Git worktree (develop)
├── dartwing-prod/     # Git worktree (main)
└── dartwing → dartwing-dev  # Symlink to active
```

**Problems**:
- Only one environment at a time
- Switching requires script: `ln -sf dartwing-prod dartwing`
- Fragile (symlink breaks = bench breaks)
- Git may not track symlinks

**Verdict**: Adds complexity for minimal benefit

#### Solution 2: Modify Frappe Core ❌

**Changes Needed**:
1. Add app name → folder path mapping config
2. Update all `get_module(app)` calls to use mapping
3. Update path resolution logic
4. Update pip install logic

**Problems**:
- Breaks on every Frappe update
- Won't be accepted upstream (fundamental architecture change)
- Massive maintenance burden

**Verdict**: Not viable

#### Solution 3: Separate Benches ⚠️

**Concept**:
```
development/
├── frappe-bench-dev/      # Develop branch apps
└── frappe-bench-prod/     # Main branch apps
```

**Problems**:
- 2x disk space (duplicate benches)
- 2x containers (duplicate services)
- More complex Docker Compose
- Resource intensive

**Verdict**: Overkill for most use cases

### Final Recommendation

**Use standard Frappe approach**:
- One folder per app: `apps/dartwing/`
- Switch branches with `git checkout`
- Test different versions using separate sites (lighter than separate benches)

**Why**:
- ✅ Works as documented
- ✅ No custom infrastructure
- ✅ Compatible with all tools
- ✅ Easy to troubleshoot
- ✅ Simplest mental model

---

## Configuration Reference

### Environment Variables

**File**: `.devcontainer/.env` (inside each workspace)

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `frappe` | Container name prefix |
| `SITE_NAME` | `${SITE_NAME}` | Default site |
| `FRAPPE_SITE_NAME` | (optional) | Override site name |
| `ADMIN_PASSWORD` | `admin` | Site admin password |
| `DB_PASSWORD` | `frappe` | MariaDB root password |
| `CUSTOM_APPS` | (empty) | Apps to auto-install |
| `CONTAINER_MEMORY` | `4g` | Memory limit per container |
| `CONTAINER_CPUS` | `2` | CPU limit per container |

### Docker Compose Services

**File**: `.devcontainer/docker-compose.yml`

#### frappe-bench
- **Image**: `frappe-bench:${USER}` (Layer 2)
- **User**: Matches host UID/GID
- **Command**: `sleep infinity` (kept alive)
- **Volumes**: `../:/workspace:cached`
- **Ports**: `${HOST_PORT}:8000` (bench serve)

#### mariadb
- **Image**: `mariadb:10.6`
- **Charset**: UTF-8 (utf8mb4_unicode_ci)
- **Volume**: `mariadb-data-{PROJECT_NAME}`
- **Health Check**: `mysqladmin ping`

#### redis-cache
- **Image**: `redis:alpine`
- **Policy**: LRU eviction (256MB max)
- **Volume**: `redis-cache-data-{PROJECT_NAME}`

#### redis-queue
- **Image**: `redis:alpine`
- **Policy**: No eviction
- **Volume**: `redis-queue-data-{PROJECT_NAME}`

#### redis-socketio
- **Image**: `redis:alpine`
- **Policy**: No eviction
- **Volume**: `redis-socketio-data-{PROJECT_NAME}`

#### workers (default, short, long)
- **Image**: Same as frappe-bench
- **Command**: `bench worker --queue {name}`
- **Resources**: 2GB memory, 1 CPU

#### scheduler
- **Image**: Same as frappe-bench
- **Command**: `bench schedule`
- **Resources**: 2GB memory, 1 CPU

#### socketio
- **Image**: Same as frappe-bench
- **Command**: `node apps/frappe/socketio.js`
- **Resources**: 1GB memory, 0.5 CPU

#### nginx
- **Image**: `nginx:alpine`
- **Profile**: `production` (only starts with --profile flag)
- **Port**: `${NGINX_HOST_PORT}:80`

---

## Troubleshooting

### Bench Initialization Fails

**Symptom**: `setup-frappe.sh` exits with error

**Debug**:
```bash
# Check MariaDB health
docker ps --filter "name=mariadb"
docker logs frappe-mariadb

# Check Redis
docker compose -f .devcontainer/docker-compose.yml exec frappe redis-cli -h redis-cache ping

# Manual bench init
cd /workspace
rm -rf bench
bench init /workspace/bench --frappe-branch version-15
```

### App Import Fails

**Symptom**: `ModuleNotFoundError: No module named 'your-app'`

**Debug**:
```bash
# Check app is in apps.txt
cat sites/apps.txt

# Check .pth file exists
ls env/lib/python3.10/site-packages/*.pth

# Check folder name matches app name
ls apps/

# Reinstall app
pip install -e apps/your-app
```

### Site Migration Fails

**Symptom**: `bench migrate` errors

**Debug**:
```bash
# Check database connection
bench --site ${SITE_NAME} mariadb
# If connects, database is ok

# Check app installed
bench --site ${SITE_NAME} list-apps

# Force migrate with patch
bench --site ${SITE_NAME} migrate --skip-failing
```

### Worker Not Processing Jobs

**Symptom**: Background jobs stuck in queue

**Debug**:
```bash
# Check worker logs
docker logs frappe-worker-default

# Check Redis queue
redis-cli -h redis-queue
> LLEN rq:queue:default

# Restart workers
docker restart frappe-worker-default frappe-worker-short frappe-worker-long
```

---

## Performance Tuning

### Container Resources

**Edit**: `.devcontainer/.env`
```bash
CONTAINER_MEMORY=8g  # Default: 4g
CONTAINER_CPUS=4     # Default: 2
```

**Apply**: Rebuild container

### MariaDB Performance

**Edit**: `.devcontainer/docker-compose.yml`
```yaml
mariadb:
  command: >
    --character-set-server=utf8mb4
    --collation-server=utf8mb4_unicode_ci
    --innodb-buffer-pool-size=2G       # Add this
    --innodb-log-file-size=512M        # Add this
```

### Redis Memory

**Edit**: `.devcontainer/docker-compose.yml`
```yaml
redis-cache:
  command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
```

---

## Security Considerations

### User Permissions

- Container user matches host user (same UID/GID)
- No root access required for file operations
- Files created have correct ownership

### Database Credentials

- Default password: `frappe` (change in production!)
- Only accessible within Docker network
- No external port exposure

### Port Exposure

- Port `${NGINX_HOST_PORT}`: Nginx (optional, production profile)
- Ports 8081, 9000, 1455: Forwarded by VSCode (localhost only)
- No ports directly exposed to network

---

## Conclusion

This architecture provides a **simple, standard Frappe development environment** with:
- ✅ Full service stack (database, cache, workers, scheduler)
- ✅ Native Frappe tooling (no custom scripts)
- ✅ Reproducible setup (containerized)
- ✅ Developer-friendly (matched UID/GID, zsh, VS Code integration)
- ✅ Production-ready patterns (separate Redis instances, workers, etc.)

**Philosophy**: Standard > Custom. Simple > Complex. Working > Perfect.
