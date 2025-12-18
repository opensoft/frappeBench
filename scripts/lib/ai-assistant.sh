#!/bin/bash
# AI-powered assistant for workspace operations with graceful degradation
# Version: 1.0.0

# Source utility libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/ai-provider.sh"

# Check if AI is available
ai_available() {
    [ -n "$AI_PROVIDER" ] && [ "$AI_PROVIDER" != "" ]
}

# Build prompt for Claude API
build_claude_prompt() {
    local task="$1"
    local context="$2"
    
    cat <<EOF
You are a helpful assistant for managing Frappe development environments.
Your role is to provide brief, actionable guidance.

Task: $task

Context:
$context

Provide a concise response (1-2 sentences max). Be practical and specific.
EOF
}

# Build prompt for OpenAI API
build_openai_prompt() {
    local task="$1"
    local context="$2"
    
    cat <<EOF
Task: $task
Context: $context
Respond concisely (1-2 sentences). Be practical.
EOF
}

# Call Claude API for assistance
ask_claude() {
    local task="$1"
    local context="$2"
    local prompt
    
    prompt=$(build_claude_prompt "$task" "$context")
    
    local api_key
    api_key=$(get_provider_api_key "claude") || return 1
    
    local response
    response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "{
            \"model\": \"claude-3-5-sonnet-20241022\",
            \"max_tokens\": 200,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": \"$prompt\"
            }]
        }")
    
    echo "$response" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Call OpenAI API for assistance
ask_openai() {
    local task="$1"
    local context="$2"
    local prompt
    
    prompt=$(build_openai_prompt "$task" "$context")
    
    local api_key
    api_key=$(get_provider_api_key "openai") || return 1
    
    local response
    response=$(curl -s https://api.openai.com/v1/chat/completions \
        -H "Authorization: Bearer $api_key" \
        -H "content-type: application/json" \
        -d "{
            \"model\": \"gpt-4\",
            \"max_tokens\": 200,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": \"$prompt\"
            }]
        }")
    
    echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Generic AI assistance function
ask_ai() {
    local task="$1"
    local context="${2:-}"
    
    if ! ai_available; then
        return 1
    fi
    
    case "$AI_PROVIDER" in
        claude)
            ask_claude "$task" "$context"
            ;;
        openai)
            ask_openai "$task" "$context"
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate workspace operation with AI guidance
validate_workspace_operation() {
    local operation="$1"  # new, update, delete
    local workspace_name="$2"
    local project_type="$3"
    
    if ! ai_available; then
        log_info "Proceeding without AI validation"
        return 0
    fi
    
    log_subsection "Getting AI guidance on workspace ${operation} operation..."
    
    local context="Project: $project_type
Workspace: $workspace_name
Operation: $operation"
    
    local prompt="Review this Frappe workspace operation and briefly indicate if it's valid or if there are concerns:
$context"
    
    local guidance
    guidance=$(ask_ai "$prompt" "$context") 2>/dev/null || {
        log_warn "AI guidance unavailable, proceeding without validation"
        return 0
    }
    
    if [ -n "$guidance" ]; then
        log_info "AI Guidance: $guidance"
    fi
    
    return 0
}

# Get AI suggestion for workspace name
suggest_workspace_name() {
    local existing_workspaces="$1"
    local project_type="$2"
    
    if ! ai_available; then
        return 1
    fi
    
    log_subsection "Getting AI suggestion for workspace name..."
    
    local context="Project: $project_type
Existing workspaces: $existing_workspaces"
    
    local prompt="Suggest a short, meaningful workspace name (1-2 words) for a Frappe development environment.
Already used: $existing_workspaces
Suggest something different and memorable."
    
    local suggestion
    suggestion=$(ask_ai "$prompt" "$context") 2>/dev/null || return 1
    
    # Clean up suggestion (remove quotes, extra spaces)
    suggestion=$(echo "$suggestion" | tr -d '"' | xargs)
    
    if [ -n "$suggestion" ]; then
        log_info "AI Suggestion: $suggestion"
        echo "$suggestion"
        return 0
    fi
    
    return 1
}

# Get AI assistance with troubleshooting
troubleshoot_with_ai() {
    local error_message="$1"
    local operation="$2"
    
    if ! ai_available; then
        return 1
    fi
    
    log_subsection "Getting AI troubleshooting assistance..."
    
    local context="Operation: $operation
Error: $error_message"
    
    local prompt="Brief troubleshooting for Frappe workspace setup error.
Error: $error_message
Suggest 1-2 steps to resolve."
    
    local troubleshooting
    troubleshooting=$(ask_ai "$prompt" "$context") 2>/dev/null || {
        log_warn "AI troubleshooting unavailable"
        return 1
    }
    
    if [ -n "$troubleshooting" ]; then
        log_info "AI Troubleshooting Tips:"
        log_info "  $troubleshooting"
        return 0
    fi
    
    return 1
}

# Get configuration review from AI
review_configuration() {
    local config_json="$1"
    
    if ! ai_available; then
        return 1
    fi
    
    log_subsection "Getting AI review of configuration..."
    
    local prompt="Brief review of this devcontainer configuration for issues or improvements:
$config_json
Mention only critical issues (1 sentence max)."
    
    local review
    review=$(ask_ai "$prompt" "") 2>/dev/null || return 1
    
    if [ -n "$review" ]; then
        log_info "Configuration Review: $review"
        return 0
    fi
    
    return 1
}

# Confirm destructive operation with AI awareness
confirm_destructive_operation() {
    local operation="$1"
    local resource="$2"
    local ai_insight=""
    
    # Get AI insight if available
    if ai_available; then
        ai_insight=$(ask_ai "Briefly warn about consequences of deleting a Frappe workspace: $resource" "" 2>/dev/null) || true
    fi
    
    echo ""
    log_warn "WARNING: This will $operation: $resource"
    
    if [ -n "$ai_insight" ]; then
        log_info "  Note: $ai_insight"
    fi
    
    confirm "Do you want to proceed?" "n" || {
        log_info "Operation cancelled"
        return 1
    }
    
    return 0
}

# Initialize AI assistant
init_ai_assistant() {
    # Verify AI provider is available but don't fail if not
    init_ai_provider || true
    
    if ai_available; then
        log_success "AI Assistant Ready"
    else
        log_info "AI Assistant disabled (no provider available)"
    fi
}

# Report operation success with AI celebration (optional)
report_success_to_ai() {
    local operation="$1"
    local workspace="$2"
    
    if ! ai_available; then
        return 0
    fi
    
    # Optional: brief congratulatory message
    # Ask AI for a brief, encouraging message
    ask_ai "Generate a one-sentence congratulatory message for successfully $operation workspace: $workspace" "" 2>/dev/null || true
}
