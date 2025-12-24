# FrappeBench Workspace Setup System

## Overview

FrappeBench now has a workspace creation system similar to the dartwing/frappe project. This allows you to create multiple independent Frappe development workspaces, each with its own devcontainer configuration.

## Architecture

### Template System
- **`devcontainer.example/`** - Master template for all workspaces
  - Contains all devcontainer configuration files (Dockerfile, docker-compose.yml, devcontainer.json, etc.)
  - Version tracked in `devcontainer.example/README.md`
  - When a new workspace is created, this entire folder is copied to `workspaces/<name>/.devcontainer/`

### Workspaces Directory
- **`workspaces/`** - Container for all workspace instances
  - Each subdirectory is an independent workspace (e.g., `alpha`, `bravo`, `charlie`)
  - Workspaces can be created, updated, or deleted independently
  - Each workspace has its own `.devcontainer/` configuration and `.env` file

## Usage

### Initial Setup
Run the setup script to initialize the workspace system:

```bash
./setup.sh
```

This script will:
1. Check for required files (devcontainer.example, workspace scripts)
2. Create the workspaces directory
3. Check for outdated workspaces and offer to update them
4. Create the default "alpha" workspace

### Creating New Workspaces

Create a new workspace with a NATO phonetic name:

```bash
./scripts/new-frappe-workspace.sh bravo
./scripts/new-frappe-workspace.sh charlie
```

Or let the script auto-detect the next name:

```bash
./scripts/new-frappe-workspace.sh
```

Each workspace will:
- Be created in `workspaces/<name>/`
- Get its own copy of the devcontainer template
- Have a unique port assignment (8201 for alpha, 8202 for bravo, etc.)
- Get a workspace-specific `.env` file with unique settings

### Opening a Workspace

```bash
cd workspaces/alpha
code .
```

When VSCode opens, click "Reopen in Container" to start the development environment.

### Deleting Workspaces

```bash
./scripts/delete-frappe-workspace.sh alpha
```

### Updating Workspaces

When the master template (`devcontainer.example/`) is updated, run setup.sh to update existing workspaces:

```bash
./setup.sh
```

It will:
- Detect version mismatches
- Offer to update outdated workspaces
- Backup existing `.devcontainer/` configurations
- Preserve workspace-specific `.env` files

## File Structure

```
frappeBench/
├── .devcontainer/           # Original single workspace config (kept for reference)
├── devcontainer.example/    # Master template for new workspaces
│   ├── README.md           # Version tracking
│   ├── Dockerfile
│   ├── devcontainer.json
│   ├── docker-compose.yml
│   ├── .env.example
│   └── ...
├── workspaces/             # All workspace instances
│   ├── alpha/              # First workspace
│   │   ├── .devcontainer/  # Copy of devcontainer.example (customized)
│   │   ├── bench/
│   │   └── scripts/
│   ├── bravo/              # Additional workspaces
│   │   └── .devcontainer/
│   └── ...
├── scripts/
│   ├── new-frappe-workspace.sh      # Create new workspace
│   ├── delete-frappe-workspace.sh   # Delete workspace
│   └── ...
└── setup.sh                # Initialize/update workspace system
```

## Environment Variables per Workspace

Each workspace has its own `.devcontainer/.env` with:
- `CODENAME` - Workspace name
- `CONTAINER_NAME` - Unique container identifier
- `HOST_PORT` - Unique port mapping (8201, 8202, etc.)
- `DB_NAME` - Workspace-specific database
- `SITE_NAME` - Frappe site name

## Version Management

Template versions are tracked in `devcontainer.example/README.md`:

```
## Current Version: 1.0.0
```

The setup script compares this with workspace versions and offers updates when mismatched.

## Key Differences from Single Workspace Setup

- **Before**: `.devcontainer/` was a single configuration
- **Now**: 
  - `devcontainer.example/` is the master template
  - Each workspace gets its own customized copy in `workspaces/<name>/.devcontainer/`
  - Multiple independent workspaces can run simultaneously
  - Each workspace has isolated databases and configurations

## Compatibility

- This system mirrors the dartwing/frappe workspace architecture
- Existing `.devcontainer/` folder is preserved for backward compatibility
- New workspaces use the `devcontainer.example/` template
