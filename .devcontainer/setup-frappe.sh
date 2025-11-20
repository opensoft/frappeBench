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
    log "$GREEN" "  ✓ Bench initialization complete."
}

ensure_bench_ready() {
    mkdir -p "$BENCH_DIR"
    if bench_is_initialized; then
        log "$GREEN" "✅ Bench detected at $BENCH_DIR (keeping existing files)"
        cd "$BENCH_DIR"
    else
        rebuild_bench
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
    if [ ! -d "$BENCH_DIR/sites/$FRAPPE_SITE_NAME" ]; then
        log "$BLUE" "[Site] Creating $FRAPPE_SITE_NAME..."
        bench new-site "$FRAPPE_SITE_NAME" \
            --mariadb-root-password "$DB_PASSWORD" \
            --admin-password "$ADMIN_PASSWORD" \
            --db-host "$DB_HOST" \
            --db-port 3306 \
            --no-mariadb-socket \
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
    log "$BLUE" "[Site] Setting default site to $FRAPPE_SITE_NAME..."
    bench use "$FRAPPE_SITE_NAME"
    log "$GREEN" "  ✓ Default site set."
}

#############################################
# Main flow
#############################################
echo "========================================"
log "$BLUE" "🚀 Frappe Bench Setup starting..."
echo "========================================"

ensure_bench_ready
ensure_apps_txt
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
