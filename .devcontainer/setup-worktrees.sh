#!/bin/bash
set -euo pipefail

# Setup script for git worktrees - runs on host during devcontainer initialization
# Requires frappe-apps.json to exist (can be empty array [])

CONFIG_FILE=".devcontainer/frappe-apps.json"
MODE="prepare" # Default mode for worktrees

# Detect if running on host vs in container
if [ ! -d "/workspace" ]; then
    # Running on host - /workspace maps to current directory
    WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export PATH_PREFIX="$WORKSPACE_ROOT"
else
    # Running in container - /workspace is the workspace
    export PATH_PREFIX=""
fi

if [[ $# -ge 1 ]]; then
    case "$1" in
        --prepare) MODE="prepare" ;;
        --install) MODE="install" ;;
    esac
fi

# Load env except UID/GID to avoid clobbering container user
if [ -f .devcontainer/.env ]; then
    set -a
    source <(grep -v '^#' .devcontainer/.env | grep -v '^UID=' | grep -v '^GID=')
    set +a
fi

log() {
    local level="$1"; shift
    echo "[setup-worktrees][$level] $*"
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

try:
    with open('.devcontainer/frappe-apps.json') as f:
        data = json.load(f)
except Exception as exc:
    print(f"[setup-worktrees][ERROR] Failed to parse frappe-apps.json: {exc}", file=sys.stderr)
    sys.exit(1)

DEFAULT_APP_BASE = "/workspace/development/frappe-bench/apps"

for item in data:
    if not isinstance(item, dict):
        continue
    app = (item.get("app") or "").strip()
    repo = (item.get("source") or "").strip()
    worktree = (item.get("target") or "").strip()
    branch = (item.get("branch") or "").strip()

    if not app or not repo:
        continue
    if not worktree:
        worktree = f"{DEFAULT_APP_BASE}/{app}"
    
    # Replace /workspace with actual path when running on host
    import os
    path_prefix = os.environ.get('PATH_PREFIX', '')
    if path_prefix and worktree.startswith('/workspace'):
        worktree = worktree.replace('/workspace', path_prefix, 1)

    print(json.dumps({
        "name": app,
        "repo": repo,
        "worktree": worktree,
        "branch": branch,
    }))
PY
}

ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
}

worktree_exists() {
    local repo="$1" path="$2"
    git -C "$repo" worktree list --porcelain | grep -q "^worktree $path$"
}

branch_in_use_elsewhere() {
    local repo="$1" branch="$2" path="$3"
    git -C "$repo" worktree list --porcelain | awk '
        $1=="worktree"{w=$2}
        $1=="branch"{b=$2; if (b=="refs/heads/'"$branch"'") {print w}}
    ' | grep -qv "^$path$"
}

ensure_worktree() {
    local name="$1" repo="$2" path="$3" branch="$4"

    if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log WARN "Repo root $repo for $name is not a git repo; skipping."
        return
    fi

    if branch_in_use_elsewhere "$repo" "$branch" "$path"; then
        log WARN "Branch $branch for $name already in use in another worktree; skipping add/switch."
        return
    fi

    if worktree_exists "$repo" "$path"; then
        current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ "$current_branch" != "$branch" ]]; then
            log INFO "Switching $name worktree at $path to $branch"
            git -C "$path" checkout "$branch" >/dev/null 2>&1 || log WARN "Failed to checkout $branch in $path"
        else
            log INFO "$name worktree present at $path on $branch"
        fi
        return
    fi

    if [ -e "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" != "" ]; then
        log WARN "Target path $path for $name is not empty and not a worktree; skipping."
        return
    fi

    ensure_dir "$(dirname "$path")"
    log INFO "Adding worktree for $name at $path (branch $branch)"
    git -C "$repo" worktree add "$path" "$branch" >/dev/null 2>&1 || log WARN "Failed to add worktree at $path"
}

main() {
    local entries
    mapfile -t entries < <(read_entries)

    if [[ ${#entries[@]} -eq 0 ]]; then
        log INFO "No apps configured in frappe-apps.json"
        exit 0
    fi

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
        repo=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj["repo"])
PY
)
        worktree=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj["worktree"])
PY
)
        branch=$(python3 - <<PY
import json,sys
with open('$temp_file') as f:
    obj=json.load(f)
print(obj["branch"])
PY
)
        rm -f "$temp_file"

        if [[ -n "$branch" ]]; then
            ensure_worktree "$name" "$repo" "$worktree" "$branch"
        else
            log INFO "No branch specified for $name; skipping worktree creation"
        fi
    done
}

main
