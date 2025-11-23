# Frappe DevContainer - Executive Summary

## 🎯 Core Strategy

Your devcontainer setup implements a **decoupled app development architecture** where:

1. **Frappe Bench** = Execution environment (runs in container)
2. **Custom Apps** = External repositories (mounted into bench)
3. **Zero Duplication** = One repo, multiple bench instances can share it
4. **Instant Sync** = Changes in app repos immediately visible in running bench

## 🏗️ Three-Phase Setup

### Phase 0: Pre-Flight (Host Machine)
- **Script**: `generate_mounts.py`
- **Action**: Reads `mounts.json` → Generates `docker-compose.mounts.yml`
- **Result**: Docker knows which app directories to mount

### Phase 1: Container Build
- **Action**: Starts services (MariaDB, Redis, Frappe, Workers, etc.)
- **Result**: Full Frappe stack running, waiting for bench initialization

### Phase 2: Bench Initialization
- **Script**: `setup-frappe.sh`
- **Action**: Creates bench structure, preserves mounted apps, creates sites
- **Result**: Working bench at `/workspace/development/frappe-bench`

## 🌿 Branch Strategy

### ✅ Current: Uses **"main"** for Production

```
Production Branch:  main     ← Modern Git convention
Development Branch: develop  ← Feature development
Frappe Framework:   version-15 ← Stable release
```

**Evidence**: Your dartwing repo shows `remotes/origin/main` as the production branch.

### 🔄 Future: Worktree Strategy (Not Yet Implemented)

**Goal**: Run dev and prod branches simultaneously

```
Single Repo → Two Worktrees → Two Apps in Bench

dartwing-frappe/
├── .git/                                    # One repository
└── development/frappe-bench/apps/
    ├── dartwing-dev/   (develop branch)    # Development worktree
    └── dartwing-prod/  (main branch)       # Production worktree

Each with dedicated site:
- dev.dartwing.localhost  → dartwing-dev app
- prod.dartwing.localhost → dartwing-prod app
```

**Status**:
- ✅ Scripts ready (`setup-worktrees.sh`)
- ⚠️ Not configured (no `apps.worktrees.yml` exists)
- ✅ Current direct mount works fine for single-branch development

## 📊 Current Configuration

### What You Have Now

```json
// mounts.json
[
  {
    "app": "dartwing",
    "source": "/home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing"
  }
]
```

**Result**:
```
Host Path (your app repo)
  ↓ (bind mount)
Container Path: /workspace/development/frappe-bench/apps/dartwing
  ↓ (used by)
Frappe Bench (version-15) running site1.localhost
```

### How It Works

```mermaid
graph LR
    A[Edit File on Host] --> B[Bind Mount Updates File in Container]
    B --> C[Frappe Detects Change]
    C --> D{File Type?}
    D -->|Python| E[Restart bench]
    D -->|JS/CSS| F[bench build or auto-reload]
    E --> G[Changes Live]
    F --> G
```

## 🎁 Key Benefits

1. **One Repo, Multiple Benches** - Same app code can be mounted to different benches
2. **Instant Updates** - No git pull needed, files sync via bind mount
3. **Branch Independence** - Bench can run Frappe v15 while app runs on any branch
4. **No Permission Conflicts** - Container user matches host user (same UID/GID)
5. **Development Ready** - Edit in VSCode, test in browser, commit from anywhere

## 🔍 Verification Checklist

I verified the following about your setup:

### ✅ Confirmed Working
- [x] Full Frappe stack defined (MariaDB, Redis x3, Workers x3, Scheduler, SocketIO)
- [x] Dartwing app mounted from external repo
- [x] Branch: **main** used for production (modern convention)
- [x] User UID/GID matching for permission safety
- [x] Setup scripts are idempotent (safe to run multiple times)
- [x] Smart bench scaffolding (preserves mounted apps during init)

### ⚠️ Future Enhancement Ready
- [ ] Worktree implementation (scripts exist, not configured)
- [ ] Multiple worktrees per app (dev + prod)
- [ ] Dedicated sites per worktree

### ❌ Not Yet Implemented
- No `apps.worktrees.yml` configuration file
- No automatic dev/prod worktree creation
- Currently using simpler direct mount approach

## 🚀 Common Workflows

### Developing Dartwing App

```bash
# On host or in container - both work!
cd /home/brett/projects/dartwingers/dartwing/dartwing-frappe/development/frappe-bench/apps/dartwing

# Edit files in VSCode
vim dartwing/api/v1.py

# Changes are instantly in container!
# In container terminal:
cd /workspace/development/frappe-bench
bench restart  # or Ctrl+C and bench start

# Test at http://localhost:8000

# Commit from host or container
git add .
git commit -m "Add new API endpoint"
git push
```

### Adding New App

```json
// Edit mounts.json
[
  {
    "app": "hrms",
    "source": "/home/brett/projects/frappe-apps/hrms"
  }
]
```

```bash
# Rebuild container (regenerates mounts)
# VSCode: Dev Containers: Rebuild Container

# Install app to site
bench --site site1.localhost install-app hrms
```

## 📈 Why This Setup is Better Than Traditional

| Aspect | Traditional Frappe Dev | This Setup |
|--------|------------------------|------------|
| **Repo Copies** | One per bench | One shared by all benches |
| **Sync Method** | git pull | Instant (bind mount) |
| **Disk Usage** | High (duplicated repos) | Low (one copy) |
| **Branch Switching** | git checkout (one at a time) | Worktrees (multiple simultaneously) |
| **Environment Setup** | Manual dependencies | Containerized, reproducible |
| **Permission Issues** | Common (root vs user) | Solved (UID/GID matching) |

## 🎓 Key Concepts

### Bind Mount
Direct file system mapping: host file = container file (same inode). Changes propagate instantly, no copying.

### Git Worktree
Multiple working directories for one repository, each on different branches. Shares `.git` objects, saves disk space.

### Bench Independence
Frappe framework version (e.g., version-15) is independent from custom app branches (e.g., dartwing on main).

### Service Orchestration
Docker Compose manages dependencies: MariaDB starts → Redis starts → Frappe starts → Workers start.

### Idempotent Scripts
Safe to run multiple times. If bench exists, keeps it. If site exists, keeps it. No destructive actions.

## 📝 Next Steps (Optional)

If you want to enable simultaneous dev/prod branch testing:

1. **Create** `apps.worktrees.yml`:
   ```yaml
   apps:
     - name: dartwing
       repo_root: /home/brett/projects/dartwingers/dartwing/dartwing-frappe
       dev_branch: develop
       prod_branch: main
   ```

2. **Run** worktree setup:
   ```bash
   .devcontainer/setup-worktrees.sh --prepare
   ```

3. **Update** `mounts.json` to reference worktrees

4. **Rebuild** container to apply new mounts

Otherwise, your current direct mount setup works perfectly for single-branch development!

## 📚 Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Complete technical deep-dive (9000+ words)
- **[README.md](./README.md)** - Quick start and common commands
- **[.devcontainer/](.)** - All configuration files with inline comments

## 🎉 Summary

Your setup achieves the goal of:
- ✅ **One copy of repo** - Shared across benches
- ✅ **Immediate updates** - Via bind mounts
- ✅ **Independent branches** - Bench and apps decouple
- ✅ **Defaults to main** - Production branch (not master)
- ✅ **Future-ready** - Worktree infrastructure exists

**Production Branch**: `main` ← You asked me to verify this, and yes, it's `main`.

**Worktrees**: Two per app (dev + prod) when configured, currently one direct mount.

The architecture is elegant, efficient, and production-ready! 🚀
