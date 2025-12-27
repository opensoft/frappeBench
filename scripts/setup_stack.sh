#!/bin/bash

# ==============================================================================
# This script automates the setup of a Frappe bench environment based on a
# frappe-stack.json file. It installs apps, creates sites, and installs
# apps on those sites.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
STACK_FILE="/workspace/.devcontainer/frappe-stack.json"

# Load environment variables (excluding read-only vars)
if [ -f /workspace/.devcontainer/.env ]; then
    set -a
    # Filter UID/GID so we don't clobber container user
    source <(grep -v '^#' /workspace/.devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')
    set +a
fi

BENCH_DIR=${BENCH_DIR:-${FRAPPE_BENCH_PATH:-/workspace/development/frappe-bench}}
DB_HOST=${DB_HOST:-frappe-mariadb}
DB_PORT=${DB_PORT:-3306}
DB_ROOT_USER=${DB_ROOT_USER:-root}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-${DB_PASSWORD:-frappe}}
APP_CACHE_DIR=${APP_CACHE_DIR:-/opt/frappe-app-cache}

# --- Pre-flight Checks ---

# 1. Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to proceed."
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    echo "On macOS: brew install jq"
    exit 1
fi

# 2. Check for stack file
if [ ! -f "$STACK_FILE" ]; then
    echo "Error: $STACK_FILE not found in the project root."
    exit 1
fi

# 3. Check for bench directory
if [ ! -d "$BENCH_DIR" ]; then
    echo "Warning: Bench directory not found at $BENCH_DIR."
    echo "This likely means setup-frappe.sh did not complete successfully."
    echo "Skipping stack setup - run 'bash scripts/setup-frappe.sh' first, then re-run this script."
    exit 0  # Exit gracefully so container creation continues
fi

# Ensure bench venv takes precedence (avoid global bench)
if [ -d "${BENCH_DIR}/env/bin" ]; then
    export PATH="${BENCH_DIR}/env/bin:${PATH}"
fi

# --- Helpers ---

ensure_site_db_access() {
    local site_name="$1"
    local site_config="sites/$site_name/site_config.json"

    if [ ! -f "$site_config" ]; then
        echo "  Site config not found for $site_name; skipping DB credential check."
        return 0
    fi

    local db_name
    local db_password
    db_name=$(jq -r '.db_name // empty' "$site_config")
    db_password=$(jq -r '.db_password // empty' "$site_config")

    if [ -z "$db_name" ] || [ -z "$db_password" ]; then
        echo "  Site config missing db_name/db_password; skipping DB credential check."
        return 0
    fi

    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$db_name" -p"$db_password" -e "SELECT 1" >/dev/null 2>&1; then
        echo "  DB credentials verified for $db_name."
        return 0
    fi

    echo "  DB credentials mismatch for $db_name; attempting repair..."
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        echo "  Error: cannot connect to MariaDB as root; aborting."
        return 1
    fi

    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
        -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    local hosts
    hosts=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -B \
        -e "SELECT Host FROM mysql.user WHERE User='$db_name';")

    if [ -z "$hosts" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
            -e "CREATE USER IF NOT EXISTS '$db_name'@'%' IDENTIFIED BY '$db_password';"
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
            -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_name'@'%';"
    else
        while read -r host; do
            [ -z "$host" ] && continue
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
                -e "ALTER USER '$db_name'@'$host' IDENTIFIED BY '$db_password';"
        done <<< "$hosts"
    fi

    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$db_name" -p"$db_password" -e "SELECT 1" >/dev/null 2>&1; then
        echo "  DB credentials repaired for $db_name."
        return 0
    fi

    echo "  Warning: DB credentials still failing for $db_name."
    return 1
}

ensure_apps_txt_entry() {
    local app_name="$1"
    local apps_file="sites/apps.txt"

    mkdir -p "sites"
    if [ ! -f "$apps_file" ]; then
        echo "frappe" > "$apps_file"
    fi

    if ! grep -Fxq "$app_name" "$apps_file"; then
        echo "$app_name" >> "$apps_file"
    fi
}

get_site_db_name() {
    local site_name="$1"
    local site_config="sites/$site_name/site_config.json"

    if [ -f "$site_config" ]; then
        jq -r '.db_name // empty' "$site_config"
    else
        BENCH_DIR="$BENCH_DIR" compute_site_db_name "$site_name"
    fi
}

get_site_db_password() {
    local site_name="$1"
    local site_config="sites/$site_name/site_config.json"

    if [ -f "$site_config" ]; then
        jq -r '.db_password // empty' "$site_config"
    else
        echo ""
    fi
}

site_schema_ready() {
    local site_name="$1"
    local db_name
    local db_password

    db_name=$(get_site_db_name "$site_name")
    db_password=$(get_site_db_password "$site_name")

    if [ -z "$db_name" ] || [ -z "$db_password" ]; then
        return 1
    fi

    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$db_name" -p"$db_password" -N -B \
        -e "SELECT 1 FROM information_schema.tables WHERE table_schema='${db_name}' AND table_name='tabDefaultValue' LIMIT 1;" \
        2>/dev/null | grep -q '^1$'
}

compute_site_db_name() {
    local site_name="$1"
    python3 - "$site_name" <<'PY'
import hashlib
import os
import sys

bench_dir = os.environ["BENCH_DIR"]
site_name = sys.argv[1]
site_path = os.path.realpath(os.path.join(bench_dir, "sites", site_name))
db_name = "_" + hashlib.sha1(site_path.encode(), usedforsecurity=False).hexdigest()[:16]
print(db_name)
PY
}

cleanup_site_db_user() {
    local db_name="$1"

    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        echo "  Warning: cannot connect to MariaDB as root; skipping DB user cleanup."
        return 0
    fi

    local hosts
    hosts=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -B \
        -e "SELECT Host FROM mysql.user WHERE User='$db_name';")

    if [ -n "$hosts" ]; then
        while read -r host; do
            [ -z "$host" ] && continue
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
                -e "DROP USER IF EXISTS '$db_name'@'$host';"
        done <<< "$hosts"
    fi

    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
        -e "DROP DATABASE IF EXISTS \`$db_name\`;"
}

clone_app_repo() {
    local repo="$1"
    local app_name="$2"
    local branch="$3"
    local target="apps/$app_name"

    if [ -d "$target" ]; then
        return 0
    fi

    if [ -n "$branch" ]; then
        git clone --depth 1 --branch "$branch" --origin upstream "$repo" "$target"
    else
        git clone --depth 1 --origin upstream "$repo" "$target"
    fi
}

ensure_cached_app() {
    local repo="$1"
    local app_name="$2"
    local branch="$3"

    if [ -z "${APP_CACHE_DIR:-}" ]; then
        return 1
    fi

    mkdir -p "$APP_CACHE_DIR"
    local cache_dir="${APP_CACHE_DIR}/${app_name}"

    if [ ! -d "$cache_dir/.git" ]; then
        if [ -n "$branch" ]; then
            git clone --depth 1 --branch "$branch" --origin upstream "$repo" "$cache_dir"
        else
            git clone --depth 1 --origin upstream "$repo" "$cache_dir"
        fi
    fi

    if [ -e "apps/$app_name" ] && [ ! -L "apps/$app_name" ]; then
        echo "  App directory exists; skipping cache link."
        return 0
    fi

    ln -sfn "$cache_dir" "apps/$app_name"
    return 0
}

ensure_dartwing_uv_deps() {
    local pyproject="apps/dartwing/pyproject.toml"
    local dep="gunicorn @ git+https://github.com/frappe/gunicorn@bb554053bb87218120d76ab6676af7015680e8b6"

    if [ ! -f "$pyproject" ]; then
        return 0
    fi

    if grep -q "$dep" "$pyproject"; then
        return 0
    fi

    python3 - <<'PY'
import pathlib

path = pathlib.Path("apps/dartwing/pyproject.toml")
dep = "gunicorn @ git+https://github.com/frappe/gunicorn@bb554053bb87218120d76ab6676af7015680e8b6"

text = path.read_text()
if dep in text:
    raise SystemExit(0)

lines = text.splitlines()
out = []
added = False
in_deps = False

def ensure_trailing_comma(lines_out):
    for idx in range(len(lines_out) - 1, -1, -1):
        candidate = lines_out[idx].strip()
        if not candidate or candidate.startswith("#"):
            continue
        if not candidate.endswith(",") and candidate != "[":
            lines_out[idx] = lines_out[idx].rstrip() + ","
        break

for line in lines:
    stripped = line.strip()
    if stripped.startswith("dependencies") and stripped.endswith("["):
        in_deps = True
        out.append(line)
        continue

    if in_deps:
        if dep in stripped:
            added = True
        if stripped == "]":
            if not added:
                ensure_trailing_comma(out)
                out.append(f'    "{dep}",')
                added = True
            out.append(line)
            in_deps = False
            continue
        out.append(line)
        continue

    out.append(line)

if not added:
    # Fallback: append dependency block if missing
    out.append("")
    out.append("dependencies = [")
    out.append(f'    "{dep}",')
    out.append("]")
    added = True

if added:
    path.write_text("\n".join(out) + "\n")
PY
}

ensure_app_python_install() {
    local app_name="$1"
    local app_path="apps/$app_name"

    if [ ! -d "$app_path" ]; then
        return 0
    fi

    if [ -f "$app_path/pyproject.toml" ] || [ -f "$app_path/setup.py" ] || [ -f "$app_path/setup.cfg" ]; then
        "${BENCH_DIR}/env/bin/python" -m pip install -e "$app_path"
    fi
}

ensure_app_in_apps_txt() {
    local app_name="$1"
    local apps_txt="sites/apps.txt"

    # Create apps.txt with frappe if it doesn't exist
    if [ ! -f "$apps_txt" ]; then
        echo "frappe" > "$apps_txt"
    fi

    # Add app to apps.txt if not already present
    if ! grep -Fxq "$app_name" "$apps_txt"; then
        echo "  Registering $app_name in apps.txt"
        # Ensure file ends with newline before appending
        if [ -s "$apps_txt" ] && [ -n "$(tail -c1 "$apps_txt")" ]; then
            echo "" >> "$apps_txt"
        fi
        echo "$app_name" >> "$apps_txt"
    fi
}

# --- Main Execution ---

echo "Changing directory to the Frappe bench: $BENCH_DIR"
cd "$BENCH_DIR"

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
    
    ensure_apps_txt_entry "$APP_NAME"
    ensure_cached_app "$APP_REPO" "$APP_NAME" "$APP_BRANCH" || true

    if [ -d "apps/$APP_NAME" ]; then
        echo "  App directory 'apps/$APP_NAME' already exists. Skipping 'bench get-app'."
        if [ "$APP_NAME" = "dartwing" ]; then
            ensure_dartwing_uv_deps
            ensure_app_in_apps_txt "$APP_NAME"
        fi
        ensure_app_python_install "$APP_NAME"
    else
        if [ "$APP_NAME" = "dartwing" ]; then
            if [ -n "$APP_BRANCH" ]; then
                echo "  Branch: $APP_BRANCH"
            fi
            clone_app_repo "$APP_REPO" "$APP_NAME" "$APP_BRANCH"
            ensure_dartwing_uv_deps
            ensure_app_python_install "$APP_NAME"
            ensure_app_in_apps_txt "$APP_NAME"
        else
            if [ -n "$APP_BRANCH" ]; then
                echo "  Branch: $APP_BRANCH"
                bench get-app --branch "$APP_BRANCH" "$APP_REPO"
            else
                bench get-app "$APP_REPO"
            fi
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
        echo "Site '$SITE_NAME' already exists. Checking database..."
        ensure_site_db_access "$SITE_NAME"
        if ! site_schema_ready "$SITE_NAME"; then
            echo "  Site database schema missing; recreating site..."
            site_db_name=$(get_site_db_name "$SITE_NAME")
            cleanup_site_db_user "$site_db_name"
            rm -rf "sites/$SITE_NAME"
            bench new-site "$SITE_NAME" \
                --admin-password "$ADMIN_PASSWORD" \
                --db-password "$DB_PASSWORD" \
                --db-root-password "$DB_ROOT_PASSWORD" \
                --db-host "$DB_HOST" \
                --db-port "$DB_PORT" \
                --no-mariadb-socket \
                --mariadb-user-host-login-scope "%" \
                --force
        fi
    else
        echo "Creating new site: $SITE_NAME"
        site_db_name=$(BENCH_DIR="$BENCH_DIR" compute_site_db_name "$SITE_NAME")
        cleanup_site_db_user "$site_db_name"
        bench new-site "$SITE_NAME" \
            --admin-password "$ADMIN_PASSWORD" \
            --db-password "$DB_PASSWORD" \
            --db-root-password "$DB_ROOT_PASSWORD" \
            --db-host "$DB_HOST" \
            --db-port "$DB_PORT" \
            --no-mariadb-socket \
            --mariadb-user-host-login-scope "%" \
            --force
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


echo "✅ Bench setup complete!"
echo
echo "To start the development server, run:"
echo "cd $BENCH_DIR && bench start"
