# frappeBench Root DevContainer

This `.devcontainer` configuration allows you to open the frappeBench repository directly in VSCode as a devcontainer for development and testing.

## Updated to Layered Architecture

**Date Updated:** 2026-01-02

This devcontainer now uses the **layered image approach** instead of the old monolithic Dockerfile.

### What Changed:

- ✅ **Now uses:** `image: frappe-bench:brett` (pre-built layered image)
- ❌ **Old way:** `build: Dockerfile` (monolithic build from scratch)

### Benefits:

- **Instant startup** - No build time, just uses the pre-built image
- **Consistent** - Same environment as all workspaces
- **Easy updates** - Rebuild Layer 2 once, all environments benefit

## Requirements

You must have the layered image built first:

```bash
# Build Layer 2 (if not already built)
cd /home/brett/projects/workBenches/devBenches/frappeBench
./build-layer.sh --user $(whoami)
```

## Usage

### Open in VSCode:
1. Open frappeBench folder in VSCode
2. Click "Reopen in Container" when prompted
3. Container starts instantly using `frappe-bench:brett` image

### Manual Start:
```bash
cd /home/brett/projects/workBenches/devBenches/frappeBench/.devcontainer
docker compose up -d
```

## Container Details

- **Image:** `frappe-bench:brett`
- **Container name:** `frappebench-root-bench`
- **Workspace:** Mounts frappeBench root to `/workspace`
- **Network:** Connects to `frappe-network`
- **Infrastructure:** Uses shared frappe-infra (MariaDB, Redis)

## Old Files (Archived)

The following files contain the old monolithic setup (deprecated):
- `Dockerfile.old-monolithic`
- `docker-compose.yml.old-monolithic`
- `devcontainer.json.old-monolithic`

These are kept for reference only and should not be used.

## Notes

This is different from workspace devcontainers (in `workspaces/*/`):
- **This:** frappeBench root for development/testing
- **Workspaces:** Individual Frappe projects using the same layered image
