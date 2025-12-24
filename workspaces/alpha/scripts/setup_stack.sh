#!/bin/bash

# ==============================================================================
# This script automates the setup of a Frappe bench environment based on a
# frappe-stack.json file. It installs apps, creates sites, and installs
# apps on those sites.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Setting up Frappe stack..."

# --- Load Environment Variables ---
if [ -f "/workspace/.devcontainer/.env" ]; then
    export FRAPPE_BENCH_PATH=$(grep "^FRAPPE_BENCH_PATH=" /workspace/.devcontainer/.env | cut -d'=' -f2)
    export SITE_NAME=$(grep "^SITE_NAME=" /workspace/.devcontainer/.env | cut -d'=' -f2)
fi

# --- Configuration ---
FRAPPE_BENCH_PATH="${FRAPPE_BENCH_PATH:-/workspace/bench}"
STACK_FILE="/workspace/.devcontainer/frappe-stack.json"
DB_ROOT_PASSWORD="frappe" # As determined from docker-compose files.

# Disable Claude Code for bench commands to avoid recursion
export CLAUDE_CODE_DISABLED=1

# --- Pre-flight Checks ---

# 1. Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to proceed."
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    exit 1
fi

# 2. Check for stack file
if [ ! -f "$STACK_FILE" ]; then
    echo "Warning: $STACK_FILE not found. Skipping stack setup."
    exit 0
fi

# 3. Check for bench directory
if [ ! -d "$FRAPPE_BENCH_PATH" ]; then
    echo "Error: Bench directory not found at $FRAPPE_BENCH_PATH."
    echo "Please run setup-frappe.sh first to initialize the bench."
    exit 1
fi

# --- Main Execution ---

echo "Changing directory to the Frappe bench: $FRAPPE_BENCH_PATH"
cd "$FRAPPE_BENCH_PATH"

# --- App Installation ---

# Read app list from JSON and install each one
echo "Processing apps for installation..."
jq -c '.apps[]' "$STACK_FILE" | while read -r app; do
    APP_NAME=$(echo "$app" | jq -r '.name')
    APP_REPO=$(echo "$app" | jq -r '.repo')
    APP_BRANCH=$(echo "$app" | jq -r '.branch // ""') # Use empty string if branch is null

    echo "--------------------------------------------------"
    echo "Getting app: $APP_NAME"
    echo "  Repo: $APP_REPO"

    if [ -d "apps/$APP_NAME" ]; then
        echo "  App directory 'apps/$APP_NAME' already exists. Skipping 'bench get-app'."
    else
        if [ -n "$APP_BRANCH" ]; then
            echo "  Branch: $APP_BRANCH"
            bench get-app --branch "$APP_BRANCH" "$APP_REPO"
        else
            bench get-app "$APP_REPO"
        fi
    fi
    echo "--------------------------------------------------"
done

# --- Site Creation and App Installation ---

echo "Processing sites for creation..."
jq -c '.sites[]' "$STACK_FILE" | while read -r site; do
    SITE_NAME=$(echo "$site" | jq -r '.name')
    ADMIN_PASSWORD=$(echo "$site" | jq -r '.admin_password')

    echo "=================================================="
    echo "Processing site: $SITE_NAME"

    # Check if site exists
    if [ -d "sites/$SITE_NAME" ]; then
        echo "Site '$SITE_NAME' already exists. Skipping creation."
    else
        echo "Creating new site: $SITE_NAME"
        bench new-site "$SITE_NAME" --admin-password "$ADMIN_PASSWORD" --db-root-password "$DB_ROOT_PASSWORD" --force
    fi

    # Install apps on the site
    echo "Installing apps on $SITE_NAME..."
    jq -c '.apps[]' <<< "$site" | while read -r app_name_to_install; do
        # The app name from the site's app list is a string, so remove quotes
        APP_TO_INSTALL=$(echo "$app_name_to_install" | jq -r '.')

        # Check if app is already installed
        if bench --site "$SITE_NAME" list-apps | grep -q "^$APP_TO_INSTALL$"; then
            echo "  App '$APP_TO_INSTALL' is already installed on site '$SITE_NAME'. Skipping."
        else
            echo "  Installing app: $APP_TO_INSTALL"
            bench --site "$SITE_NAME" install-app "$APP_TO_INSTALL"
        fi
    done
    echo "=================================================="
done

# --- Health Check ---

echo "Running bench health check..."
bench doctor || echo "Bench doctor check completed with warnings (non-critical)."

echo ""
echo "✅ Frappe stack setup completed successfully!"
echo ""
echo "To start the development server, run:"
echo "  cd $FRAPPE_BENCH_PATH && bench start"
