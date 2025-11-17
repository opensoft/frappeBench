#!/bin/bash
set -e

# Load environment variables (excluding read-only vars)
if [ -f .devcontainer/.env ]; then
    set -a
    source <(grep -v '^#' .devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')
    set +a
fi

FRAPPE_SITE_NAME=${FRAPPE_SITE_NAME:-site1.localhost}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DB_HOST=${DB_HOST:-mariadb}
DB_PASSWORD=${DB_PASSWORD:-frappe}
BENCH_DIR="/workspace/development/frappe-bench"

echo "========================================"
echo "🚀 Frappe Setup Starting..."
echo "========================================"
echo ""

# Check if bench is properly initialized
if [ -f "$BENCH_DIR/env/bin/python" ] && [ -d "$BENCH_DIR/apps/frappe" ]; then
    echo "✅ Frappe Bench already initialized (skipping)"
    cd "$BENCH_DIR"
else
    echo "⏱️  First-time setup will take 5-10 minutes"
    echo "📦 Downloading Frappe framework and dependencies..."
    echo ""
    echo "[1/4] Initializing Frappe Bench..."
    
    cd /workspace/development
    
    # If bench directory exists but is incomplete, remove it
    if [ -d "frappe-bench" ]; then
        echo "Removing incomplete bench directory..."
        rm -rf frappe-bench
    fi
    
    bench init frappe-bench --frappe-branch version-15 --python python3.10 --skip-redis-config-generation --verbose
    cd "$BENCH_DIR"
    
    echo "✅ Bench initialization complete"
fi

# Ensure apps.txt exists in sites directory
if [ ! -f "$BENCH_DIR/sites/apps.txt" ]; then
    echo "Creating apps.txt..."
    echo "frappe" > "$BENCH_DIR/sites/apps.txt"
fi

# Check if site exists
echo ""
echo "[2/4] Creating Frappe site (this may take 2-3 minutes)..."
if [ ! -d "sites/$FRAPPE_SITE_NAME" ]; then
    bench new-site "$FRAPPE_SITE_NAME" \
        --mariadb-root-password "$DB_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --db-host "$DB_HOST" \
        --db-port 3306 \
        --verbose
    
    echo "✅ Site created successfully!"
else
    echo "✅ Site $FRAPPE_SITE_NAME already exists (skipping)"
fi

# Configure Redis (before bench use, as bench needs valid redis config)
echo ""
echo "[3/4] Configuring Redis connections..."
if [ -f "sites/common_site_config.json" ]; then
    python3 -c "
import json
config_file = 'sites/common_site_config.json'
with open(config_file, 'r') as f:
    config = json.load(f)
config['redis_cache'] = 'redis://redis-cache:6379'
config['redis_queue'] = 'redis://redis-queue:6379'
config['redis_socketio'] = 'redis://redis-socketio:6379'
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
"
    echo "✅ Redis configured"
fi

# Set current site
echo ""
echo "[4/4] Setting default site..."
bench use "$FRAPPE_SITE_NAME"
echo "✅ Default site set"

echo ""
echo "========================================"
echo "✅ Frappe setup completed successfully!"
echo "========================================"
echo "Bench directory: $BENCH_DIR"
echo "Site: $FRAPPE_SITE_NAME"
echo "Admin password: $ADMIN_PASSWORD"
echo ""
echo "To start Frappe, run: bench start"
echo ""
