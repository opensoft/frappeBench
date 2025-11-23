#!/bin/bash
set -euo pipefail

# Setup script for sites and apps - runs in container after bench is ready
# Requires frappe-apps.json to exist (can be empty array [])

CONFIG_FILE=".devcontainer/frappe-apps.json"

# Load env except UID/GID to avoid clobbering container user
if [ -f .devcontainer/.env ]; then
    set -a
    source <(grep -v '^#' .devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')
    set +a
fi

BENCH_DIR=${BENCH_DIR:-/workspace/development/frappe-bench}

log() {
    local level="$1"; shift
    echo "[setup-apps][$level] $*"
}

# Validate that frappe-apps.json exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log ERROR "Required configuration file $CONFIG_FILE not found!"
    log ERROR "Please create $CONFIG_FILE based on frappe-apps.example.json"
    log ERROR "The file can be an empty array [] but must exist."
    exit 1
fi

# Validate JSON syntax
if ! python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
    log ERROR "Invalid JSON in $CONFIG_FILE"
    log ERROR "Please check the JSON syntax and try again."
    exit 1
fi

# Validate JSON structure (must be an array)
if ! python3 - <<'PY' 2>/dev/null; then
import json, sys
with open('.devcontainer/frappe-apps.json') as f:
    data = json.load(f)
    if not isinstance(data, list):
        print("ERROR: frappe-apps.json must be a JSON array", file=sys.stderr)
        sys.exit(1)
PY
    log ERROR "frappe-apps.json must be a JSON array"
    exit 1
fi

log INFO "Configuration file $CONFIG_FILE validated successfully"

read_entries() {
    python3 - <<'PY'
import json, sys
from pathlib import Path

path = Path(".devcontainer/frappe-apps.json")
try:
    with open(path) as f:
        data = json.load(f)
except Exception as exc:
    print(f"[setup-apps][ERROR] Failed to parse frappe-apps.json: {exc}", file=sys.stderr)
    sys.exit(1)

for item in data:
    if not isinstance(item, dict):
        continue
    app = (item.get("app") or "").strip()
    repo = (item.get("source") or "").strip()
    site = (item.get("site") or "").strip()
    site_admin_password = (item.get("site_admin_password") or "").strip()
    site_db_name = (item.get("site_db_name") or "").strip()

    if not app:
        continue

    print(json.dumps({
        "name": app,
        "repo": repo,
        "site": site,
        "site_admin_password": site_admin_password,
        "site_db_name": site_db_name,
    }))
PY
}

ensure_apps_txt_entry() {
    local app="$1"
    local apps_file="$BENCH_DIR/sites/apps.txt"
    mkdir -p "$(dirname "$apps_file")"
    touch "$apps_file"
    if ! grep -Fxq "$app" "$apps_file"; then
        echo "$app" >> "$apps_file"
        log INFO "Added $app to apps.txt"
    fi
}

ensure_site_exists() {
    local site="$1"
    local admin_password="${2:-admin}"
    local db_name="${3:-}"

    if [ -z "$site" ]; then
        return
    fi

    if [ ! -d "$BENCH_DIR/sites/$site" ]; then
        log INFO "Creating site $site"
        local cmd="bench new-site \"$site\" --admin-password \"$admin_password\" --db-root-password \"${DB_PASSWORD:-frappe}\" --db-host \"${DB_HOST:-mariadb}\" --no-mariadb-socket --force"
        if [ -n "$db_name" ]; then
            cmd="$cmd --db-name \"$db_name\""
        fi
        eval "$cmd" >/dev/null 2>&1 || log WARN "Failed to create site $site"
    else
        log INFO "Site $site exists"
    fi
}

ensure_app_installed() {
    local site="$1" app="$2"
    if [ -z "$site" ]; then
        return
    fi
    if bench --site "$site" list-apps | grep -Fxq "$app"; then
        log INFO "App $app already installed on $site"
    else
        log INFO "Installing $app on $site"
        bench --site "$site" install-app "$app" >/dev/null 2>&1 || log WARN "Failed to install $app on $site"
    fi
}

main() {
    local entries
    mapfile -t entries < <(read_entries)

    if [[ ${#entries[@]} -eq 0 ]]; then
        log INFO "No apps configured in frappe-apps.json"
        exit 0
    fi

    # Ensure we're in the bench directory
    cd "$BENCH_DIR" || {
        log ERROR "Cannot cd to bench directory: $BENCH_DIR"
        exit 1
    }

    for row in "${entries[@]}"; do
        temp_file=$(mktemp)
        echo "$row" > "$temp_file"
        name=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj["name"])
PY
)
        site=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj["site"])
PY
)
        site_admin_password=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj.get("site_admin_password", ""))
PY
)
        site_db_name=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj.get("site_db_name", ""))
PY
)
        rm -f "$temp_file"

        # Add app to apps.txt
        ensure_apps_txt_entry "$name"

        # Create site if specified
        if [[ -n "$site" ]]; then
            ensure_site_exists "$site" "$site_admin_password" "$site_db_name"
            ensure_app_installed "$site" "$name"
        fi
    done
}

main