# Frappe DevContainer Template

This is the template for creating Frappe development workspaces with devcontainer configuration.

## Current Version: 1.0.0

When a new workspace is created, the contents of this folder are copied to `workspaces/<workspace-name>/.devcontainer/`.

## Files

- `devcontainer.json` - DevContainer configuration
- `Dockerfile` - Container image definition
- `docker-compose.yml` - Multi-service composition for Frappe stack
- `.env.example` - Environment variables template
- `nginx.conf` - Nginx reverse proxy configuration
- `assets/` - Additional assets for the container

## Updating Workspaces

If this template is updated, existing workspaces can be updated by running:

```bash
./setup.sh
```

This will check for version mismatches and offer to update existing workspaces while preserving their `.env` files.
