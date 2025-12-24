#!/bin/bash
set -e

# Script metadata for version tracking
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="new-workspace.sh"

# Source utility libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/git-project.sh"
source "${SCRIPT_DIR}/lib/ai-provider.sh"
source "${SCRIPT_DIR}/lib/ai-assistant.sh"

# Configuration - project-specific repos will be detected
FRAPPE_REPO=""  # Will be detected from git remote
APP_REPO=""     # Will be detected based on project type

# NATO phonetic alphabet for workspace naming
NATO_ALPHABET=(alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu)

# Function to get next workspace name
get_next_workspace_name() {
    local project_root="$1"
    local workspaces_dir="${project_root}/workspaces"
    
    # If no workspaces exist, return first name
    if [ ! -d "$workspaces_dir" ] || [ -z "$(ls -A "$workspaces_dir" 2>/dev/null)" ]; then
        echo "${NATO_ALPHABET[0]}"
        return
    fi
    
    # Find all NATO phonetic workspace names
    local existing_workspaces=()
    for dir in "${workspaces_dir}"/*; do
        if [ -d "$dir" ]; then
            local basename=$(basename "$dir")
            # Check if it's a NATO phonetic name
            for nato_name in "${NATO_ALPHABET[@]}"; do
                if [ "$basename" = "$nato_name" ]; then
                    existing_workspaces+=("$basename")
                    break
                fi
            done
        fi
    done
    
    # Find the last NATO name in sequence
    local last_index=-1
    for i in "${!NATO_ALPHABET[@]}"; do
        local nato_name="${NATO_ALPHABET[$i]}"
        for existing in "${existing_workspaces[@]}"; do
            if [ "$existing" = "$nato_name" ]; then
                last_index=$i
            fi
        done
    done
    
    # Return next name in sequence
    local next_index=$((last_index + 1))
    if [ $next_index -lt ${#NATO_ALPHABET[@]} ]; then
        echo "${NATO_ALPHABET[$next_index]}"
    else
        echo -e "${RED}Error: All NATO phonetic names exhausted!${NC}" >&2
        return 1
    fi
}

# Initialize AI assistant (optional)
init_ai_assistant

# Detect project context from current directory
log_section "New Workspace Creator"
detect_project_context || die "Failed to detect project context"
display_project_context

# Parse arguments
WORKSPACE_NAME="${1:-}"

# If no workspace name provided, auto-detect next one
if [ -z "$WORKSPACE_NAME" ]; then
    WORKSPACE_NAME=$(get_next_workspace_name "$GIT_ROOT")
    if [ $? -ne 0 ]; then
        die "Failed to generate next workspace name"
    fi
    log_info "No workspace name provided, auto-detected next: ${WORKSPACE_NAME}"
    echo ""
fi

# App repository will be auto-detected or left empty
# Projects can define APP_REPO in their own scripts if needed
APP_REPO=""

NEW_DIR="${WORKSPACES_DIR}/${WORKSPACE_NAME}"

log_info "Configuration:"
log_info "  Workspace name: ${WORKSPACE_NAME}"
log_info "  New directory: ${NEW_DIR}"
echo ""

# Validate AI before proceeding
validate_workspace_operation "new" "$WORKSPACE_NAME" "$PROJECT_TYPE"

# Step 1: Create new workspace subdirectory
log_subsection "[1/4] Creating new workspace directory..."
if [ -d "$NEW_DIR" ]; then
    log_error "Directory ${NEW_DIR} already exists!"
    exit 1
fi

mkdir -p "${NEW_DIR}/bench/apps"
mkdir -p "${NEW_DIR}/scripts"
log_success "Workspace directory created"
echo ""

# Step 2: Copy devcontainer template
log_subsection "[2/4] Setting up devcontainer configuration..."
if [ ! -d "${GIT_ROOT}/devcontainer.example" ]; then
    log_error "devcontainer.example folder not found!"
    exit 1
fi

cp -r "${GIT_ROOT}/devcontainer.example" "${NEW_DIR}/.devcontainer"
log_success "Devcontainer template copied"

# Calculate unique port based on NATO alphabet index for sequential assignment
BASE_PORT=8201
# Find the index of workspace name in NATO alphabet
NATO_INDEX=-1
for i in "${!NATO_ALPHABET[@]}"; do
    if [ "${NATO_ALPHABET[$i]}" = "$WORKSPACE_NAME" ]; then
        NATO_INDEX=$i
        break
    fi
done

if [ $NATO_INDEX -eq -1 ]; then
    # Not a NATO name, fall back to hash-based port
    echo -e "${YELLOW}  → Custom workspace name, using hash-based port${NC}"
    PORT_OFFSET=$(echo -n "$WORKSPACE_NAME" | cksum | cut -d' ' -f1)
    HOST_PORT=$((BASE_PORT + (PORT_OFFSET % 50)))
else
    # Sequential port based on NATO index (alpha=8201, bravo=8202, etc.)
    HOST_PORT=$((BASE_PORT + NATO_INDEX))
fi

# Update .devcontainer/.env with workspace-specific settings
cat > "${NEW_DIR}/.devcontainer/.env" << EOF
# Workspace: ${WORKSPACE_NAME}
CODENAME=${WORKSPACE_NAME}
HOST_PORT=${HOST_PORT}

# User configuration
USER=${USER}
UID=${UID}
GID=${GID}

# Database configuration (uses existing frappe-mariadb container)
DB_HOST=frappe-mariadb
DB_PORT=3306
DB_PASSWORD=frappe

# Redis configuration (uses existing frappe redis containers)
REDIS_CACHE=frappe-redis-cache:6379
REDIS_QUEUE=frappe-redis-queue:6379
REDIS_SOCKETIO=frappe-redis-socketio:6379

# Frappe site configuration
SITE_NAME=${WORKSPACE_NAME}.localhost
ADMIN_PASSWORD=admin

# App configuration
APP_BRANCH=main

# Bench configuration
FRAPPE_BENCH_PATH=/workspace/bench
EOF
log_success "Devcontainer environment configured"
log_info "  Port: ${HOST_PORT}"
echo ""

# Step 3: Update devcontainer.json name
log_subsection "[3/4] Customizing devcontainer settings..."
sed -i "s/WORKSPACE_NAME/${WORKSPACE_NAME}/g" "${NEW_DIR}/.devcontainer/devcontainer.json"
log_success "Devcontainer name updated"
echo ""

# Step 4: Clone app repository (if configured)
log_subsection "[4/4] Setting up app repository..."
if [ -n "$APP_REPO" ]; then
    log_info "  Cloning from provided APP_REPO..."
    if git clone "$APP_REPO" "${NEW_DIR}/bench/apps/app"; then
        log_success "App repository cloned"
    else
        log_warn "Failed to clone app repository - you may need to clone manually"
    fi
else
    log_info "  No app repository configured - workspace ready for manual app setup"
fi
echo ""

log_section "New Workspace Created!"
log_info "Workspace Details:"
log_info "  Name: ${WORKSPACE_NAME}"
log_info "  Location: ${NEW_DIR}"
log_info "  Bench: ${NEW_DIR}/bench"
log_info "  Port: ${HOST_PORT}"
echo ""
log_info "Next Steps:"
log_info "  1. cd ${NEW_DIR}"
log_info "  2. code . (open workspace in VSCode)"
log_info "  3. Click 'Reopen in Container' when prompted"
log_info "  4. Access at: http://localhost:${HOST_PORT}"
echo ""

# Report success to AI if available
report_success_to_ai "create" "$WORKSPACE_NAME"
