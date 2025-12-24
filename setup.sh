#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "Frappe Bench - Initial Setup"
echo -e "==========================================${NC}"
echo ""
echo -e "This script will set up the workspace environment"
echo -e "with devcontainer configuration and templates."
echo ""

# Get script directory (script is now in project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${PROJECT_ROOT}/scripts"

# Step 1: Check prerequisites
echo -e "${BLUE}[1/3] Checking prerequisites...${NC}"

# Check if devcontainer.example exists
if [ ! -d "${PROJECT_ROOT}/devcontainer.example" ]; then
    echo -e "${RED}  ✗ devcontainer.example folder not found!${NC}"
    echo -e "${YELLOW}  This template is needed to create workspaces.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ devcontainer.example found${NC}"

# Check if new-frappe-workspace.sh exists
if [ ! -f "${SCRIPT_DIR}/new-frappe-workspace.sh" ]; then
    echo -e "${RED}  ✗ new-frappe-workspace.sh script not found!${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ new-frappe-workspace.sh found${NC}"

# Check if delete-frappe-workspace.sh exists
if [ ! -f "${SCRIPT_DIR}/delete-frappe-workspace.sh" ]; then
    echo -e "${RED}  ✗ delete-frappe-workspace.sh script not found!${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ delete-frappe-workspace.sh found${NC}"
echo ""

# Step 2: Ensure workspaces folder exists and check existing workspaces
echo -e "${BLUE}[2/3] Checking workspaces directory...${NC}"
if [ ! -d "${PROJECT_ROOT}/workspaces" ]; then
    mkdir -p "${PROJECT_ROOT}/workspaces"
    echo -e "${GREEN}  ✓ Created workspaces directory${NC}"
else
    echo -e "${YELLOW}  → workspaces directory already exists${NC}"
    
    # Get current template version (if it exists in .devcontainer)
    CURRENT_TEMPLATE_VERSION=""
    if [ -f "${PROJECT_ROOT}/.devcontainer/README.md" ]; then
        CURRENT_TEMPLATE_VERSION=$(grep 'Current Version:' "${PROJECT_ROOT}/.devcontainer/README.md" 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "")
    elif [ -f "${PROJECT_ROOT}/devcontainer.example/README.md" ]; then
        CURRENT_TEMPLATE_VERSION=$(grep 'Current Version:' "${PROJECT_ROOT}/devcontainer.example/README.md" 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "")
    fi
    
    # Check existing workspaces
    WORKSPACES_FOUND=false
    WORKSPACES_TO_UPDATE=()
    
    for workspace_dir in "${PROJECT_ROOT}/workspaces"/*; do
        if [ -d "$workspace_dir" ]; then
            WORKSPACES_FOUND=true
            workspace_name=$(basename "$workspace_dir")
            
            echo -e "\n${BLUE}  Checking workspace: ${workspace_name}${NC}"
            
            # Check devcontainer version
            WORKSPACE_VERSION="unknown"
            if [ -f "${workspace_dir}/.devcontainer/README.md" ]; then
                WORKSPACE_VERSION=$(grep 'Current Version:' "${workspace_dir}/.devcontainer/README.md" 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
            fi
            
            if [ -n "$CURRENT_TEMPLATE_VERSION" ] && [ "$WORKSPACE_VERSION" = "$CURRENT_TEMPLATE_VERSION" ]; then
                echo -e "    ${GREEN}✓ Devcontainer version: ${WORKSPACE_VERSION} (up to date)${NC}"
            elif [ -n "$CURRENT_TEMPLATE_VERSION" ]; then
                echo -e "    ${YELLOW}⚠ Devcontainer version: ${WORKSPACE_VERSION} (latest: ${CURRENT_TEMPLATE_VERSION})${NC}"
                WORKSPACES_TO_UPDATE+=("$workspace_name")
            else
                echo -e "    ${YELLOW}⚠ Devcontainer version: ${WORKSPACE_VERSION}${NC}"
            fi
        fi
    done
    
    # Ask to update workspaces if needed
    if [ ${#WORKSPACES_TO_UPDATE[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}The following workspaces have outdated devcontainer templates:${NC}"
        for ws in "${WORKSPACES_TO_UPDATE[@]}"; do
            echo -e "  - $ws"
        done
        echo -e "\n${YELLOW}Update these workspaces to version ${CURRENT_TEMPLATE_VERSION}?${NC}"
        echo -e "${YELLOW}This will backup and replace devcontainer files.${NC}"
        read -p "Update workspaces? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for ws in "${WORKSPACES_TO_UPDATE[@]}"; do
                echo -e "\n${BLUE}Updating workspace: ${ws}${NC}"
                
                # Backup current devcontainer
                BACKUP_DIR="${PROJECT_ROOT}/workspaces/${ws}/.devcontainer.backup.$(date +%Y%m%d-%H%M%S)"
                cp -r "${PROJECT_ROOT}/workspaces/${ws}/.devcontainer" "$BACKUP_DIR"
                echo -e "  ${GREEN}✓ Backup created: $(basename "$BACKUP_DIR")${NC}"
                
                # Copy new template (except .env to preserve workspace-specific settings)
                rm -rf "${PROJECT_ROOT}/workspaces/${ws}/.devcontainer"
                cp -r "${PROJECT_ROOT}/devcontainer.example" "${PROJECT_ROOT}/workspaces/${ws}/.devcontainer"
                
                # Restore .env from backup
                if [ -f "${BACKUP_DIR}/.env" ]; then
                    cp "${BACKUP_DIR}/.env" "${PROJECT_ROOT}/workspaces/${ws}/.devcontainer/.env"
                    echo -e "  ${GREEN}✓ Preserved workspace .env settings${NC}"
                fi
                
                echo -e "  ${GREEN}✓ Updated to version ${CURRENT_TEMPLATE_VERSION}${NC}"
            done
            echo -e "\n${GREEN}All workspaces updated!${NC}"
        else
            echo -e "${YELLOW}Skipping workspace updates${NC}"
        fi
    fi
fi
echo ""

# Step 3: Create alpha workspace if it doesn't exist
echo -e "${BLUE}[3/3] Checking default workspace...${NC}"
if [ ! -d "${PROJECT_ROOT}/workspaces/alpha" ] || [ ! -d "${PROJECT_ROOT}/workspaces/alpha/.devcontainer" ]; then
    if [ -d "${PROJECT_ROOT}/workspaces/alpha" ]; then
        echo -e "${YELLOW}  → Incomplete alpha workspace found, recreating...${NC}"
        rm -rf "${PROJECT_ROOT}/workspaces/alpha"
    fi
    
    echo -e "${YELLOW}  → Creating alpha workspace...${NC}"
    cd "${PROJECT_ROOT}"
    "${SCRIPT_DIR}/new-frappe-workspace.sh" alpha
    echo -e "${GREEN}  ✓ Alpha workspace created${NC}"
else
    echo -e "${YELLOW}  → Alpha workspace already exists${NC}"
fi
echo ""

echo -e "${GREEN}=========================================="
echo "Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo -e "Workspace created at: ${BLUE}workspaces/alpha${NC}"
echo ""
echo -e "Next Steps:"
echo -e "  1. ${YELLOW}cd workspaces/alpha${NC}"
echo -e "  2. ${YELLOW}code .${NC} (open workspace in VSCode)"
echo -e "  3. Click ${YELLOW}'Reopen in Container'${NC} when prompted"
echo -e "  4. Wait for automatic Frappe initialization"
echo ""
echo -e "To create additional workspaces:"
echo -e "  ${YELLOW}./scripts/new-frappe-workspace.sh bravo${NC}"
echo -e "  ${YELLOW}./scripts/new-frappe-workspace.sh charlie${NC}"
echo ""
