#!/bin/bash
# Rebuild Analyzer Library for Workspace Updates
# Version: 1.0.0
# Determines if container rebuild or restart is necessary based on changes

# Prevent double-sourcing
if [ -n "$_REBUILD_ANALYZER_SOURCED" ]; then
    return 0
fi
_REBUILD_ANALYZER_SOURCED=1

# Action levels
readonly ACTION_NONE="none"
readonly ACTION_RESTART="restart"
readonly ACTION_REBUILD="rebuild"

# Global state
REBUILD_REQUIRED=false
RESTART_REQUIRED=false
REBUILD_REASON=""
declare -a REBUILD_REASONS=()
declare -a RESTART_REASONS=()

# Check if a file change requires rebuild
requires_rebuild() {
    local filename="$1"
    local category="$2"
    
    case "$category" in
        "dockerfile")
            # Any Dockerfile change requires rebuild
            return 0
            ;;
        "compose")
            # Docker compose service changes require rebuild
            # Check if it's a service definition change (not just environment vars)
            return 0
            ;;
        "config")
            # devcontainer.json usually doesn't require rebuild
            # unless it changes base image or build args
            return 1
            ;;
        "script")
            # Scripts run at container start, no rebuild needed
            return 1
            ;;
        "env")
            # Environment changes only need restart
            return 1
            ;;
        "doc")
            # Documentation never requires rebuild
            return 1
            ;;
        *)
            # Unknown files, be safe and recommend rebuild
            return 0
            ;;
    esac
}

# Check if a file change requires restart
requires_restart() {
    local filename="$1"
    local category="$2"
    
    case "$category" in
        "dockerfile"|"compose")
            # If rebuild needed, restart is implicit
            return 1
            ;;
        "config")
            # Config changes may need restart
            return 0
            ;;
        "script")
            # Post-create scripts need restart to run
            return 0
            ;;
        "env")
            # Environment changes need restart
            return 0
            ;;
        "doc")
            # Documentation doesn't need restart
            return 1
            ;;
        *)
            # Be safe, recommend restart
            return 0
            ;;
    esac
}

# Analyze specific file for rebuild needs with detailed reasoning
analyze_file_change() {
    local filename="$1"
    local category="$2"
    local workspace_file="$3"
    local template_file="$4"
    
    case "$category" in
        "dockerfile")
            # Check what changed in Dockerfile
            if grep -q "FROM " "$template_file" 2>/dev/null; then
                local old_base=$(grep "FROM " "$workspace_file" 2>/dev/null | head -1)
                local new_base=$(grep "FROM " "$template_file" 2>/dev/null | head -1)
                if [ "$old_base" != "$new_base" ]; then
                    echo "Base image changed: $old_base → $new_base"
                    return 0
                fi
            fi
            
            if grep -q "RUN " "$template_file" 2>/dev/null; then
                echo "System packages or build steps modified"
                return 0
            fi
            
            echo "Dockerfile modified"
            return 0
            ;;
        "compose")
            # Check for service definition changes
            if diff -q "$workspace_file" "$template_file" >/dev/null 2>&1; then
                return 1
            fi
            echo "Docker Compose services modified"
            return 0
            ;;
        "config")
            # devcontainer.json analysis
            if [ -f "$workspace_file" ] && [ -f "$template_file" ]; then
                # Check for build-related changes
                if grep -q '"build"' "$template_file" 2>/dev/null; then
                    if ! diff -q <(grep '"build"' "$workspace_file" 2>/dev/null) <(grep '"build"' "$template_file" 2>/dev/null) >/dev/null 2>&1; then
                        echo "Build configuration changed in devcontainer.json"
                        return 0
                    fi
                fi
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Analyze all changes and determine required action
analyze_changes() {
    local workspace_dir="$1"
    local template_dir="$2"
    
    # Reset state
    REBUILD_REQUIRED=false
    RESTART_REQUIRED=false
    REBUILD_REASONS=()
    RESTART_REASONS=()
    
    if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
        return 0
    fi
    
    # Analyze each changed file
    for file in "${CHANGED_FILES[@]}"; do
        local category="${FILE_CATEGORIES[$file]}"
        local workspace_file="${workspace_dir}/.devcontainer/${file}"
        local template_file="${template_dir}/${file}"
        
        # Check if rebuild needed
        if requires_rebuild "$(basename "$file")" "$category"; then
            REBUILD_REQUIRED=true
            local reason=$(analyze_file_change "$file" "$category" "$workspace_file" "$template_file")
            REBUILD_REASONS+=("$file: $reason")
        # Otherwise check if restart needed
        elif requires_restart "$(basename "$file")" "$category"; then
            RESTART_REQUIRED=true
            RESTART_REASONS+=("$file: ${category} change")
        fi
    done
    
    return 0
}

# Get recommended action
get_recommended_action() {
    if [ "$REBUILD_REQUIRED" = true ]; then
        echo "$ACTION_REBUILD"
    elif [ "$RESTART_REQUIRED" = true ]; then
        echo "$ACTION_RESTART"
    else
        echo "$ACTION_NONE"
    fi
}

# Display action summary
display_action_summary() {
    local action=$(get_recommended_action)
    
    echo ""
    log_info "Action Analysis:"
    echo ""
    
    case "$action" in
        "$ACTION_REBUILD")
            echo -e "${YELLOW}⚠ Container rebuild required${NC}"
            echo ""
            echo -e "${BLUE}Reasons:${NC}"
            for reason in "${REBUILD_REASONS[@]}"; do
                echo -e "  • $reason"
            done
            echo ""
            echo -e "${BLUE}Required steps:${NC}"
            echo -e "  1. ${CYAN}docker-compose down${NC}"
            echo -e "  2. ${CYAN}docker-compose up --build -d${NC}"
            echo -e "  3. Reopen workspace in VSCode"
            echo ""
            echo -e "${YELLOW}Estimated time: 5-15 minutes${NC}"
            ;;
        "$ACTION_RESTART")
            echo -e "${BLUE}ℹ Container restart recommended${NC}"
            echo ""
            echo -e "${BLUE}Reasons:${NC}"
            for reason in "${RESTART_REASONS[@]}"; do
                echo -e "  • $reason"
            done
            echo ""
            echo -e "${BLUE}Required steps:${NC}"
            echo -e "  1. ${CYAN}docker-compose restart${NC}"
            echo -e "     OR reopen workspace in VSCode"
            echo ""
            echo -e "${GREEN}Estimated time: 1-2 minutes${NC}"
            ;;
        "$ACTION_NONE")
            echo -e "${GREEN}✓ No rebuild or restart needed${NC}"
            echo ""
            echo -e "Changes applied successfully!"
            echo -e "Updates will take effect on next workspace open."
            ;;
    esac
    echo ""
}

# Generate AI prompt for change analysis
generate_ai_analysis_prompt() {
    local workspace_name="$1"
    
    if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
        return 1
    fi
    
    cat << EOF
Analyze the following workspace configuration changes and provide:
1. A brief explanation of what changed
2. Potential impact on the development environment
3. Any migration steps needed
4. Confirmation of rebuild necessity

Workspace: $workspace_name

Changes detected:
EOF
    
    for file in "${CHANGED_FILES[@]}"; do
        local category="${FILE_CATEGORIES[$file]}"
        local change_type="${FILE_CHANGES[$file]}"
        echo "- $file [$category] ($change_type)"
    done
    
    echo ""
    echo "Rebuild analysis:"
    if [ "$REBUILD_REQUIRED" = true ]; then
        echo "REBUILD REQUIRED"
        for reason in "${REBUILD_REASONS[@]}"; do
            echo "  - $reason"
        done
    elif [ "$RESTART_REQUIRED" = true ]; then
        echo "RESTART RECOMMENDED"
        for reason in "${RESTART_REASONS[@]}"; do
            echo "  - $reason"
        done
    else
        echo "NO ACTION REQUIRED"
    fi
}

# Use AI to analyze changes (if available)
ai_analyze_changes() {
    local workspace_name="$1"
    
    # Check if AI is available
    if [ -z "$AI_PROVIDER" ] || [ "$AI_PROVIDER" = "none" ]; then
        return 1
    fi
    
    log_info "Analyzing changes with AI..."
    echo ""
    
    local prompt=$(generate_ai_analysis_prompt "$workspace_name")
    
    # Call AI provider (implementation depends on available AI tools)
    # For now, just show that AI could be used here
    if command -v call_ai_cli >/dev/null 2>&1; then
        local ai_response=$(call_ai_cli "$prompt" "text" 2>/dev/null || echo "")
        if [ -n "$ai_response" ]; then
            echo -e "${CYAN}AI Analysis:${NC}"
            echo "$ai_response"
            echo ""
            return 0
        fi
    fi
    
    return 1
}

# Export functions
export -f requires_rebuild
export -f requires_restart
export -f analyze_file_change
export -f analyze_changes
export -f get_recommended_action
export -f display_action_summary
export -f generate_ai_analysis_prompt
export -f ai_analyze_changes
