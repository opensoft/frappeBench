#!/bin/bash
# Git project detection and validation utility
# Version: 1.0.0

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Find git root directory by walking up from current directory
find_git_root() {
    local current_dir="$(pwd)"
    
    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/.git" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    return 1
}

# Validate that a directory is a git repository
is_git_repo() {
    local dir="${1:-.}"
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1
}

# Get git remote URL
get_git_remote() {
    local dir="${1:-.}"
    git -C "$dir" config --get remote.origin.url 2>/dev/null || echo ""
}

# Get git branch name
get_git_branch() {
    local dir="${1:-.}"
    git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

# Check if directory is a Frappe project by looking for markers
is_frappe_project() {
    local dir="$1"
    
    # Check for common Frappe/Bench markers
    if [ -d "$dir/.git" ] && [ -f "$dir/setup.py" ] || [ -f "$dir/setup.cfg" ]; then
        if grep -q -i "frappe\|bench" "$dir/setup.py" 2>/dev/null || \
           grep -q -i "frappe\|bench" "$dir/setup.cfg" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Check for frappe config files
    if [ -f "$dir/frappe/app.py" ] || [ -f "$dir/frappe/__init__.py" ]; then
        return 0
    fi
    
    # Check for bench structure
    if [ -d "$dir/apps" ] && [ -d "$dir/sites" ]; then
        return 0
    fi
    
    # Check for pyproject.toml with frappe
    if [ -f "$dir/pyproject.toml" ] && grep -q -i "frappe" "$dir/pyproject.toml" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Identify project type (dartwing, frappe, etc.)
get_project_type() {
    local git_root="$1"
    local remote_url=$(get_git_remote "$git_root")
    
    # Check remote URL for project identification
    if echo "$remote_url" | grep -q "dartwing"; then
        echo "dartwing"
    elif echo "$remote_url" | grep -q "frappe"; then
        echo "frappe"
    else
        # Try to identify from directory structure
        if [ -d "$git_root/apps/dartwing" ]; then
            echo "dartwing"
        elif [ -d "$git_root/apps" ]; then
            echo "frappe"
        else
            echo "unknown"
        fi
    fi
}

# Check if workspaces directory structure is valid
is_valid_workspace_structure() {
    local git_root="$1"
    
    # Must have .devcontainer.example
    if [ ! -d "$git_root/devcontainer.example" ]; then
        log_warn "devcontainer.example not found in git root"
        return 1
    fi
    
    # Should have scripts directory
    if [ ! -d "$git_root/scripts" ]; then
        log_warn "scripts directory not found in git root"
        return 1
    fi
    
    return 0
}

# Get or create workspaces directory
get_workspaces_dir() {
    local git_root="$1"
    local workspaces_dir="${git_root}/workspaces"
    
    # Create if doesn't exist
    if [ ! -d "$workspaces_dir" ]; then
        mkdir -p "$workspaces_dir"
    fi
    
    echo "$workspaces_dir"
}

# Detect git root and validate project context
detect_project_context() {
    # Find git root from current directory
    local git_root
    git_root=$(find_git_root) || \
        die "Not in a git repository. Cannot determine project root."
    
    # Validate it's a Frappe project
    if ! is_frappe_project "$git_root"; then
        die "Not in a Frappe project. Expected to find Frappe markers in $git_root"
    fi
    
    # Validate workspace structure exists
    if ! is_valid_workspace_structure "$git_root"; then
        die "Invalid workspace structure. This doesn't appear to be a supported project with devcontainer setup."
    fi
    
    # Get project details
    local project_type=$(get_project_type "$git_root")
    local branch=$(get_git_branch "$git_root")
    local remote=$(get_git_remote "$git_root")
    
    # Export variables for use by calling script
    export GIT_ROOT="$git_root"
    export PROJECT_TYPE="$project_type"
    export CURRENT_BRANCH="$branch"
    export REMOTE_URL="$remote"
    export WORKSPACES_DIR=$(get_workspaces_dir "$git_root")
    
    return 0
}

# Display project context information
display_project_context() {
    log_info "Project Context:"
    log_info "  Root: ${GIT_ROOT}"
    log_info "  Type: ${PROJECT_TYPE}"
    log_info "  Branch: ${CURRENT_BRANCH}"
    log_info "  Remote: ${REMOTE_URL}"
    log_info "  Workspaces: ${WORKSPACES_DIR}"
}

# List existing workspaces
list_workspaces() {
    local workspaces_dir="${1:-.}"
    local -a workspaces
    
    if [ ! -d "$workspaces_dir" ]; then
        return 1
    fi
    
    for dir in "$workspaces_dir"/*; do
        if [ -d "$dir" ]; then
            workspaces+=("$(basename "$dir")")
        fi
    done
    
    if [ ${#workspaces[@]} -gt 0 ]; then
        printf '%s\n' "${workspaces[@]}"
    else
        return 1
    fi
}

# Get specific workspace directory
get_workspace_dir() {
    local workspace_name="$1"
    local workspaces_dir="${2:-.}"
    
    echo "${workspaces_dir}/${workspace_name}"
}

# Check if workspace exists
workspace_exists() {
    local workspace_name="$1"
    local workspaces_dir="${2:-.}"
    
    local workspace_dir=$(get_workspace_dir "$workspace_name" "$workspaces_dir")
    [ -d "$workspace_dir" ]
}

# Verify workspace has valid .devcontainer
workspace_has_devcontainer() {
    local workspace_dir="$1"
    
    [ -d "$workspace_dir/.devcontainer" ] && \
    [ -f "$workspace_dir/.devcontainer/Dockerfile" ] && \
    [ -f "$workspace_dir/.devcontainer/devcontainer.json" ]
}
