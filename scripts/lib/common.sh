#!/bin/bash
# Common utility functions for all scripts
# Version: 1.0.0

# Guard against re-sourcing
if [ -n "$_COMMON_SOURCED" ]; then
    return 0
fi
_COMMON_SOURCED=1

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "$*"
    echo -e "==========================================${NC}"
    echo ""
}

log_subsection() {
    echo -e "${BLUE}[*]${NC} $*"
}

# Error handling
die() {
    log_error "$*"
    exit 1
}

# Confirm action
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [ "$default" = "y" ]; then
        echo -ne "${YELLOW}${prompt}${NC} [Y/n]: "
    else
        echo -ne "${YELLOW}${prompt}${NC} [y/N]: "
    fi
    
    read -r response
    
    if [ -z "$response" ]; then
        response="$default"
    fi
    
    case "$response" in
        [yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get absolute path
get_absolute_path() {
    local path="$1"
    if [ -d "$path" ]; then
        (cd "$path" && pwd)
    else
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi
}

# Validate directory exists
validate_directory() {
    local dir="$1"
    local desc="${2:-Directory}"
    
    if [ ! -d "$dir" ]; then
        log_error "${desc} not found: ${dir}"
        return 1
    fi
    return 0
}

# Validate file exists
validate_file() {
    local file="$1"
    local desc="${2:-File}"
    
    if [ ! -f "$file" ]; then
        log_error "${desc} not found: ${file}"
        return 1
    fi
    return 0
}

# Get file size in bytes
get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Retry function with exponential backoff
retry() {
    local max_attempts=3
    local timeout=1
    local attempt=1
    local exit_code=0
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        else
            exit_code=$?
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Attempt $attempt/$max_attempts failed. Retrying in ${timeout}s..."
            sleep "$timeout"
            timeout=$((timeout * 2))
        fi
        
        attempt=$((attempt + 1))
    done
    
    return $exit_code
}

# Pretty print JSON (fallback to cat if jq not available)
pretty_json() {
    if command_exists jq; then
        jq . 2>/dev/null || cat
    else
        cat
    fi
}

# Spinner for long-running operations
show_spinner() {
    local pid=$1
    local task="${2:-Processing}"
    local chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        echo -ne "${CYAN}${chars[$i]}${NC} ${task}\r"
        i=$((($i + 1) % ${#chars[@]}))
        sleep 0.1
    done
    
    wait $pid
    local exit_code=$?
    echo -ne "\r"
    return $exit_code
}
