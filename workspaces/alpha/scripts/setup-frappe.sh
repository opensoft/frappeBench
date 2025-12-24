#!/bin/bash
set -e

echo "Setting up Frappe development environment..."

# Load environment variables manually to avoid readonly issues
if [ -f "/workspace/.devcontainer/.env" ]; then
    export FRAPPE_BENCH_PATH=$(grep "^FRAPPE_BENCH_PATH=" /workspace/.devcontainer/.env | cut -d'=' -f2)
    export SITE_NAME=$(grep "^SITE_NAME=" /workspace/.devcontainer/.env | cut -d'=' -f2)
    export ADMIN_PASSWORD=$(grep "^ADMIN_PASSWORD=" /workspace/.devcontainer/.env | cut -d'=' -f2)
    export DB_HOST=$(grep "^DB_HOST=" /workspace/.devcontainer/.env | cut -d'=' -f2)
    export DB_PORT=$(grep "^DB_PORT=" /workspace/.devcontainer/.env | cut -d'=' -f2)
fi

# Set default values
FRAPPE_BENCH_PATH="${FRAPPE_BENCH_PATH:-/workspace/bench}"

# Change to workspace root
cd /workspace

# Initialize Frappe bench if not already done
if [ ! -d "$FRAPPE_BENCH_PATH/apps/frappe" ]; then
    echo "Initializing Frappe bench in $FRAPPE_BENCH_PATH..."
    export CLAUDE_CODE_DISABLED=1
    bench init "$FRAPPE_BENCH_PATH" --frappe-branch version-15 --skip-redis-config-generation --skip-assets
else
    echo "Frappe bench already initialized"
fi

echo "Frappe setup completed successfully"