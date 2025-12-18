# Workspace Management Scripts

## Overview

These scripts provide intelligent management of Frappe development workspaces with optional AI assistance. They are designed to work from any directory and support any Frappe-based project.

**Version:** 1.0.0

## Scripts

### Main Scripts

#### `new-workspace.sh`
Creates a new development workspace with automatic configuration.

**Usage:**
```bash
scripts/new-workspace.sh [WORKSPACE_NAME]
```

**Features:**
- Auto-detects next workspace name if not provided
- Creates .devcontainer configuration
- Sets up devcontainer.json with VS Code settings
- Configures database and Redis connections
- Optionally clones app repositories (e.g., dartwing)
- AI validation before creation

**Example:**
```bash
# Auto-detect next workspace name
./scripts/new-workspace.sh

# Create specific workspace
./scripts/new-workspace.sh alpha
```

#### `update-workspace.sh`
Updates an existing workspace to the latest devcontainer template without deletion.

**Usage:**
```bash
scripts/update-workspace.sh [WORKSPACE_NAME|-all]
```

**Features:**
- Updates devcontainer files from example
- Preserves workspace configuration (.env)
- Backs up existing .env before updating
- Faster than delete/recreate
- Works from any directory

**Example:**
```bash
# Update specific workspace
./scripts/update-workspace.sh alpha

# Update all workspaces
./scripts/update-workspace.sh -all
```

#### `delete-workspace.sh`
Safely deletes a workspace with confirmation and backup.

**Usage:**
```bash
scripts/delete-workspace.sh [WORKSPACE_NAME]
```

**Features:**
- Lists available workspaces if not provided
- Validates workspace exists
- Stops containers before deletion
- Creates backup of bench data
- Requires confirmation before deletion
- AI-powered warnings about consequences

**Example:**
```bash
./scripts/delete-workspace.sh alpha
```

### Utility Libraries

Located in `scripts/lib/`:

#### `common.sh`
Shared utility functions:
- Logging functions (log_info, log_success, log_warn, log_error)
- User confirmation (confirm)
- Directory and file validation
- Error handling

#### `git-project.sh`
Git and project detection:
- Finds git root from any directory
- Validates Frappe project structure
- Identifies project type (dartwing, frappe, etc.)
- Workspace directory management

#### `ai-provider.sh`
AI provider detection and management:
- Searches for credentials in multiple locations
- Prioritizes providers: Codex → Claude → OpenAI
- Abstracts API communication
- Gracefully handles missing credentials

#### `ai-assistant.sh`
AI-powered guidance:
- Validates workspace operations
- Provides suggestions for naming
- Offers troubleshooting assistance
- Confirms destructive operations with AI insights

## Features

### Intelligent Detection
- **Works from any directory** - Scripts automatically find your project root
- **Multi-project support** - Work with dartwing-frappe, frappeBench, or any Frappe project
- **Auto-detection** - Detects workspace names, ports, configurations

### AI Assistance (Optional)
- **Provider detection** - Automatically finds your AI credentials
- **Graceful degradation** - Scripts work perfectly without AI
- **Smart validation** - Gets guidance before creating/deleting workspaces
- **Better errors** - AI helps troubleshoot issues

### Version Tracking
Each script has version metadata for synchronization across repositories:

```bash
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="new-workspace.sh"
```

## Dual Repository Setup

These scripts are maintained in two locations:

1. **Primary:** `/projects/dartwing/dartwing-frappe/scripts/`
2. **Shared:** `/projects/workBenches/devBenches/frappeBench/scripts/`

This allows users to clone either repository and have access to the workspace scripts.

### Synchronizing Across Repos

Use the sync helper to update the shared copy:

```bash
scripts/sync-to-devbench.sh
```

Features:
- Detects version differences
- Only syncs when needed
- Lists which files were updated
- Optionally commits and pushes to frappeBench

## AI Credentials Setup

Scripts automatically detect AI credentials in these locations:

```
~/.codex/                 # GitHub Codex credentials
~/.anthropic/             # Claude credentials  
~/.openai/                # OpenAI credentials
~/.config/codex/          # Alternative Codex location
~/.config/anthropic/      # Alternative Claude location
~/.config/openai/         # Alternative OpenAI location
```

### Setting Up Credentials

**For Claude (Recommended):**
```bash
mkdir -p ~/.anthropic
echo 'API_KEY=sk-ant-...' > ~/.anthropic/credentials
```

**For OpenAI:**
```bash
mkdir -p ~/.openai
echo 'API_KEY=sk-...' > ~/.openai/credentials
```

## Workspace Structure

Each workspace is created with this structure:

```
workspaces/
└── WORKSPACE_NAME/
    ├── .devcontainer/
    │   ├── Dockerfile
    │   ├── devcontainer.json
    │   ├── docker-compose.yml
    │   ├── docker-compose.override.yml
    │   ├── .env
    │   └── [other config files]
    ├── bench/
    │   ├── apps/
    │   │   └── dartwing/ (if configured)
    │   └── sites/
    └── scripts/
        └── [symlinks to shared scripts]
```

## Configuration

### Environment Variables
Each workspace has `.devcontainer/.env` with:
- `CODENAME` - Workspace identifier
- `CONTAINER_NAME` - Docker container name
- `HOST_PORT` - Port mapping (auto-assigned)
- `DB_*` - Database configuration
- `REDIS_*` - Redis configuration
- `SITE_NAME` - Frappe site name

### Port Assignment
- **NATO names** (alpha, bravo, etc.): Sequential ports (8201, 8202, ...)
- **Custom names**: Hash-based port assignment

## Troubleshooting

### Script Not Found
If running from another project:
```bash
cd /path/to/frappe/project
scripts/new-workspace.sh
```

### AI Not Available
Scripts work fine without AI - they provide basic validation and confirmation.

### Workspace Already Exists
Delete with `delete-workspace.sh` or remove manually:
```bash
rm -rf workspaces/WORKSPACE_NAME
```

### Port Conflicts
Check assigned ports in `.devcontainer/.env`:
```bash
grep HOST_PORT workspaces/*/. devcontainer/.env
```

## Version History

### v1.0.0 (Initial Release)
- AI-powered workspace management
- Multi-project support
- Git-aware path detection
- Dual repository setup with sync helper
