#!/bin/bash
set -e

# Script metadata for version tracking
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="update-workspace.sh"

# Source utility libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/git-project.sh"
source "${SCRIPT_DIR}/lib/ai-provider.sh"
source "${SCRIPT_DIR}/lib/ai-assistant.sh"

# Initialize AI assistant (optional)
init_ai_assistant

# Detect project context from current directory
log_section "Workspace Updater"
detect_project_context || die "Failed to detect project context"
display_project_context

# Parse arguments
TARGET="${1:--all}"

# Function to update a single workspace
update_single_workspace() {
    local workspace_name="$1"
    local workspace_dir="${WORKSPACES_DIR}/${workspace_name}"
    
    # Validate workspace exists
    if [ ! -d "$workspace_dir" ]; then
        log_error "Workspace directory ${workspace_dir} not found!"
        return 1
    fi
    
    # Validate .devcontainer exists (it should, but check anyway)
    if [ ! -d "${workspace_dir}/.devcontainer" ]; then
        log_error ".devcontainer directory not found in ${workspace_dir}!"
        return 1
    fi
    
    log_info "Updating workspace: ${workspace_name}"
    
    # Validate with AI before proceeding
    validate_workspace_operation "update" "$workspace_name" "$PROJECT_TYPE"
    
    # Step 1: Backup current .env if it exists (preserve custom settings)
    if [ -f "${workspace_dir}/.devcontainer/.env" ]; then
        cp "${workspace_dir}/.devcontainer/.env" "${workspace_dir}/.devcontainer/.env.backup"
        log_success ".env backed up to .env.backup"
    fi
    
    # Step 2: Copy updated devcontainer files from example (preserves .env and .env.backup)
    log_subsection "[1/3] Updating devcontainer configuration..."
    
    # Copy all files except .env (which we want to preserve)
    for file in "${GIT_ROOT}/devcontainer.example"/*; do
        filename=$(basename "$file")
        # Skip .env files as we preserve those
        if [[ "$filename" != ".env" ]]; then
            if [ -d "$file" ]; then
                # For directories, remove old and copy new
                rm -rf "${workspace_dir}/.devcontainer/${filename}"
                cp -r "$file" "${workspace_dir}/.devcontainer/${filename}"
            else
                # For files, just copy
                cp "$file" "${workspace_dir}/.devcontainer/${filename}"
            fi
        fi
    done
    log_success "Devcontainer files updated"
    
    # Step 2.5: Ensure all script symlinks are present
    log_subsection "[2/3] Updating workspace script symlinks..."
    
    # Ensure scripts directory exists
    mkdir -p "${workspace_dir}/scripts"
    
    # Required script symlinks
    declare -a required_scripts=(
        "setup-frappe.sh"
        "setup_stack.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        symlink_path="${workspace_dir}/scripts/${script}"
        target_path="/repo/scripts/${script}"
        
        # Remove old symlink or file if exists
        if [ -e "$symlink_path" ] || [ -L "$symlink_path" ]; then
            rm -f "$symlink_path"
        fi
        
        # Create new symlink
        ln -s "$target_path" "$symlink_path"
    done
    
    log_success "Script symlinks updated"
    
    # Step 3: Preserve and reapply .env settings
    log_subsection "[3/4] Preserving workspace environment configuration..."
    
    if [ -f "${workspace_dir}/.devcontainer/.env.backup" ]; then
        # Extract workspace details from existing .env
        existing_project_name=$(grep "^PROJECT_NAME=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_codename=$(grep "^CODENAME=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_workspace=$(grep "^WORKSPACE_NAME=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_compose=$(grep "^COMPOSE_PROJECT_NAME=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_port=$(grep "^HOST_PORT=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_nginx_port=$(grep "^NGINX_HOST_PORT=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_user=$(grep "^USER=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_uid=$(grep "^UID=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_gid=$(grep "^GID=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_site=$(grep "^SITE_NAME=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_memory=$(grep "^CONTAINER_MEMORY=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)
        existing_cpus=$(grep "^CONTAINER_CPUS=" "${workspace_dir}/.devcontainer/.env.backup" | cut -d= -f2)

        if [ -z "$existing_workspace" ]; then
            existing_workspace="$existing_codename"
        fi
        if [ -z "$existing_compose" ] && [ -n "$existing_workspace" ]; then
            existing_compose="frappe-${existing_workspace}"
        fi
        if [[ "$existing_compose" == frappeworkspace-* ]]; then
            existing_compose="frappe-${existing_compose#frappeworkspace-}"
        fi
        if [[ "$existing_compose" == frappebench-* ]]; then
            existing_compose="frappe-${existing_compose#frappebench-}"
        fi
        if [ -z "$existing_project_name" ]; then
            existing_project_name="$PROJECT_NAME"
        fi
        if [ -z "$existing_port" ]; then
            existing_port="8201"
        fi
        if [ -z "$existing_nginx_port" ]; then
            existing_nginx_port="8081"
        fi
        if [ -z "$existing_memory" ]; then
            existing_memory="4g"
        fi
        if [ -z "$existing_cpus" ]; then
            existing_cpus="2"
        fi
        
        # Recreate .env with existing settings
        cat > "${workspace_dir}/.devcontainer/.env" << EOF
# Project Configuration
PROJECT_NAME=${existing_project_name}
COMPOSE_PROJECT_NAME=${existing_compose}

# Workspace: ${existing_workspace}
WORKSPACE_NAME=${existing_workspace}
CODENAME=${existing_codename}
HOST_PORT=${existing_port}
NGINX_HOST_PORT=${existing_nginx_port}

# User configuration
USER=${existing_user}
UID=${existing_uid}
GID=${existing_gid}

# Database configuration (uses shared frappe-infra stack)
DB_HOST=frappe-mariadb
DB_PORT=3306
DB_PASSWORD=frappe

# Redis configuration (uses shared frappe-infra stack)
REDIS_CACHE=frappe-redis-cache:6379
REDIS_QUEUE=frappe-redis-queue:6379
REDIS_SOCKETIO=frappe-redis-socketio:6379

# Frappe site configuration
SITE_NAME=${existing_site}
ADMIN_PASSWORD=admin

# App configuration
APP_BRANCH=main

# Bench configuration
FRAPPE_BENCH_PATH=/workspace/bench
BENCH_DISABLE_UV=0

# Resource Limits
CONTAINER_MEMORY=${existing_memory}
CONTAINER_CPUS=${existing_cpus}
EOF
        log_success "Environment configuration preserved"
        
        # Clean up backup
        rm "${workspace_dir}/.devcontainer/.env.backup"
    fi
    
    # Step 4: Update devcontainer.json name with workspace name
    log_subsection "[4/4] Customizing devcontainer settings..."
    if [ -f "${workspace_dir}/.devcontainer/devcontainer.json" ]; then
        sed -i "s/WORKSPACE_NAME/${workspace_name}/g" "${workspace_dir}/.devcontainer/devcontainer.json"
        log_success "Devcontainer name updated"
    fi
    
    log_success "Workspace ${workspace_name} updated successfully"
    echo ""
    return 0
}

# Main logic
if [ "$TARGET" = "-all" ]; then
    # Update all workspaces
    log_info "Configuration:"
    log_info "  Target: all workspaces"
    echo ""
    
    if [ ! -d "$WORKSPACES_DIR" ] || [ -z "$(ls -A "$WORKSPACES_DIR" 2>/dev/null)" ]; then
        log_error "No workspaces found in ${WORKSPACES_DIR}!"
        exit 1
    fi
    
    failed_count=0
    success_count=0
    
    for workspace_dir in "${WORKSPACES_DIR}"/*; do
        if [ -d "$workspace_dir" ]; then
            workspace_name=$(basename "$workspace_dir")
            if update_single_workspace "$workspace_name"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        fi
    done
    
    log_section "Update Complete!"
    log_info "Results:"
    log_success "Successful: ${success_count}"
    if [ $failed_count -gt 0 ]; then
        log_error "Failed: ${failed_count}"
        exit 1
    fi
else
    # Update specific workspace
    log_info "Configuration:"
    log_info "  Target: ${TARGET}"
    echo ""
    
    if update_single_workspace "$TARGET"; then
        log_section "Workspace Updated!"
        log_info "Workspace Details:"
        log_info "  Name: ${TARGET}"
        log_info "  Location: ${WORKSPACES_DIR}/${TARGET}"
        echo ""
        log_info "Next Steps:"
        log_info "  1. Rebuild the container: docker-compose rebuild"
        log_info "  2. Reopen in container in VSCode"
        echo ""
        report_success_to_ai "update" "$TARGET"
    else
        exit 1
    fi
fi
