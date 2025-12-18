#!/bin/bash
# AI provider detection and credential management utility
# Version: 1.0.0

# Source common functions (guard against re-sourcing)
if [ -z "$_AI_PROVIDER_SOURCED" ]; then
    _AI_PROVIDER_SOURCED=1
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/common.sh"
fi

# List of credential locations to check for each provider
declare -A PROVIDER_CREDENTIALS=(
    ["codex"]="~/.codex ~/.config/codex"
    ["claude"]="~/.anthropic ~/.config/anthropic"
    ["openai"]="~/.openai ~/.config/openai"
)

# Provider API endpoints
declare -A PROVIDER_ENDPOINTS=(
    ["codex"]="https://api.github.com"
    ["claude"]="https://api.anthropic.com"
    ["openai"]="https://api.openai.com"
)

# Find credentials file for a provider
find_provider_credentials() {
    local provider="$1"
    local cred_locations="${PROVIDER_CREDENTIALS[$provider]}"
    
    if [ -z "$cred_locations" ]; then
        return 1
    fi
    
    for location in $cred_locations; do
        location="${location/#\~/$HOME}"
        
        # Check for various credential file formats
        for filename in "credentials" "credentials.json" ".env" "config" "config.json"; do
            local filepath="${location}/${filename}"
            if [ -f "$filepath" ]; then
                echo "$filepath"
                return 0
            fi
        done
        
        # Check if directory itself exists with hidden file
        if [ -d "$location" ]; then
            # Look for any non-directory files
            if [ -n "$(find "$location" -maxdepth 1 -type f 2>/dev/null | head -1)" ]; then
                echo "$location"
                return 0
            fi
        fi
    done
    
    return 1
}

# Extract API key from credentials
extract_api_key() {
    local filepath="$1"
    local provider="$2"
    
    if [ ! -f "$filepath" ]; then
        return 1
    fi
    
    local api_key=""
    
    # Try to extract from common formats
    # JSON format
    api_key=$(grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$filepath" 2>/dev/null | cut -d'"' -f4)
    [ -n "$api_key" ] && echo "$api_key" && return 0
    
    api_key=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$filepath" 2>/dev/null | cut -d'"' -f4)
    [ -n "$api_key" ] && echo "$api_key" && return 0
    
    # Environment variable format
    api_key=$(grep "API_KEY=" "$filepath" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    [ -n "$api_key" ] && echo "$api_key" && return 0
    
    api_key=$(grep "TOKEN=" "$filepath" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    [ -n "$api_key" ] && echo "$api_key" && return 0
    
    # For directory, try to find any token file
    if [ -d "$filepath" ]; then
        api_key=$(find "$filepath" -maxdepth 1 -type f -exec grep -h "." {} \; 2>/dev/null | head -1 | tr -d '\n' | tr -d '"' | tr -d "'")
        [ -n "$api_key" ] && echo "$api_key" && return 0
    fi
    
    return 1
}

# Check if provider has valid credentials
check_provider_available() {
    local provider="$1"
    local cred_file
    
    cred_file=$(find_provider_credentials "$provider") || return 1
    
    # Verify we can extract API key
    if extract_api_key "$cred_file" "$provider" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Get available providers in priority order
get_available_providers() {
    local -a available
    local priority_order=("codex" "claude" "openai")
    
    for provider in "${priority_order[@]}"; do
        if check_provider_available "$provider"; then
            available+=("$provider")
        fi
    done
    
    if [ ${#available[@]} -gt 0 ]; then
        printf '%s\n' "${available[@]}"
    else
        return 1
    fi
}

# Get primary available provider (first in priority)
get_primary_provider() {
    local provider
    provider=$(get_available_providers | head -1) || return 1
    echo "$provider"
}

# Get API key for provider
get_provider_api_key() {
    local provider="$1"
    local cred_file
    
    cred_file=$(find_provider_credentials "$provider") || {
        log_error "No credentials found for $provider"
        return 1
    }
    
    extract_api_key "$cred_file" "$provider" || {
        log_error "Could not extract API key from $cred_file"
        return 1
    }
}

# Make API call to provider
call_provider_api() {
    local provider="$1"
    local endpoint="$2"
    local method="${3:-POST}"
    local data="$4"
    
    local api_key
    api_key=$(get_provider_api_key "$provider") || return 1
    
    local headers=("-H" "Content-Type: application/json")
    
    case "$provider" in
        codex)
            headers+=("-H" "Authorization: token $api_key")
            ;;
        claude)
            headers+=("-H" "x-api-key: $api_key")
            headers+=("-H" "anthropic-version: 2023-06-01")
            ;;
        openai)
            headers+=("-H" "Authorization: Bearer $api_key")
            ;;
    esac
    
    local curl_args=("-s" "-X" "$method")
    curl_args+=("${headers[@]}")
    
    if [ -n "$data" ]; then
        curl_args+=("-d" "$data")
    fi
    
    curl_args+=("${PROVIDER_ENDPOINTS[$provider]}${endpoint}")
    
    curl "${curl_args[@]}"
}

# Validate provider is working
validate_provider() {
    local provider="$1"
    
    log_subsection "Validating $provider provider..."
    
    case "$provider" in
        codex)
            # Try to get GitHub user info
            if call_provider_api "$provider" "/user" "GET" >/dev/null 2>&1; then
                log_success "$provider provider is valid"
                return 0
            fi
            ;;
        claude)
            # Check API key format is valid
            if [ -n "$(get_provider_api_key "$provider")" ]; then
                log_success "$provider provider is configured"
                return 0
            fi
            ;;
        openai)
            # Check API key format is valid
            if [ -n "$(get_provider_api_key "$provider")" ]; then
                log_success "$provider provider is configured"
                return 0
            fi
            ;;
    esac
    
    log_warn "$provider provider validation failed"
    return 1
}

# Display available providers
show_available_providers() {
    local -a providers
    mapfile -t providers < <(get_available_providers)
    
    if [ ${#providers[@]} -eq 0 ]; then
        log_warn "No AI providers configured"
        log_info "Supported providers:"
        log_info "  - Codex (GitHub): ~.codex, ~/.config/codex"
        log_info "  - Claude (Anthropic): ~/.anthropic, ~/.config/anthropic"
        log_info "  - OpenAI: ~/.openai, ~/.config/openai"
        return 1
    fi
    
    log_info "Available AI providers:"
    for provider in "${providers[@]}"; do
        log_info "  - ${provider} (primary)"
    done
    
    return 0
}

# Initialize AI provider support
init_ai_provider() {
    local provider
    provider=$(get_primary_provider) || {
        log_warn "No AI providers available - operating in degraded mode"
        export AI_PROVIDER=""
        return 0
    }
    
    export AI_PROVIDER="$provider"
    log_success "Using $provider as AI provider"
    return 0
}
