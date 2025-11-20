#!/bin/bash
set -euo pipefail

#############################################
# Dartwing site + app bootstrap (idempotent)
#############################################

# General configuration
BENCH_PATH=${BENCH_PATH:-/workspace/development/frappe-bench}
SITE_NAME=${SITE_NAME:-dartwing.localhost}
APP_NAME=${APP_NAME:-dartwing}
APP_REPO=${APP_REPO:-https://github.com/Opensoft/frappe-app-dartwing.git}
APP_BRANCH=${APP_BRANCH:-main}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-frappe}
MARIADB_HOST=${MARIADB_HOST:-mariadb}

# Helper output formatting
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

if [ ! -d "$BENCH_PATH" ]; then
    log "$YELLOW" "Bench directory $BENCH_PATH not found. Run setup-frappe.sh first."
    exit 1
fi

export PATH="$PATH:$HOME/.local/bin:$BENCH_PATH/env/bin"
export PYTHONPATH="$BENCH_PATH/apps:$PYTHONPATH"

cd "$BENCH_PATH"

#############################################
# Step 1: MariaDB host
#############################################
log "$BLUE" "[1/5] Ensuring MariaDB host is set to $MARIADB_HOST..."
if ! grep -q '"db_host"' sites/common_site_config.json 2>/dev/null; then
    bench set-mariadb-host "$MARIADB_HOST"
    log "$GREEN" "  ✓ db_host saved."
else
    log "$GREEN" "  ✓ db_host already configured."
fi

#############################################
# Step 2: Site creation
#############################################
log "$BLUE" "[2/5] Checking site $SITE_NAME..."
if [ ! -d "sites/$SITE_NAME" ]; then
    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --db-host "$MARIADB_HOST" \
        --no-mariadb-socket
    log "$GREEN" "  ✓ Site created."
else
    log "$GREEN" "  ✓ Site already exists, skipping creation."
fi

#############################################
# Step 3: Dartwing app checkout/refresh
#############################################
APP_DIR="$BENCH_PATH/apps/$APP_NAME"
clone_app() {
    bench get-app --branch "$APP_BRANCH" "$APP_REPO" "$APP_NAME"
}

log "$BLUE" "[3/5] Ensuring $APP_NAME app is cloned from $APP_REPO..."
if [ -d "$APP_DIR/.git" ]; then
    if git -C "$APP_DIR" diff --quiet && git -C "$APP_DIR" diff --cached --quiet; then
        log "$YELLOW" "  → No local changes detected. Refreshing checkout..."
        rm -rf "$APP_DIR"
        clone_app
        log "$GREEN" "  ✓ Re-cloned clean copy."
    else
        log "$YELLOW" "  → Local changes found; leaving existing checkout untouched."
    fi
elif [ -d "$APP_DIR" ]; then
    log "$YELLOW" "  → Directory exists but is not a git repo; replacing..."
    rm -rf "$APP_DIR"
    clone_app
    log "$GREEN" "  ✓ App cloned."
else
    clone_app
    log "$GREEN" "  ✓ App cloned."
fi

#############################################
# Step 4: Install app on site
#############################################
log "$BLUE" "[4/5] Ensuring $APP_NAME is installed on $SITE_NAME..."
if bench --site "$SITE_NAME" list-apps | grep -Fxq "$APP_NAME"; then
    log "$GREEN" "  ✓ App already installed."
else
    bench --site "$SITE_NAME" install-app "$APP_NAME"
    log "$GREEN" "  ✓ App installed."
fi

#############################################
# Step 5: Set default site
#############################################
log "$BLUE" "[5/5] Setting $SITE_NAME as default bench site..."
bench use "$SITE_NAME"
log "$GREEN" "  ✓ Default site updated."

echo ""
echo "=========================================="
log "$GREEN" "Dartwing environment ready!"
echo "Site URL:  http://localhost:8081 (via nginx profile) or http://localhost:8000 (bench start)"
echo "App path:  $APP_DIR"
echo "=========================================="
