#!/bin/bash
# Intelligent workspace creator - determines which workspace type to create
# Uses AI to understand what the user needs, then routes to appropriate script

set -e

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="new-workspace.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Log functions
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

die() {
    log_error "$*"
    exit 1
}

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo -e "${BLUE}=========================================="
echo "Workspace Creator (Intelligent Router v${SCRIPT_VERSION})"
echo -e "==========================================${NC}"
echo ""

# Check for AI support (source the AI provider library if available)
AI_AVAILABLE=false
if [ -f "${SCRIPT_DIR}/lib/ai-provider.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
    source "${SCRIPT_DIR}/lib/ai-provider.sh" 2>/dev/null || true
    
    if command -v get_primary_provider >/dev/null 2>&1; then
        provider=$(get_primary_provider 2>/dev/null) || true
        if [ -n "$provider" ]; then
            AI_AVAILABLE=true
            log_success "AI support available ($provider)"
        fi
    fi
fi

# If no arguments provided and AI is available, ask user what they need
if [ $# -eq 0 ] && [ "$AI_AVAILABLE" = true ]; then
    echo ""
    log_info "What type of workspace do you want to create?"
    echo ""
    echo "  1. Frappe (ERP framework)"
    echo "  2. Custom workspace"
    echo ""
    echo -ne "${YELLOW}Select workspace type [1-2]: ${NC}"
    read -r choice
    
    case "$choice" in
        1)
            WORKSPACE_TYPE="frappe"
            ;;
        2)
            echo -ne "${YELLOW}Enter custom workspace name (optional): ${NC}"
            read -r WORKSPACE_NAME
            if [ -n "$WORKSPACE_NAME" ]; then
                log_info "Custom workspace not yet supported"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
else
    # Try to determine workspace type from context or arguments
    WORKSPACE_TYPE="frappe"  # Default to frappe for now
    WORKSPACE_NAME="${1:-}"
fi

# Route to appropriate script
case "$WORKSPACE_TYPE" in
    frappe)
        log_info "Creating Frappe workspace..."
        
        if [ ! -f "${SCRIPT_DIR}/new-frappe-workspace.sh" ]; then
            die "Frappe workspace script not found: ${SCRIPT_DIR}/new-frappe-workspace.sh"
        fi
        
        # Pass through arguments to the specific script
        if [ -n "$WORKSPACE_NAME" ]; then
            exec "${SCRIPT_DIR}/new-frappe-workspace.sh" "$WORKSPACE_NAME"
        else
            exec "${SCRIPT_DIR}/new-frappe-workspace.sh"
        fi
        ;;
    *)
        die "Unknown workspace type: $WORKSPACE_TYPE"
        ;;
esac
