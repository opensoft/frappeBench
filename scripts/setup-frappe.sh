#!/bin/bash
set -euo pipefail

#############################################
# Frappe Bench bootstrap & self-healing
#############################################

# Load environment variables (excluding read-only vars)
if [ -f .devcontainer/.env ]; then
    set -a
    # Filter UID/GID so we don't clobber container user
    source <(grep -v '^#' .devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')
    set +a
fi

FRAPPE_SITE_NAME=${FRAPPE_SITE_NAME:-site1.localhost}
DB_NAME=${DB_NAME:-site1}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DB_HOST=${DB_HOST:-mariadb}
DB_PASSWORD=${DB_PASSWORD:-frappe}
BENCH_DIR=${BENCH_DIR:-/workspace/development/frappe-bench}
FRAPPE_BRANCH=${FRAPPE_BRANCH:-version-15}
PYTHON_BIN=${PYTHON_BIN:-python3.10}

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

bench_is_initialized() {
    [[ -f "$BENCH_DIR/env/bin/python" && -d "$BENCH_DIR/apps/frappe" ]]
}

rebuild_bench() {
    # Clean up any leftover temp benches from failed runs
    rm -rf /workspace/development/tmp-bench-* || true
    
    if mountpoint -q "$BENCH_DIR/apps" || { [ -d "$BENCH_DIR/apps" ] && [ "$(ls -A "$BENCH_DIR/apps" 2>/dev/null)" != "" ]; }; then
        log "$YELLOW" "⚠️  Apps directory present; performing non-destructive bench scaffold."
        local tmp_name
        tmp_name=$(mktemp -u /workspace/development/tmp-bench-XXXX)
        pushd /workspace/development >/dev/null
        bench init "$tmp_name" \
            --frappe-branch "$FRAPPE_BRANCH" \
            --python "$PYTHON_BIN" \
            --skip-redis-config-generation \
            --verbose
        popd >/dev/null
        mkdir -p "$BENCH_DIR"
        (
            cd "$tmp_name"
            tar --exclude=apps -cf - .
        ) | (
            cd "$BENCH_DIR"
            tar -xf -
        )
        # Copy apps from tmp bench to ensure frappe is up to date
        tar -cf - -C "$tmp_name" apps | tar -xf - -C "$BENCH_DIR"
        rm -rf "$tmp_name"
        log "$GREEN" "  ✓ Bench scaffolded without touching apps."
        cd "$BENCH_DIR"
        find "$BENCH_DIR/env/bin/" -type f -exec sed -i "s|$tmp_name|$BENCH_DIR|g" {} \;
        # Fix shebang to use venv python
        find "$BENCH_DIR/env/bin/" -type f -exec sed -i "s|#!/usr/bin/env python|#!/$BENCH_DIR/env/bin/python|g" {} \;
        cd "$BENCH_DIR/apps/frappe" && "$BENCH_DIR/env/bin/pip" install -e .
        cd "$BENCH_DIR" && bench setup requirements
        return
    fi

    log "$YELLOW" "⚠️  Rebuilding bench directory..."
    rm -rf "$BENCH_DIR"
    mkdir -p /workspace/development
    cd /workspace/development
    bench init frappe-bench \
        --frappe-branch "$FRAPPE_BRANCH" \
        --python "$PYTHON_BIN" \
        --skip-redis-config-generation \
        --verbose
    cd "$BENCH_DIR"
    "$BENCH_DIR/env/bin/bench" setup requirements
    log "$GREEN" "  ✓ Bench initialization complete."
}

ensure_bench_ready() {
    mkdir -p "$BENCH_DIR"
    if bench_is_initialized; then
        log "$GREEN" "✅ Bench detected at $BENCH_DIR (keeping existing files)"
        cd "$BENCH_DIR"
        bench setup requirements
        # Ensure frappe is installed in the venv
        cd "$BENCH_DIR/apps/frappe" && "$BENCH_DIR/env/bin/pip" install -e .
        export PATH="$BENCH_DIR/env/bin:$PATH"
    else
        rebuild_bench
        export PATH="$BENCH_DIR/env/bin:$PATH"
    fi
}

ensure_apps_txt() {
    local apps_file="$BENCH_DIR/sites/apps.txt"
    mkdir -p "$BENCH_DIR/sites"
    if [ ! -f "$apps_file" ]; then
        echo "frappe" > "$apps_file"
        log "$GREEN" "  ✓ Created apps.txt with frappe entry."
    elif ! grep -Fxq "frappe" "$apps_file"; then
        echo "frappe" >> "$apps_file"
        log "$GREEN" "  ✓ Added frappe to apps.txt."
    fi
}

ensure_site() {
    cd "$BENCH_DIR" || exit 1
    if [ ! -d "$BENCH_DIR/sites/$FRAPPE_SITE_NAME" ]; then
        log "$BLUE" "[Site] Creating $FRAPPE_SITE_NAME..."
        bench new-site "$FRAPPE_SITE_NAME" \
            --db-name "$DB_NAME" \
            --db-password "$DB_PASSWORD" \
            --mariadb-root-password "$DB_PASSWORD" \
            --admin-password "$ADMIN_PASSWORD" \
            --db-host "$DB_HOST" \
            --db-port 3306 \
            --no-mariadb-socket \
            --force \
            --verbose
        log "$GREEN" "  ✓ Site created."
    else
        log "$GREEN" "[Site] $FRAPPE_SITE_NAME already exists."
    fi
}

ensure_common_site_config() {
    local config_path="$BENCH_DIR/sites/common_site_config.json"
    mkdir -p "$(dirname "$config_path")"
    CONFIG_PATH="$config_path" DB_HOST="$DB_HOST" python3 <<'PY'
import json, os, sys
config_path = os.environ["CONFIG_PATH"]
target = {
    "db_host": os.environ["DB_HOST"],
    "redis_cache": "redis://redis-cache:6379",
    "redis_queue": "redis://redis-queue:6379",
    "redis_socketio": "redis://redis-socketio:6379"
}
config = {}
if os.path.exists(config_path):
    with open(config_path) as fh:
        try:
            config = json.load(fh)
        except json.JSONDecodeError:
            config = {}
changed = False
for key, value in target.items():
    if config.get(key) != value:
        config[key] = value
        changed = True
if changed or not os.path.exists(config_path):
    with open(config_path, "w") as fh:
        json.dump(config, fh, indent=2)
    print("updated")
PY
    if [ $? -eq 0 ]; then
        log "$GREEN" "[Config] common_site_config.json verified."
    else
        log "$YELLOW" "[Config] Failed to update common_site_config.json."
    fi
}

set_default_site() {
    cd "$BENCH_DIR" || exit 1
    log "$BLUE" "[Site] Setting default site to $FRAPPE_SITE_NAME..."
    bench use "$FRAPPE_SITE_NAME"
    log "$GREEN" "  ✓ Default site set."
}

validate_bench_start() {
    local log_file
    log_file=$(mktemp)
    log "$BLUE" "[Validate] Running bench start smoke test (20s timeout)..."
    set +e
    timeout --signal=SIGINT --kill-after=5 20s bench start >"$log_file" 2>&1
    local exit_code=$?
    set -e
    local failure=0
    if [[ $exit_code -ne 124 && $exit_code -ne 0 ]]; then
        failure=1
    fi
    if grep -E "ECONNREFUSED|Traceback|Procfile does not exist" "$log_file" >/dev/null; then
        failure=1
    fi
    if [[ $failure -eq 0 ]]; then
        log "$GREEN" "[Validate] Bench start health check passed."
    else
        log "$YELLOW" "[Validate] Bench start reported issues. See log output below."
        sed -n '1,200p' "$log_file"
    fi
    rm -f "$log_file"
    return $failure
}

set_default_site() {
    cd "$BENCH_DIR" || exit 1
    log "$BLUE" "[Site] Setting default site to $FRAPPE_SITE_NAME..."
    bench use "$FRAPPE_SITE_NAME"
    log "$GREEN" "  ✓ Default site set."
}

get_custom_apps() {
    cd "$BENCH_DIR" || exit 1
    # Check if CUSTOM_APPS env var is set (comma-separated list)
    if [ -n "${CUSTOM_APPS:-}" ]; then
        log "$BLUE" "[Apps] Installing custom apps: $CUSTOM_APPS"
        IFS=',' read -ra APPS <<< "$CUSTOM_APPS"
        for app_spec in "${APPS[@]}"; do
            app_spec=$(echo "$app_spec" | xargs)  # Trim whitespace
            # Format: app_name:repo_url:branch or app_name:repo_url or just app_name
            if [[ "$app_spec" == *":"* ]]; then
                IFS=':' read -r app_name repo_url branch <<< "$app_spec"
                if [ -d "$BENCH_DIR/apps/$app_name" ]; then
                    log "$YELLOW" "[Apps] $app_name already exists, skipping"
                    continue
                fi
                log "$BLUE" "[Apps] Getting $app_name from $repo_url"
                if [ -n "$branch" ]; then
                    bench get-app --branch "$branch" "$repo_url" || log "$YELLOW" "Failed to get $app_name"
                else
                    bench get-app "$repo_url" || log "$YELLOW" "Failed to get $app_name"
                fi
                # Install app to default site
                if [ -d "$BENCH_DIR/apps/$app_name" ]; then
                    log "$BLUE" "[Apps] Installing $app_name to $FRAPPE_SITE_NAME"
                    bench --site "$FRAPPE_SITE_NAME" install-app "$app_name" || log "$YELLOW" "Failed to install $app_name"
                fi
            else
                # Just app name - get from Frappe marketplace
                if [ -d "$BENCH_DIR/apps/$app_spec" ]; then
                    log "$YELLOW" "[Apps] $app_spec already exists, skipping"
                    continue
                fi
                log "$BLUE" "[Apps] Getting $app_spec from Frappe marketplace"
                bench get-app "$app_spec" || log "$YELLOW" "Failed to get $app_spec"
                # Install app to default site
                if [ -d "$BENCH_DIR/apps/$app_spec" ]; then
                    log "$BLUE" "[Apps] Installing $app_spec to $FRAPPE_SITE_NAME"
                    bench --site "$FRAPPE_SITE_NAME" install-app "$app_spec" || log "$YELLOW" "Failed to install $app_spec"
                fi
            fi
        done
    else
        log "$BLUE" "[Apps] No custom apps specified in CUSTOM_APPS env var"
    fi
}

#############################################
# Main flow
#############################################
echo "========================================"
log "$BLUE" "🚀 Frappe Bench Setup starting..."
echo "========================================"

ensure_bench_ready
get_custom_apps
ensure_apps_txt

# Wait for MariaDB to be ready before creating site
log "$BLUE" "Waiting for MariaDB to be ready..."
attempts=0
max_attempts=60  # 5 minutes max wait
until mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u root -p"$DB_PASSWORD" --silent 2>/dev/null; do
    if (( attempts >= max_attempts )); then
        log "$YELLOW" "MariaDB not ready after $((max_attempts * 5)) seconds, continuing anyway..."
        break
    fi
    log "$YELLOW" "MariaDB not ready, waiting... ($((attempts * 5))s elapsed)"
    sleep 5
    ((attempts++))
done
if (( attempts < max_attempts )); then
    log "$GREEN" "MariaDB is ready."
fi

ensure_site
ensure_common_site_config
set_default_site

if ! validate_bench_start; then
    log "$YELLOW" "Attempting full rebuild due to validation failure..."
    rebuild_bench
    ensure_apps_txt
    ensure_site
    ensure_common_site_config
    set_default_site
    if ! validate_bench_start; then
        log "$YELLOW" "Bench validation failed after rebuild. Please inspect manually."
        exit 1
    fi
fi

echo ""
echo "========================================"
log "$GREEN" "✅ Frappe setup completed successfully!"
echo "========================================"
echo "Bench directory: $BENCH_DIR"
echo "Site: $FRAPPE_SITE_NAME"
echo "Admin password: $ADMIN_PASSWORD"
echo ""
echo "You can now run: cd $BENCH_DIR && bench start"
echo ""
