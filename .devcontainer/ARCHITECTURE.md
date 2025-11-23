# Frappe DevContainer Architecture & Strategy

## Executive Summary

This development environment implements a **containerized Frappe development stack** with an innovative approach to app development that separates the main bench environment from individual app repositories. The architecture enables:

1. **Single Source of Truth**: App repositories live outside the bench, mounted as needed
2. **Immediate Synchronization**: Changes in external app repos instantly reflect in the running bench
3. **Branch Flexibility**: The frappeBench can run on any branch independently of the mounted apps
4. **Zero Duplication**: No need to duplicate entire repositories for development
5. **Production-Development Parity**: Same apps can be mounted to multiple benches with different branches

### Why This Approach?

Traditional Frappe development requires each bench to have its own copy of apps, leading to:
- Disk space waste with multiple copies of the same repos
- Synchronization challenges between development environments
- Complex git workflows when switching between branches
- Difficulty maintaining consistency across environments

This architecture solves these problems by **decoupling app storage from bench execution**, treating apps as external dependencies that can be dynamically mounted.

---

## Architecture Overview

```
Host Machine
├── frappeBench/                          # This repository (bench orchestration)
│   ├── .devcontainer/                    # Container configuration
│   │   ├── devcontainer.json            # VSCode devcontainer settings
│   │   ├── docker-compose.yml           # Service orchestration
│   │   ├── Dockerfile                   # Development container image
│   │   ├── setup-frappe.sh              # Bench initialization script
│   │   ├── setup-worktrees.sh           # Worktree management (future)
│   │   ├── generate_mounts.py           # Dynamic mount generation
│   │   └── mounts.json                  # App mount configuration
│   └── development/
│       └── frappe-bench/                 # Created at runtime
│           ├── apps/                     # Mounted from external repos
│           │   └── dartwing/            # Mounted via docker volume
│           ├── sites/
│           ├── env/
│           └── config/
│
└── External App Repositories
    └── dartwingers/dartwing/dartwing-frappe/  # Actual app repository
        └── development/frappe-bench/apps/dartwing/  # Worktree (future)
```

---

## Phase-by-Phase Setup Process

### Phase 0: Pre-Container Initialization (Host Machine)

**Trigger**: VSCode Command "Reopen in Container" or `docker compose up`
**Script**: `.devcontainer/generate_mounts.py`
**Configured**: `devcontainer.json` → `initializeCommand`

#### What Happens:
1. **Reads** `mounts.json` (JSON with `//` comment support)
2. **Validates** each mount entry:
   - `source`: Host path to app repository
   - `target`: Container path where app should appear (default: `/workspace/development/frappe-bench/apps/{app_name}`)
   - `app`: App name for default target derivation
3. **Generates** `docker-compose.mounts.yml` with volume mount directives
4. **Diagnostics**: Prints source path status, directory contents, and target info

#### Current Configuration:
```json
[
  {
    "app": "dartwing",
    "source": "/home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing"
    // No explicit target = default to /workspace/development/frappe-bench/apps/dartwing
  }
]
```

#### Generated Output (`docker-compose.mounts.yml`):
```yaml
services:
  frappe:
    volumes:
      - /home/brett/.../dartwing:/workspace/development/frappe-bench/apps/dartwing
```

**Why This Phase Exists**:
Docker Compose needs volume mount paths before containers start. This pre-flight script converts a user-friendly JSON config into Docker Compose volume syntax.

---

### Phase 1: Container Build & Startup

**Trigger**: Docker Compose starts services
**Configuration**: `docker-compose.yml`, `docker-compose.override.yml`, `docker-compose.mounts.yml`
**Image**: Built from `Dockerfile`

#### Services Started (in order):

1. **mariadb** (MariaDB 10.6)
   - Database server with UTF-8 support
   - Persistent volume: `mariadb-data-{PROJECT_NAME}`
   - Healthcheck: `mysqladmin ping`

2. **redis-cache** (Redis Alpine)
   - LRU cache with 256MB max memory
   - Persistent volume: `redis-cache-data-{PROJECT_NAME}`

3. **redis-queue** (Redis Alpine)
   - Background job queue storage
   - Persistent volume: `redis-queue-data-{PROJECT_NAME}`

4. **redis-socketio** (Redis Alpine)
   - Real-time communication state
   - Persistent volume: `redis-socketio-data-{PROJECT_NAME}`

5. **frappe** (Main Development Container)
   - Custom image: Ubuntu 22.04 + Frappe dependencies
   - User: Matches host UID/GID (no permission conflicts)
   - Shell: zsh with Oh My Zsh
   - Python: 3.10 with virtualenv
   - Node.js: 20.x with Yarn
   - Command: `sleep infinity` (keeps container alive)
   - Volumes:
     - `../:/workspace:cached` (entire project)
     - Mounts from `docker-compose.mounts.yml`
     - Claude/Codex config directories

6. **worker-default**, **worker-short**, **worker-long** (Background Workers)
   - Process Frappe background jobs
   - Same image as frappe container
   - Commands: `bench worker --queue {default|short|long}`

7. **scheduler** (Cron Scheduler)
   - Runs scheduled tasks
   - Command: `bench schedule`

8. **socketio** (Real-time Server)
   - Handles WebSocket connections
   - Command: `node apps/frappe/socketio.js`

9. **nginx** (Reverse Proxy - Optional)
   - Only starts with `--profile production`
   - Port: 8081 → 80 (internal)

#### Key Container Features:
- **UID/GID Matching**: Container user matches host user (no file permission issues)
- **Shell Environment**: zsh with Oh My Zsh for better developer experience
- **AI Tools**: Claude Code, Codex CLIs pre-installed
- **Python Tools**: black, isort, flake8, pytest, ipython
- **Network**: All services on `frappe-network` bridge

**Why This Phase Exists**:
Establishes the runtime environment with all Frappe dependencies and supporting services. The container mirrors your host user identity to avoid permission conflicts with mounted volumes.

---

### Phase 2: Bench Initialization

**Trigger**: `devcontainer.json` → `postCreateCommand`
**Script**: `.devcontainer/setup-frappe.sh`
**Runs**: Only when container is first created or rebuilt

#### Step 2.1: Environment Loading
- Loads `.devcontainer/.env` (excluding UID/GID to prevent conflicts)
- Sets defaults:
  - `BENCH_DIR=/workspace/development/frappe-bench`
  - `FRAPPE_BRANCH=version-15` ⚠️ **Production branch**
  - `PYTHON_BIN=python3.10`
  - `FRAPPE_SITE_NAME=site1.localhost`

#### Step 2.2: Worktree Preparation (Optional - Future)
```bash
.devcontainer/setup-worktrees.sh --prepare
```
- **Currently**: No-op (no `apps.worktrees.yml` exists)
- **Future**: Will create git worktrees for apps with dev/prod branches
- **Non-fatal**: Script continues even if this fails

#### Step 2.3: Bench Creation (`ensure_bench_ready`)

**If bench exists** (`/workspace/development/frappe-bench/env/bin/python` + `apps/frappe`):
- Keeps existing bench (idempotent)
- Preserves all existing files and configuration

**If bench doesn't exist**:
- Creates temporary bench with `bench init`
- **Smart App Preservation**: If `apps/` directory has content (mounted apps), scaffolds bench WITHOUT touching apps:
  ```bash
  bench init tmp-bench-XXXX --frappe-branch version-15
  tar --exclude=apps -cf - tmp-bench | tar -xf - -C frappe-bench
  ```
- Otherwise: Full `bench init frappe-bench`

**Bench Init Parameters**:
- `--frappe-branch version-15` ⚠️ **Uses Frappe's stable release branch**
- `--python python3.10`
- `--skip-redis-config-generation` (we provide custom config)

**Why Smart Preservation?**:
When apps are mounted from external repos, we don't want `bench init` to overwrite them with fresh clones. This approach creates the bench structure (env, config, sites) while preserving mounted apps.

#### Step 2.4: Apps.txt Configuration (`ensure_apps_txt`)
- Creates `/workspace/development/frappe-bench/sites/apps.txt`
- Ensures `frappe` entry exists
- Mounted apps will be added later

#### Step 2.5: Site Creation (`ensure_site`)
- Creates site if not exists: `bench new-site site1.localhost`
- Database: `mariadb` container, root password from env
- Admin password: From env (default: `admin`)
- Connection: `--no-mariadb-socket` (use TCP to mariadb container)

#### Step 2.6: Common Site Config (`ensure_common_site_config`)
- Generates/updates `sites/common_site_config.json`:
  ```json
  {
    "db_host": "mariadb",
    "redis_cache": "redis://redis-cache:6379",
    "redis_queue": "redis://redis-queue:6379",
    "redis_socketio": "redis://redis-socketio:6379"
  }
  ```
- Uses Docker service names for service discovery

#### Step 2.7: App Installation (Optional - Future)
```bash
.devcontainer/setup-worktrees.sh --install
```
- **Currently**: Reads `mounts.json`, ensures apps.txt entries
- **Future**: With `apps.worktrees.yml`, will:
  - Create worktrees for each app (dev + prod branches)
  - Add apps to apps.txt
  - Create dedicated sites per app
  - Install apps to their respective sites

**Current Behavior** (mounts.json mode):
```bash
# For each app in mounts.json:
ensure_apps_txt_entry "dartwing"          # Add to apps.txt
ensure_site_exists "dev.dartwing.localhost"  # Create site (if specified)
ensure_app_installed "dev.dartwing.localhost" "dartwing"  # Install app
```

#### Step 2.8: Default Site Selection
```bash
bench use site1.localhost
```
- Sets default site for bench commands

#### Step 2.9: Health Check (`validate_bench_start`)
- Runs `bench start` for 20 seconds (timeout)
- Checks for errors: `ECONNREFUSED`, `Traceback`, missing Procfile
- **If healthy**: Continues
- **If unhealthy**: Triggers full rebuild and re-validates

**Why Health Check?**:
Ensures bench is properly configured before marking setup as complete. Catches configuration issues early.

---

### Phase 3: Post-Attach (Development Ready)

**Trigger**: VSCode attaches to running container
**Script**: `devcontainer.json` → `postAttachCommand`

#### What Happens:
- Prints: `"Connected to Frappe development environment"`
- Developer can now:
  - Run `bench start` to start all services
  - Access site at `http://localhost:8000`
  - Edit code in mounted app directories
  - Changes reflect immediately (hot reload for JS, restart for Python)

---

## Branch Strategy: Main vs Master

### Finding: **Uses "main" as Production Branch**

**Evidence**:
1. **Frappe Framework**: Uses `version-15` branch (not main/master)
2. **Custom Apps** (e.g., dartwing):
   ```bash
   $ git remote -v
   origin  git@github.com:opensoft/dartwing-frappe.git

   $ git branch -a
   * devcontainer
     remotes/origin/main  ⚠️ Production branch
   ```

### Worktree Convention (Future Implementation)

When using `apps.worktrees.yml` with `setup-worktrees.sh`:

**For each app**:
- **`{app}-prod`** → Worktree on `main` branch (production-ready code)
- **`{app}-dev`** → Worktree on `develop` branch (active development)

**Example** (dartwing app):
```
Host: ~/projects/dartwingers/dartwing/dartwing-frappe/
├── .git/                                # Main repository
├── development/frappe-bench/apps/
│   ├── dartwing-prod/                   # Worktree: main branch
│   └── dartwing-dev/                    # Worktree: develop branch
```

**Mounted in Container**:
```
/workspace/development/frappe-bench/apps/
├── dartwing-prod/                       # Production code
└── dartwing-dev/                        # Development code
```

**Separate Sites**:
- `prod.dartwing.localhost` → Uses `dartwing-prod` app
- `dev.dartwing.localhost` → Uses `dartwing-dev` app

### Current Implementation vs Future Worktree Implementation

| Aspect | Current (Direct Mount) | Future (Worktree) |
|--------|------------------------|-------------------|
| **Mount Source** | Arbitrary path on host | Git worktree in app repo |
| **Branch Management** | Manual git operations | Automatic via setup script |
| **Multi-Branch** | One branch per mount | dev + prod per app |
| **Site Isolation** | Manual setup | Automatic site-per-worktree |
| **Repo Structure** | Any structure | Standardized worktree layout |

---

## Worktree Strategy (Future Implementation)

### What Are Git Worktrees?

Git worktrees allow **multiple working directories** for a single repository, each on different branches:

```bash
# Main repo
~/dartwing-frappe/                       # .git directory here
├── .git/
└── some-branch/                         # Current working directory

# Create worktrees
git worktree add development/frappe-bench/apps/dartwing-dev develop
git worktree add development/frappe-bench/apps/dartwing-prod main

# Result: Three working directories, one .git
~/dartwing-frappe/
├── .git/                                # Single source of truth
├── some-branch/                         # Original checkout
├── development/frappe-bench/apps/
│   ├── dartwing-dev/                    # develop branch
│   └── dartwing-prod/                   # main branch
```

### Benefits of Worktree Approach

1. **Single Repository**: One `.git` directory, all worktrees share git objects
2. **Instant Updates**: Changes to worktree files update immediately in mounted bench
3. **Branch Isolation**: dev and prod branches exist simultaneously
4. **Disk Efficiency**: Git objects stored once, working directories are lightweight
5. **No Sync Lag**: Container and host see the same files (bind mount)

### How Worktrees Work in This Setup

#### apps.worktrees.yml Configuration (Example):
```yaml
apps:
  - name: dartwing
    repo_root: /home/brett/projects/dartwingers/dartwing/dartwing-frappe
    worktree_root: /workspace/development/frappe-bench/apps  # Container path
    dev_branch: develop
    prod_branch: main

  - name: hrms
    repo_root: /home/brett/projects/frappe/hrms
    worktree_root: /workspace/development/frappe-bench/apps
    dev_branch: develop
    prod_branch: main
```

#### Setup Process:
```bash
# For each app in config:
ensure_worktree "dartwing-dev" \
                "/home/brett/.../dartwing-frappe" \
                "/home/brett/.../dartwing-frappe/development/frappe-bench/apps/dartwing-dev" \
                "develop"

ensure_worktree "dartwing-prod" \
                "/home/brett/.../dartwing-frappe" \
                "/home/brett/.../dartwing-frappe/development/frappe-bench/apps/dartwing-prod" \
                "main"
```

#### Then Mounted in Container:
```json
{
  "app": "dartwing-dev",
  "source": "/home/brett/.../dartwing-frappe/development/frappe-bench/apps/dartwing-dev",
  "target": "/workspace/development/frappe-bench/apps/dartwing-dev"
}
```

### Worktree Lifecycle Management

**Script**: `setup-worktrees.sh`

**Modes**:
- `--prepare`: Only create/update worktrees (before bench exists)
- `--install`: Create worktrees + add to apps.txt + install to sites (after bench exists)

**Worktree Operations**:
1. **Check if worktree exists**: `git worktree list --porcelain | grep "^worktree $path$"`
2. **Check branch not in use**: Prevent multiple worktrees on same branch
3. **Create worktree**: `git -C $repo worktree add $path $branch`
4. **Switch branch**: If worktree exists but wrong branch, `git -C $path checkout $branch`

**Site Management**:
- Each worktree gets dedicated site: `dev.{app}.localhost`, `prod.{app}.localhost`
- Apps installed to respective sites only
- Allows testing prod and dev versions simultaneously

---

## Data Flow & Synchronization

### File Change Propagation

```
Developer edits file in VSCode
          ↓
File on host filesystem changes
          ↓
Bind-mounted file in container changes (instantaneous)
          ↓
Frappe detects change:
  - JS/CSS: bench watch rebuilds → browser hot reload
  - Python: Requires bench restart
```

### Why This Architecture Enables Instant Updates

1. **Bind Mounts**: Docker bind mounts create a direct file system mapping
   - Host file inode = Container file inode
   - No copying, no sync delay
   - Changes are atomic

2. **No Git Operations Required**:
   - No git pull, no git reset
   - Files change directly via filesystem
   - Git operations only needed for commit/push

3. **Bench Independence**:
   - Bench runs on any branch (e.g., Frappe version-15)
   - Mounted apps can be on different branches
   - App code separate from bench code

### Example: Editing Dartwing App

```
Host: Edit /home/brett/.../dartwing/api/v1.py
           ↓ (bind mount)
Container: /workspace/development/frappe-bench/apps/dartwing/api/v1.py changes
           ↓ (Frappe watches file)
Bench: Detects change
           ↓ (If Python change)
Developer: Restarts bench (Ctrl+C, bench start)
           ↓
Browser: Refresh to see changes
```

---

## Configuration Files Reference

### devcontainer.json
- **Purpose**: VSCode Dev Container configuration
- **Key Settings**:
  - `initializeCommand`: Runs `generate_mounts.py` on host before compose
  - `dockerComposeFile`: Loads base, override, and mounts compose files
  - `postCreateCommand`: Runs `setup-frappe.sh` on first container create
  - `postAttachCommand`: Message when VSCode connects
  - `forwardPorts`: 8081 (web), 9000 (socketio), 1455 (auth callback)
  - `mounts`: Claude/Codex config directories

### docker-compose.yml
- **Purpose**: Base service definitions
- **Services**: frappe, mariadb, redis (x3), workers (x3), scheduler, socketio, nginx
- **Networks**: `frappe-network` (bridge)
- **Volumes**: Persistent data for mariadb, redis instances

### docker-compose.override.yml
- **Purpose**: Local overrides for development
- **Typical Use**: Port mappings, resource limits, development-only services

### docker-compose.mounts.yml (Generated)
- **Purpose**: Dynamic volume mounts from mounts.json
- **Auto-Generated**: By `generate_mounts.py` before container starts

### mounts.json
- **Purpose**: User-editable app mount configuration
- **Format**: JSON with `//` comment support
- **Schema**:
  ```json
  [
    {
      "app": "app_name",              // App name for apps.txt
      "source": "/host/path/to/app",  // Host filesystem path
      "target": "/container/path",    // Container path (optional)
      "branch": "branch_name",        // For documentation (not enforced)
      "site": "site.localhost"        // Site to install app (optional)
    }
  ]
  ```

### apps.worktrees.yml (Future)
- **Purpose**: Declarative worktree configuration
- **Format**: YAML
- **Schema**:
  ```yaml
  apps:
    - name: app_name
      repo_root: /host/path/to/repo
      worktree_root: /workspace/development/frappe-bench/apps  # default
      dev_branch: develop   # default
      prod_branch: main     # default ⚠️
  ```

### .env
- **Purpose**: Environment variables for all scripts and compose
- **Key Variables**:
  - `PROJECT_NAME`: Prefix for container names
  - `BENCH_DIR`: Bench location (default: `/workspace/development/frappe-bench`)
  - `FRAPPE_BRANCH`: Frappe framework branch (default: `version-15`)
  - `FRAPPE_SITE_NAME`: Default site (default: `site1.localhost`)
  - `ADMIN_PASSWORD`: Admin password (default: `admin`)
  - `DB_PASSWORD`: Database root password (default: `frappe`)
  - `UID`, `GID`: Host user IDs for container user matching

---

## Development Workflows

### Scenario 1: Developing Custom App (Current Setup)

**Setup**:
```json
// mounts.json
[
  {
    "app": "dartwing",
    "source": "/home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing"
  }
]
```

**Workflow**:
1. Edit files in VSCode (host or container)
2. Changes instantly visible in bench
3. For Python changes: Restart bench
4. For JS/CSS changes: `bench build` or `bench watch`
5. Test at `http://localhost:8000`
6. Commit/push from host or container

**Git Operations**:
```bash
# In container or host
cd /home/brett/.../dartwing-frappe/development/frappe-bench/apps/dartwing
git add .
git commit -m "Feature: Add new API endpoint"
git push
```

### Scenario 2: Testing Prod vs Dev (Future Worktree Setup)

**Setup**:
```yaml
# apps.worktrees.yml
apps:
  - name: dartwing
    repo_root: /home/brett/projects/dartwingers/dartwing/dartwing-frappe
    dev_branch: develop
    prod_branch: main
```

**Result**:
```
Apps:
  - dartwing-dev (develop branch)
  - dartwing-prod (main branch)

Sites:
  - dev.dartwing.localhost → dartwing-dev
  - prod.dartwing.localhost → dartwing-prod
```

**Workflow**:
1. Develop in `dartwing-dev` (develop branch)
2. Test at `http://dev.dartwing.localhost:8000`
3. Merge develop → main (git operations)
4. Switch to `dartwing-prod` worktree
5. Test at `http://prod.dartwing.localhost:8000`
6. Both versions running simultaneously in same bench

### Scenario 3: Switching Bench Branch

**Current Frappe Branch**: `version-15`

**To Switch to Different Frappe Version**:
```bash
# 1. Edit .env
FRAPPE_BRANCH=version-14

# 2. Rebuild bench
cd /workspace/development/frappe-bench
bench init frappe-bench --frappe-branch version-14

# 3. Apps remain on their own branches (unchanged)
```

**Independent Branch Control**:
- **Frappe Framework**: Controlled by `FRAPPE_BRANCH` env var
- **Mounted Apps**: Controlled by git operations in app repo
- No coupling between framework version and app version

---

## Common Tasks

### Add New App Mount

**Edit** `mounts.json`:
```json
[
  {
    "app": "hrms",
    "source": "/home/brett/projects/frappe-apps/hrms"
  }
]
```

**Rebuild Container**:
- VSCode: `Dev Containers: Rebuild Container`
- CLI: `docker compose -f .devcontainer/docker-compose.yml down && docker compose -f .devcontainer/docker-compose.yml up -d`

**Install App**:
```bash
cd /workspace/development/frappe-bench
bench --site site1.localhost install-app hrms
```

### Migrate to Worktree Setup (When Ready)

**Create** `apps.worktrees.yml`:
```yaml
apps:
  - name: dartwing
    repo_root: /home/brett/projects/dartwingers/dartwing/dartwing-frappe
    dev_branch: develop
    prod_branch: main
```

**Update** `mounts.json` to reference worktrees:
```json
[
  {
    "app": "dartwing-dev",
    "source": "/home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing-dev"
  },
  {
    "app": "dartwing-prod",
    "source": "/home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing-prod"
  }
]
```

**Run Worktree Setup**:
```bash
# In container
.devcontainer/setup-worktrees.sh --prepare  # Create worktrees
.devcontainer/setup-worktrees.sh --install  # Install to bench
```

**Rebuild Container**: To apply new mounts

### Debug Container Issues

**Check Service Status**:
```bash
docker ps --filter "name=frappe"
docker logs frappe-dev
docker logs frappe-mariadb
```

**Inspect Mounts**:
```bash
docker inspect frappe-dev | jq '.[].Mounts'
```

**Validate Bench**:
```bash
cd /workspace/development/frappe-bench
bench doctor
```

---

## Performance Considerations

### Bind Mount Performance

**Linux (Native)**:
- Bind mounts have near-zero overhead
- File changes propagate instantly
- Inode operations are native

**macOS (Docker Desktop)**:
- Uses osxfs or VirtioFS
- Some overhead for file sync
- Use `:cached` mount option for better write performance
- Current config: `- ../:/workspace:cached`

**Windows (WSL2)**:
- Best performance when files are in WSL2 filesystem
- Mounting Windows filesystem (e.g., C:\) is slower
- Recommendation: Keep repos in WSL2 (e.g., `/home/user/...`)

### Container Resource Limits

**Configured Limits** (docker-compose.yml):
```yaml
frappe:
  deploy:
    resources:
      limits:
        memory: 4g
        cpus: "2"

workers:
  deploy:
    resources:
      limits:
        memory: 2g
        cpus: "1"
```

**Tuning**:
- Edit `.devcontainer/.env`:
  ```bash
  CONTAINER_MEMORY=8g  # Increase for large databases
  CONTAINER_CPUS=4     # Increase for parallel builds
  ```

---

## Security Considerations

### UID/GID Matching

**Problem**: Default containers run as root, creating files with root ownership on host.

**Solution**: Container user matches host user:
```dockerfile
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid $USER_GID frappe && \
    useradd --uid $USER_UID --gid $USER_GID frappe
```

**Benefit**:
- Files created in container have correct host ownership
- No `sudo chown` required
- Safe to edit files from host or container

### Password Management

**Current** (defaults for development):
```bash
ADMIN_PASSWORD=admin
DB_PASSWORD=frappe
```

**Production**:
- Use strong passwords in `.env`
- Never commit `.env` to git (already in `.gitignore`)
- Use secrets management for sensitive deployments

### Container Network Isolation

**Current**:
- All services on `frappe-network` (bridge)
- Services reference each other by name (Docker DNS)
- Only exposed ports: 8081 (nginx), forwarded by devcontainer

**Production**:
- Use Docker secrets for passwords
- Implement network policies
- Use TLS for external connections

---

## Troubleshooting Guide

### "Bench not found" After Container Rebuild

**Cause**: Bench directory was cleared, setup script didn't run.

**Fix**:
```bash
.devcontainer/setup-frappe.sh
```

### "App not found" Error

**Cause**: App not in `apps.txt` or not installed to site.

**Fix**:
```bash
cd /workspace/development/frappe-bench
# Add to apps.txt
echo "dartwing" >> sites/apps.txt
# Install to site
bench --site site1.localhost install-app dartwing
```

### Mounted App Directory Empty in Container

**Cause**: Mount not applied, or `generate_mounts.py` failed.

**Debug**:
```bash
# On host, check generated file
cat .devcontainer/docker-compose.mounts.yml

# In container, check mount
ls -la /workspace/development/frappe-bench/apps/
mount | grep frappe-bench
```

**Fix**: Rebuild container to re-run `initializeCommand`.

### Worker Containers Failing

**Cause**: Bench not initialized, or apps missing.

**Check Logs**:
```bash
docker logs frappe-worker-default
docker logs frappe-worker-short
docker logs frappe-worker-long
```

**Common Fixes**:
- Ensure bench is initialized
- Check apps.txt includes all required apps
- Restart workers: `docker compose -f .devcontainer/docker-compose.yml restart worker-default`

### Database Connection Failed

**Cause**: MariaDB container not healthy, or credentials incorrect.

**Debug**:
```bash
docker exec frappe-mariadb mysql -uroot -pfrappe -e "SHOW DATABASES;"
```

**Check Health**:
```bash
docker ps --filter "name=mariadb"  # STATUS should show "healthy"
```

**Fix**:
```bash
docker restart frappe-mariadb
# Wait for healthcheck to pass (10s intervals)
```

---

## Future Enhancements

### 1. Full Worktree Integration

**Status**: Scripts ready, needs configuration.

**Steps**:
1. Create `apps.worktrees.yml` with app definitions
2. Run `setup-worktrees.sh --prepare` to create worktrees
3. Update `mounts.json` to reference worktree paths
4. Run `setup-worktrees.sh --install` to configure bench

**Benefits**:
- Automated dev/prod branch worktrees
- Dedicated sites per worktree
- Standardized repository structure

### 2. Multi-Bench Support

**Concept**: Multiple benches in one project, each on different Frappe versions.

**Structure**:
```
/workspace/development/
├── frappe-bench-v15/     # version-15
├── frappe-bench-v14/     # version-14
└── frappe-bench-develop/ # develop branch
```

**Use Case**: Testing apps across Frappe versions.

### 3. Production Deployment Automation

**Goal**: One-command production deployment.

**Features**:
- Docker Compose profiles for production
- Nginx SSL termination
- Automated backup scripts
- Health monitoring and alerting

### 4. IDE Integration Improvements

**Enhancements**:
- Python interpreter detection for apps in worktrees
- Debugger configuration for multi-app development
- Task definitions for common bench commands
- Problem matchers for bench error output

---

## Key Takeaways

### Current State ✅

1. **Full Stack Running**: MariaDB, Redis, Frappe, Workers, Scheduler, SocketIO
2. **Direct Mount**: Dartwing app mounted from external repo
3. **Branch**: Frappe on `version-15`, Dartwing on `main` (production)
4. **Instant Sync**: Changes to mounted app reflect immediately in bench
5. **User Matching**: No permission conflicts between host and container
6. **Development Ready**: Edit, test, commit workflow functional

### Worktree Implementation Status ⚠️

**Ready** (Scripts Exist):
- `setup-worktrees.sh` with full worktree lifecycle management
- Support for `apps.worktrees.yml` configuration
- Automatic dev/prod branch worktree creation

**Not Yet Configured**:
- No `apps.worktrees.yml` file exists
- Currently using simpler direct mount approach
- Can migrate when needed by creating config file

### Branch Convention 📋

**Production Branch**: `main` (modern Git convention)
**Development Branch**: `develop` (feature branch)
**Frappe Framework**: `version-15` (stable release branch)

**Worktree Naming** (when implemented):
- `{app}-dev` → develop branch
- `{app}-prod` → main branch

---

## Conclusion

This architecture achieves the goal of **zero-duplication, instant-sync development** by treating apps as external dependencies mounted into a containerized bench. The worktree foundation is prepared for when you need simultaneous dev/prod branch testing, but the current direct mount approach is simpler and fully functional for single-branch development.

The setup successfully:
- ✅ Runs complete Frappe stack in containers
- ✅ Mounts apps from project folders (immediate sync)
- ✅ Supports independent bench branch selection
- ✅ Uses `main` as production branch (modern convention)
- ✅ Provides infrastructure for worktree expansion

**Next Steps**:
1. Document this architecture (done! 📄)
2. Optionally migrate to worktree setup when multi-branch testing is needed
3. Consider multi-bench support for Frappe version compatibility testing
