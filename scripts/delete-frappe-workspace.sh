#!/bin/bash
set -e

# Script metadata for version tracking
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="delete-workspace.sh"

# Source utility libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/git-project.sh"
source "${SCRIPT_DIR}/lib/ai-provider.sh"
source "${SCRIPT_DIR}/lib/ai-assistant.sh"

# Initialize AI assistant (optional)
init_ai_assistant

# Detect project context from current directory
log_section "Workspace Deleter"
detect_project_context || die "Failed to detect project context"
display_project_context

# Parse arguments
WORKSPACE_NAME="${1:-}"

if [ -z "$WORKSPACE_NAME" ]; then
    log_warn "No workspace name provided"
    
    # List available workspaces
    log_info "Available workspaces:"
    local -a workspaces
    mapfile -t workspaces < <(list_workspaces "$WORKSPACES_DIR") || {
        log_error "No workspaces found"
        exit 1
    }
    
    for ws in "${workspaces[@]}"; do
        log_info "  - $ws"
    done
    
    echo ""
    echo -ne "${YELLOW}Enter workspace name to delete: ${NC}"
    read -r WORKSPACE_NAME
    
    if [ -z "$WORKSPACE_NAME" ]; then
        log_error "Workspace name cannot be empty"
        exit 1
    fi
fi

WORKSPACE_DIR="${WORKSPACES_DIR}/${WORKSPACE_NAME}"

log_info "Configuration:"
log_info "  Workspace name: ${WORKSPACE_NAME}"
log_info "  Workspace directory: ${WORKSPACE_DIR}"
echo ""

# Validate workspace exists
if ! workspace_exists "$WORKSPACE_NAME" "$WORKSPACES_DIR"; then
    log_error "Workspace '${WORKSPACE_NAME}' does not exist"
    exit 1
fi

# Check if .devcontainer exists
if workspace_has_devcontainer "$WORKSPACE_DIR"; then
    log_success "Valid workspace structure found"
else
    log_warn "Workspace .devcontainer structure not fully valid, but directory exists"
fi

echo ""

# Validate with AI before proceeding
validate_workspace_operation "delete" "$WORKSPACE_NAME" "$PROJECT_TYPE"

# Confirm destructive operation with AI awareness
if ! confirm_destructive_operation "delete" "$WORKSPACE_DIR"; then
    log_info "Workspace deletion cancelled by user"
    exit 0
fi

# Perform deletion
log_subsection "[1/3] Stopping and removing containers...\n"

if [ -f "${WORKSPACE_DIR}/.devcontainer/docker-compose.yml" ]; then
    if command_exists docker-compose; then
        log_info "Stopping containers..."
        cd "$WORKSPACE_DIR"
        docker-compose down 2>/dev/null || log_warn "Failed to stop containers (they may already be stopped)"
        cd - >/dev/null
        log_success "Containers stopped"
    else
        log_warn "docker-compose not found, skipping container cleanup"
    fi
else
    log_info "No docker-compose.yml found, skipping container cleanup"
fi

log_subsection "[2/3] Backing up workspace data...\n"

# Create backup if there's significant data
WORKSPACE_SIZE=$(du -sh "$WORKSPACE_DIR" 2>/dev/null | cut -f1)

if [ -n "$WORKSPACE_SIZE" ]; then
    log_info "Workspace size: $WORKSPACE_SIZE"
    
    BACKUP_DIR="${WORKSPACES_DIR}/.backups/${WORKSPACE_NAME}-$(date +%Y%m%d-%H%M%S)"
    
    if [ -d "${WORKSPACE_DIR}/bench" ] && [ "$(find "${WORKSPACE_DIR}/bench" -type f | wc -l)" -gt 10 ]; then
        log_info "Creating backup of significant workspace data..."
        mkdir -p "$BACKUP_DIR"
        cp -r "${WORKSPACE_DIR}/bench" "$BACKUP_DIR/" 2>/dev/null || true
        log_success "Backup created at: ${BACKUP_DIR}"
    else
        log_info "Workspace data is minimal, skipping backup"
    fi
fi

log_subsection "[3/3] Deleting workspace directory...\n"

if rm -rf "$WORKSPACE_DIR"; then
    log_success "Workspace directory deleted"
else
    log_error "Failed to delete workspace directory"
    exit 1
fi

log_section "Workspace Deleted!"
log_info "Deleted workspace: ${WORKSPACE_NAME}"
echo ""
log_info "Next Steps:"
log_info "  1. Verify deletion: ls -la ${WORKSPACES_DIR}"
log_info "  2. If containers are stuck, run: docker ps"
log_info "  3. Create new workspace with: scripts/new-workspace.sh ${WORKSPACE_NAME}"
echo ""

# Report success to AI if available
report_success_to_ai "delete" "$WORKSPACE_NAME"
