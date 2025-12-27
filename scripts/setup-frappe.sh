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

FRAPPE_SITE_NAME=${FRAPPE_SITE_NAME:-${SITE_NAME:-site1.localhost}}
DB_NAME=${DB_NAME:-site1}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DB_HOST=${DB_HOST:-mariadb}
DB_PORT=${DB_PORT:-3306}
DB_PASSWORD=${DB_PASSWORD:-frappe}
BENCH_DIR=${BENCH_DIR:-${FRAPPE_BENCH_PATH:-/workspace/development/frappe-bench}}
FRAPPE_BRANCH=${FRAPPE_BRANCH:-version-15}
PYTHON_BIN=${PYTHON_BIN:-python3.10}
FRAPPE_TEMPLATE_DIR=${FRAPPE_TEMPLATE_DIR:-/opt/frappe-bench-template}
BENCH_REQUIREMENTS_SENTINEL=${BENCH_REQUIREMENTS_SENTINEL:-.bench-requirements-ok}
BENCH_PARENT=$(dirname "$BENCH_DIR")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

# Patch frappe's python-dateutil requirement to resolve conflict with holidays
# frappe requires ~=2.8.2, holidays requires >=2.9.0.post0
patch_frappe_dateutil_requirement() {
    local pyproject="$BENCH_DIR/apps/frappe/pyproject.toml"
    if [ ! -f "$pyproject" ]; then
        return 0
    fi

    # Check if already patched
    if grep -q 'python-dateutil>=2.8.2,<3' "$pyproject"; then
        return 0
    fi

    log "$BLUE" "[Patch] Relaxing frappe's python-dateutil constraint..."
    sed -i 's/"python-dateutil~=2.8.2"/"python-dateutil>=2.8.2,<3"/g' "$pyproject"
    log "$GREEN" "  ✓ Patched python-dateutil requirement."
}

bench_is_initialized() {
    [[ -f "$BENCH_DIR/env/bin/python" && -d "$BENCH_DIR/apps/frappe" ]]
}

apps_dir_has_content() {
    mountpoint -q "$BENCH_DIR/apps" || { [ -d "$BENCH_DIR/apps" ] && [ "$(ls -A "$BENCH_DIR/apps" 2>/dev/null)" != "" ]; }
}

template_available() {
    [[ -d "$FRAPPE_TEMPLATE_DIR/env" && -d "$FRAPPE_TEMPLATE_DIR/apps/frappe" ]]
}

install_bench_apps() {
    local apps_file="$BENCH_DIR/sites/apps.txt"
    if [ ! -f "$apps_file" ]; then
        return 0
    fi

    while read -r app; do
        [ -z "$app" ] && continue
        local app_path="$BENCH_DIR/apps/$app"
        if [ -d "$app_path" ]; then
            if [ -f "$app_path/pyproject.toml" ] || [ -f "$app_path/setup.py" ] || [ -f "$app_path/setup.cfg" ]; then
                "$BENCH_DIR/env/bin/pip" install -e "$app_path"
            fi
        fi
    done < "$apps_file"
}

seed_bench_from_template() {
    log "$BLUE" "[Template] Seeding bench from $FRAPPE_TEMPLATE_DIR..."
    rm -rf "$BENCH_DIR"
    mkdir -p "$BENCH_DIR"
    (
        cd "$FRAPPE_TEMPLATE_DIR"
        tar -cf - .
    ) | (
        cd "$BENCH_DIR"
        tar -xf -
    )
    find "$BENCH_DIR/env/bin/" -type f -exec sed -i "s|$FRAPPE_TEMPLATE_DIR|$BENCH_DIR|g" {} \;
    find "$BENCH_DIR/env/bin/" -type f -exec sed -i "s|#!/usr/bin/env python|#!/$BENCH_DIR/env/bin/python|g" {} \;
    patch_frappe_dateutil_requirement
    install_bench_apps
    touch "$BENCH_DIR/$BENCH_REQUIREMENTS_SENTINEL"
    log "$GREEN" "  ✓ Bench seeded from template."
}

rebuild_bench() {
    # Clean up any leftover temp benches from failed runs
    rm -rf "$BENCH_PARENT"/tmp-bench-* || true
    
    if apps_dir_has_content; then
        log "$YELLOW" "⚠️  Apps directory present; performing non-destructive bench scaffold."
        local tmp_name
        tmp_name=$(mktemp -u "$BENCH_PARENT/tmp-bench-XXXX")
        mkdir -p "$BENCH_PARENT"
        pushd "$BENCH_PARENT" >/dev/null
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
        patch_frappe_dateutil_requirement
        cd "$BENCH_DIR/apps/frappe" && "$BENCH_DIR/env/bin/pip" install -e .
        cd "$BENCH_DIR" && bench setup requirements
        touch "$BENCH_DIR/$BENCH_REQUIREMENTS_SENTINEL"
        return
    fi

    log "$YELLOW" "⚠️  Rebuilding bench directory..."
    rm -rf "$BENCH_DIR"
    mkdir -p "$BENCH_PARENT"
    cd "$BENCH_PARENT"
    bench init "$BENCH_DIR" \
        --frappe-branch "$FRAPPE_BRANCH" \
        --python "$PYTHON_BIN" \
        --skip-redis-config-generation \
        --verbose
    cd "$BENCH_DIR"
    bench setup requirements
    touch "$BENCH_DIR/$BENCH_REQUIREMENTS_SENTINEL"
    log "$GREEN" "  ✓ Bench initialization complete."
}

ensure_bench_ready() {
    mkdir -p "$BENCH_DIR"
    if bench_is_initialized; then
        log "$GREEN" "✅ Bench detected at $BENCH_DIR (keeping existing files)"
        cd "$BENCH_DIR"
        if [ ! -f "$BENCH_DIR/$BENCH_REQUIREMENTS_SENTINEL" ]; then
            patch_frappe_dateutil_requirement
            bench setup requirements
            touch "$BENCH_DIR/$BENCH_REQUIREMENTS_SENTINEL"
        fi
        # Ensure apps are installed in the venv
        patch_frappe_dateutil_requirement
        install_bench_apps
        export PATH="$BENCH_DIR/env/bin:$PATH"
    else
        if template_available && ! apps_dir_has_content; then
            seed_bench_from_template
        else
            rebuild_bench
        fi
        export PATH="$BENCH_DIR/env/bin:$PATH"
    fi
}

ensure_bench_cli() {
    local bench_bin="$BENCH_DIR/env/bin/bench"
    if [ ! -x "$bench_bin" ]; then
        log "$YELLOW" "[Bench] Installing bench into venv..."
        if ! "$BENCH_DIR/env/bin/python" -m pip install --upgrade frappe-bench; then
            log "$YELLOW" "[Bench] Failed to install bench into venv; falling back to global bench."
        fi
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
ensure_bench_cli
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
