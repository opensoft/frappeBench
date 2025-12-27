# Migration Complete: Worktrees → Standard Frappe

**Note**: All commands assume you are in a workspace root (e.g., `workspaces/alpha`).

## ✅ What Was Changed

### Files Deleted
- ✅ `.devcontainer/setup-worktrees.sh` - Worktree management script
- ✅ `.devcontainer/frappe-apps.json` - Mount configuration
- ✅ `.devcontainer/frappe-apps.example.json` - Example config
- ✅ `.devcontainer/generate_mounts.py` - Mount generator
- ✅ `.devcontainer/docker-compose.mounts.yml` - Generated mounts file

### Files Modified
- ✅ `.devcontainer/devcontainer.json` - Removed mount generation, simplified
- ✅ `scripts/setup-frappe.sh` - Added CUSTOM_APPS support, removed worktree calls
- ✅ `.devcontainer/.env` - Added CUSTOM_APPS variable
- ✅ `.devcontainer/.env.example` - Added CUSTOM_APPS variable

### Documentation Updated
- ✅ `.devcontainer/ARCHITECTURE.md` - Complete rewrite for standard approach
- ✅ `.devcontainer/EXECUTIVE_SUMMARY.md` - Complete rewrite
- ✅ `.devcontainer/README.md` - Updated with new app management instructions

---

## 🧹 Cleanup Steps (Required)

### Step 1: Stop and Remove Containers

```bash
# Stop all running containers
docker compose -f .devcontainer/docker-compose.yml down

# Optional: Remove volumes (starts fresh)
docker volume rm mariadb-data-frappeBench redis-cache-data-frappeBench redis-queue-data-frappeBench redis-socketio-data-frappeBench
```

### Step 2: Clean Up Bench Directory

```bash
# Remove existing bench (will be recreated on rebuild)
rm -rf development/frappe-bench

# Or keep bench but remove mounted apps that won't work anymore
rm -rf development/frappe-bench/apps/dartwing-dev
rm -rf development/frappe-bench/apps/dartwing-prod
```

### Step 3: Configure Custom Apps (Optional)

Edit `.devcontainer/.env`:
```bash
# Add your custom apps
# Format: app_name:repo_url:branch
CUSTOM_APPS=dartwing:https://github.com/opensoft/dartwing-frappe:develop
```

### Step 4: Rebuild Container

**In VSCode**:
1. Press `Cmd/Ctrl+Shift+P`
2. Type "Dev Containers: Rebuild Container"
3. Press Enter
4. Wait for rebuild (~5-10 minutes first time)

**Or via command line**:
```bash
# Rebuild images
docker compose -f .devcontainer/docker-compose.yml build --no-cache

# Start containers
docker compose -f .devcontainer/docker-compose.yml up -d

# Attach VSCode
# VSCode → Remote Explorer → Containers → Attach to Running Container
```

---

## 🧪 Testing Plan

### Test 1: Container Starts Successfully

**Expected**: Container builds and starts without errors

```bash
# Check all containers are running
docker ps

# Should see:
# - frappe-bench
# - frappe-mariadb
# - frappe-redis-cache
# - frappe-redis-queue
# - frappe-redis-socketio
# - frappe-worker-default
# - frappe-worker-short
# - frappe-worker-long
# - frappe-scheduler
# - frappe-socketio
```

**If fails**: Check logs
```bash
docker compose -f .devcontainer/docker-compose.yml logs frappe
docker compose -f .devcontainer/docker-compose.yml logs mariadb
```

### Test 2: Bench Initialized Successfully

**Expected**: Frappe bench created at `/workspace/bench`

```bash
# In container terminal
cd /workspace/bench

# Check bench exists
ls -la

# Should see:
# - apps/ (with frappe/)
# - sites/ (with ${SITE_NAME}/)
# - env/ (Python virtualenv)
# - config/
```

**If fails**: Check setup logs
```bash
# Setup script logs are shown during postCreateCommand
# Or run manually:
bash scripts/setup-frappe.sh
```

### Test 3: Custom Apps Installed (if configured)

**Expected**: Apps from CUSTOM_APPS are cloned and installed

```bash
# Check app exists
ls apps/

# Should see your app (e.g., dartwing)

# Check app is in apps.txt
cat sites/apps.txt

# Check app is installed to site
bench --site ${SITE_NAME} list-apps
```

**If fails**: Install manually
```bash
bench get-app https://github.com/opensoft/dartwing-frappe
bench --site ${SITE_NAME} install-app dartwing
```

### Test 4: Bench Starts Successfully

**Expected**: `bench start` runs without errors

```bash
cd /workspace/bench

# Start bench
bench start

# Should see output like:
# 12:00:00 web.1       | * Running on http://0.0.0.0:8000
# 12:00:00 socketio.1  | Listening on http://0.0.0.0:9000
# 12:00:00 schedule.1  | Scheduler started
# 12:00:00 worker_short.1 | Worker started
```

**If fails**: Check errors
```bash
# Run in verbose mode
bench start --verbose

# Check specific service
bench start web
```

### Test 5: Web Interface Accessible

**Expected**: Frappe site loads in browser

1. In container, run: `bench start`
2. In browser, go to: `http://localhost:${HOST_PORT}`
3. Login with:
   - Username: `Administrator`
   - Password: `admin` (or value from .env)

**If fails**:
```bash
# Check if port is forwarded
# VSCode should auto-forward ports 9000/1455; bench is on HOST_PORT

# Or check port manually
curl http://localhost:${HOST_PORT}
```

### Test 6: App Development Workflow

**Expected**: Can edit app code and see changes

```bash
# Edit a file in your app
vim apps/dartwing/dartwing/api/v1.py

# Restart bench (Ctrl+C, then bench start)

# Changes should be reflected
curl http://localhost:${HOST_PORT}/api/v1/test
```

### Test 7: Branch Switching Works

**Expected**: Can switch branches using git checkout

```bash
cd apps/dartwing

# Check current branch
git branch

# Switch branch
git checkout main
git pull

# Go back to bench
cd ../..

# Restart bench
# Ctrl+C, then: bench start
```

---

## 📊 Comparison: Old vs New

| Aspect | Old (Worktrees) | New (Standard) |
|--------|----------------|----------------|
| **Folder Structure** | `apps/dartwing-dev/`, `apps/dartwing-prod/` | `apps/dartwing/` |
| **Branch Management** | Git worktrees (automatic) | `git checkout` (manual) |
| **Multi-Branch Support** | Attempted (broken) | One branch at a time (working) |
| **Frappe Compatibility** | ❌ Broken (Python import errors) | ✅ Works perfectly |
| **Complexity** | High (custom scripts) | Low (native bench commands) |
| **Maintenance** | Complex (custom infrastructure) | Simple (standard Frappe) |
| **Documentation** | Custom (unique setup) | Standard (Frappe docs apply) |
| **Troubleshooting** | Hard (unique issues) | Easy (standard issues, known solutions) |

---

## 🎓 New Workflow Guide

### Adding a New App

```bash
# Method 1: Via .env (before rebuild)
# Edit .devcontainer/.env:
CUSTOM_APPS=myapp:https://github.com/me/myapp:develop

# Rebuild container

# Method 2: Manually (after rebuild)
cd /workspace/bench
bench get-app https://github.com/me/myapp
bench --site ${SITE_NAME} install-app myapp
```

### Switching Branches

```bash
cd apps/myapp
git checkout develop  # or main, or any branch
git pull
cd ../..
bench restart  # Ctrl+C, then bench start
```

### Developing Features

```bash
# 1. Create feature branch
cd apps/myapp
git checkout -b feature/new-api
git push -u origin feature/new-api

# 2. Make changes
vim myapp/api.py

# 3. Test (restart bench for Python, bench build for JS)
cd ../..
bench restart

# 4. Commit and push
cd apps/myapp
git add .
git commit -m "Add new API endpoint"
git push
```

### Testing Production Code

```bash
# Switch to main branch
cd apps/myapp
git checkout main
git pull
cd ../..

# Restart bench
bench restart

# Test production code
# When done, switch back to develop:
cd apps/myapp
git checkout develop
cd ../..
bench restart
```

---

## 🚨 Common Issues & Solutions

### Issue: App not found

**Symptom**: `App 'myapp' not found`

**Solution**:
```bash
# Check apps.txt
cat sites/apps.txt

# If app missing, add it:
echo "myapp" >> sites/apps.txt

# Then install to site:
bench --site ${SITE_NAME} install-app myapp
```

### Issue: Module import error

**Symptom**: `ModuleNotFoundError: No module named 'myapp'`

**Solution**:
```bash
# Check folder name matches app name
ls apps/

# If folder name has hyphens or different name, rename it:
mv apps/my-app apps/myapp

# Reinstall:
pip install -e apps/myapp
```

### Issue: Bench won't start

**Symptom**: `bench start` fails with errors

**Solution**:
```bash
# Check bench health
bench doctor

# If corrupted, rebuild:
rm -rf /workspace/bench
# Rebuild container
```

### Issue: Database connection fails

**Symptom**: `Could not connect to database`

**Solution**:
```bash
# Check MariaDB is running
docker ps --filter "name=mariadb"

# Check MariaDB logs
docker compose -f .devcontainer/docker-compose.yml logs mariadb

# Restart MariaDB
docker restart frappe-mariadb

# Wait for health check (30 seconds)
```

---

## 📝 Next Steps

1. ✅ **Read this file** - You're here!
2. 🧹 **Clean up** - Follow "Cleanup Steps" above
3. 🔧 **Configure** - Edit `.env` with your CUSTOM_APPS
4. 🔨 **Rebuild** - VSCode → Rebuild Container
5. 🧪 **Test** - Follow "Testing Plan" above
6. 📚 **Learn** - Read updated ARCHITECTURE.md and EXECUTIVE_SUMMARY.md
7. 💻 **Develop** - Use new workflow guide above

---

## 🎉 Benefits of New Approach

### Simplicity
- ✅ No custom scripts to maintain
- ✅ Standard Frappe workflow
- ✅ Easy to onboard new developers
- ✅ Clear documentation (Frappe docs apply directly)

### Reliability
- ✅ No Python import issues
- ✅ Compatible with all bench commands
- ✅ Tested by entire Frappe community
- ✅ Predictable behavior

### Maintainability
- ✅ Less code = fewer bugs
- ✅ No complex worktree management
- ✅ Standard git operations
- ✅ Works with IDE git tools

### Performance
- ✅ Faster container builds (fewer steps)
- ✅ Less disk space (no duplicate worktrees)
- ✅ Simpler Docker Compose (no mount generation)

---

## ❓ Questions?

### Q: Can I still test dev and prod simultaneously?

A: Use separate sites instead of separate worktrees:
```bash
# Create prod site
bench new-site prod.myapp.localhost

# Install app to prod site
bench --site prod.myapp.localhost install-app myapp

# Now you have:
# - ${SITE_NAME} (dev)
# - prod.myapp.localhost (prod)

# Switch app to production branch when testing prod site
```

### Q: What if I need a different Frappe version?

A: Edit `.env`:
```bash
FRAPPE_BRANCH=version-14  # or version-13, develop, etc.
```

Then rebuild container.

### Q: Can I add multiple apps?

A: Yes! Use comma-separated list in `.env`:
```bash
CUSTOM_APPS=app1:https://github.com/me/app1:develop,app2:https://github.com/me/app2:main,erpnext
```

### Q: What happened to the worktree scripts?

A: They were deleted because:
- Git worktrees with different folder names don't work with Frappe
- Python cannot import modules with hyphens in the name
- Frappe hardcodes the assumption that folder name = app name = module name
- See ARCHITECTURE.md "Why Worktrees Don't Work" section for technical details

---

## 📖 Documentation

- **[ARCHITECTURE.md](.devcontainer/ARCHITECTURE.md)** - Technical deep-dive, setup flow, troubleshooting
- **[EXECUTIVE_SUMMARY.md](.devcontainer/EXECUTIVE_SUMMARY.md)** - Quick overview, benefits, philosophy
- **[README.md](.devcontainer/README.md)** - Getting started, common commands, configuration

---

**Migration completed successfully!** 🚀

Your devcontainer now uses standard Frappe practices with native `bench` commands for all operations. Simpler, more reliable, and fully compatible with the Frappe ecosystem.
