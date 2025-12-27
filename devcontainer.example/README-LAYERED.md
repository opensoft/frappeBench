# Frappe DevContainer Template (Layered Architecture)

This workspace template uses the **layered workBench architecture** with pre-built Docker images.

## Layered Architecture

- **Layer 0** (`workbench-base:brett`): System + modern CLI tools (zsh, tmux, fzf, bat, zoxide, tldr, neovim)
- **Layer 1a** (`devbench-base:brett`): Python dev (black, pytest, ipython, uv) + Node.js + AI CLIs  
- **Layer 2** (`frappe-bench:brett`): Frappe tools (bench, MariaDB, Nginx, Redis, py-spy, web-pdb)

**Benefits:**
- ✅ < 10 second workspace startup (no build)
- ✅ All tools pre-installed and tested
- ✅ Consistent across workspaces
- ✅ Update once, all workspaces inherit

## Quick Start

Use the automated script:
```bash
./scripts/new-frappe-workspace.sh
```

Or manually:
```bash
cp -r devcontainer.example workspaces/my-workspace/.devcontainer
cd workspaces/my-workspace
code .  # Reopen in Container
```

## Pre-installed Diagnostic Tools

### Frappe-Specific (Layer 2)
- `bench` - Frappe CLI v5.28.0
- `nginx-debug` - Check config + show last 50 errors
- `frappe-doctor` - Check workers and Redis health
- `redis-monitor` - Watch Redis commands real-time
- `check-workers` - Show all Gunicorn/Node/Redis processes
- `py-spy` - Profile Python workers
- `web-pdb` - Web-based Python debugger
- `mysql`, `redis-cli` - Database/cache clients
- `multitail` - View multiple logs simultaneously

### Development Tools (Layer 1a)
- Python 3.12, black, pytest, ipython, uv
- Node.js 20.x, Yarn
- OpenCode with AI plugins

### Modern CLI (Layer 0)
- zoxide, bat, fzf, tldr, neovim, tmux

## Troubleshooting

### Image Not Found
Build Layer 2:
```bash
cd /path/to/workBenches/devBenches/frappeBench
./build-layer2.sh --user brett
```

### Nginx 502 Gateway Errors
```bash
nginx-debug          # Check config and logs
check-workers        # Verify Gunicorn running
tail -f /var/log/nginx/error.log | multitail
```

### Slow Background Jobs
```bash
frappe-doctor        # Check worker health
redis-monitor        # Watch queue
py-spy top --pid <worker-pid>  # Profile worker
```

### Database Connectivity
```bash
mysql -h mariadb -u frappe -pfrappe  # Test connection
bench doctor                          # Full health check
```

## Architecture

```
Workspace (frappe-bench:brett)
    ↓
frappe-bench:brett (Layer 2)
    ↓ extends
devbench-base:brett (Layer 1a)
    ↓ extends  
workbench-base:brett (Layer 0)
```

Shared services: MariaDB, Redis (cache/queue/socketio)

## Shared Infrastructure Stack

Database and Redis are now shared across all workspaces via the **frappe-infra** stack.

Start it once:

```bash
cd /home/brett/projects/workBenches/devBenches/frappeBench/infrastructure
docker compose up -d
```

Workspace stacks then connect to:
- `frappe-mariadb`
- `frappe-redis-cache`
- `frappe-redis-queue`
- `frappe-redis-socketio`
