# Frappe DevContainer Template

This is the template for creating Frappe development workspaces with devcontainer configuration.

**Note**: End users should open `workspaces/<name>/` (created by `./scripts/new-frappe-workspace.sh`). This folder is a template only.

## Current Version: 1.0.0

When a new workspace is created, the contents of this folder are copied to `workspaces/<workspace-name>/.devcontainer/`.

This template uses the layered workBenches images (`workbench-base` → `devbench-base` → `frappe-bench`). Build Layer 2 with `../build-layer2.sh --user <name>` if needed.

## Files

- `devcontainer.json` - DevContainer configuration
- `docker-compose.yml` - Multi-service composition for Frappe stack
- `docker-compose.override.yml` - Shared mounts/credentials (symlinked)
- `.env.example` - Environment variables template
- `nginx.conf` - Nginx reverse proxy configuration
- `assets/` - Additional assets for the container
- `scripts/` - Setup and helper scripts
- `Dockerfile.old-monolithic` - Archived (not used with layered images)

## Updating Workspaces

If this template is updated, existing workspaces can be updated by running:

```bash
./setup.sh
```

This will check for version mismatches and offer to update existing workspaces while preserving their `.env` files.
