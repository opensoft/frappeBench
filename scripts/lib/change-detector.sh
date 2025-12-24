#!/bin/bash
# Change Detection Library for Workspace Updates
# Version: 1.0.0
# Provides utilities for detecting and analyzing file changes

# Prevent double-sourcing
if [ -n "$_CHANGE_DETECTOR_SOURCED" ]; then
    return 0
fi
_CHANGE_DETECTOR_SOURCED=1

# Change categories
readonly CHANGE_DOCKERFILE="dockerfile"
readonly CHANGE_COMPOSE="compose"
readonly CHANGE_CONFIG="config"
readonly CHANGE_SCRIPT="script"
readonly CHANGE_ENV="env"
readonly CHANGE_DOC="doc"
readonly CHANGE_OTHER="other"

# Global arrays to track changes
declare -a CHANGED_FILES=()
declare -A FILE_CHANGES=()
declare -A FILE_CATEGORIES=()

# Calculate file checksum
calculate_checksum() {
    local file="$1"
    if [ -f "$file" ]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        echo "missing"
    fi
}

# Categorize file by name
categorize_file() {
    local filename="$1"
    
    case "$filename" in
        Dockerfile*)
            echo "$CHANGE_DOCKERFILE"
            ;;
        docker-compose*.yml|docker-compose*.yaml)
            echo "$CHANGE_COMPOSE"
            ;;
        devcontainer.json|.devcontainer.json)
            echo "$CHANGE_CONFIG"
            ;;
        *.sh)
            echo "$CHANGE_SCRIPT"
            ;;
        .env|.env.example|env.example)
            echo "$CHANGE_ENV"
            ;;
        *.md|README*|CHANGELOG*)
            echo "$CHANGE_DOC"
            ;;
        *)
            echo "$CHANGE_OTHER"
            ;;
    esac
}

# Compare two files and determine if they differ
files_differ() {
    local file1="$1"
    local file2="$2"
    
    # If one doesn't exist, they differ
    if [ ! -f "$file1" ] && [ -f "$file2" ]; then
        return 0  # True - they differ
    elif [ -f "$file1" ] && [ ! -f "$file2" ]; then
        return 0  # True - they differ
    elif [ ! -f "$file1" ] && [ ! -f "$file2" ]; then
        return 1  # False - both missing, no diff
    fi
    
    # Both exist, compare checksums
    local sum1=$(calculate_checksum "$file1")
    local sum2=$(calculate_checksum "$file2")
    
    if [ "$sum1" != "$sum2" ]; then
        return 0  # True - they differ
    else
        return 1  # False - same
    fi
}

# Get human-readable diff between two files
get_file_diff() {
    local file1="$1"
    local file2="$2"
    local context_lines="${3:-3}"
    
    if [ ! -f "$file1" ]; then
        echo "New file: $file2"
        return 0
    elif [ ! -f "$file2" ]; then
        echo "File deleted: $file1"
        return 0
    fi
    
    # Generate unified diff with context
    diff -u --color=never -U"$context_lines" "$file1" "$file2" 2>/dev/null || true
}

# Count significant changes (ignore whitespace and comments)
count_significant_changes() {
    local file1="$1"
    local file2="$2"
    
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "unknown"
        return 0
    fi
    
    # Count lines that changed (excluding whitespace-only changes)
    local changes
    changes=$(diff -w -B "$file1" "$file2" 2>/dev/null | grep -c "^[<>]" || echo "0")
    echo "$changes"
}

# Scan template directory for updateable files
scan_template_files() {
    local template_dir="$1"
    local -a files=()
    
    if [ ! -d "$template_dir" ]; then
        return 1
    fi
    
    # Find all files in template (excluding hidden files except .env*)
    while IFS= read -r -d '' file; do
        local relative_path="${file#$template_dir/}"
        files+=("$relative_path")
    done < <(find "$template_dir" -type f \( ! -name ".*" -o -name ".env*" \) -print0)
    
    printf '%s\n' "${files[@]}"
}

# Compare workspace with template and detect changes
detect_workspace_changes() {
    local workspace_dir="$1"
    local template_dir="$2"
    local verbose="${3:-false}"
    
    # Clear previous results
    CHANGED_FILES=()
    FILE_CHANGES=()
    FILE_CATEGORIES=()
    
    # Get all template files
    local -a template_files
    mapfile -t template_files < <(scan_template_files "$template_dir")
    
    if [ ${#template_files[@]} -eq 0 ]; then
        [ "$verbose" = true ] && echo "No template files found"
        return 1
    fi
    
    # Compare each file
    local change_count=0
    for rel_path in "${template_files[@]}"; do
        local workspace_file="${workspace_dir}/.devcontainer/${rel_path}"
        local template_file="${template_dir}/${rel_path}"
        
        # Skip .env file (we preserve it)
        if [[ "$(basename "$rel_path")" == ".env" ]]; then
            continue
        fi
        
        if files_differ "$workspace_file" "$template_file"; then
            CHANGED_FILES+=("$rel_path")
            FILE_CATEGORIES["$rel_path"]=$(categorize_file "$(basename "$rel_path")")
            
            # Store change type
            if [ ! -f "$workspace_file" ]; then
                FILE_CHANGES["$rel_path"]="new"
            elif [ ! -f "$template_file" ]; then
                FILE_CHANGES["$rel_path"]="deleted"
            else
                local sig_changes=$(count_significant_changes "$workspace_file" "$template_file")
                FILE_CHANGES["$rel_path"]="modified:$sig_changes"
            fi
            
            ((change_count++))
        fi
    done
    
    [ "$verbose" = true ] && echo "Detected $change_count changed files"
    return 0
}

# Display change summary
display_change_summary() {
    local show_details="${1:-true}"
    
    if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
        log_success "No changes detected - workspace is up to date!"
        return 0
    fi
    
    echo ""
    log_info "Update Summary:"
    log_info "  Files to update: ${#CHANGED_FILES[@]}"
    echo ""
    
    if [ "$show_details" = true ]; then
        # Group by category
        local -A category_counts
        for file in "${CHANGED_FILES[@]}"; do
            local category="${FILE_CATEGORIES[$file]}"
            category_counts[$category]=$((${category_counts[$category]:-0} + 1))
        done
        
        # Display by category
        for category in "$CHANGE_DOCKERFILE" "$CHANGE_COMPOSE" "$CHANGE_CONFIG" "$CHANGE_SCRIPT" "$CHANGE_ENV" "$CHANGE_DOC" "$CHANGE_OTHER"; do
            local count=${category_counts[$category]:-0}
            if [ $count -gt 0 ]; then
                local category_name=""
                case "$category" in
                    "$CHANGE_DOCKERFILE") category_name="Dockerfile changes" ;;
                    "$CHANGE_COMPOSE") category_name="Docker Compose changes" ;;
                    "$CHANGE_CONFIG") category_name="Configuration changes" ;;
                    "$CHANGE_SCRIPT") category_name="Script changes" ;;
                    "$CHANGE_ENV") category_name="Environment changes" ;;
                    "$CHANGE_DOC") category_name="Documentation changes" ;;
                    "$CHANGE_OTHER") category_name="Other changes" ;;
                esac
                
                echo -e "${BLUE}  $category_name: $count${NC}"
                
                # List files in this category
                for file in "${CHANGED_FILES[@]}"; do
                    if [ "${FILE_CATEGORIES[$file]}" = "$category" ]; then
                        local change_type="${FILE_CHANGES[$file]}"
                        local badge=""
                        
                        if [[ "$change_type" == "new" ]]; then
                            badge="${GREEN}[NEW]${NC}"
                        elif [[ "$change_type" == "deleted" ]]; then
                            badge="${RED}[DELETED]${NC}"
                        elif [[ "$change_type" == modified:* ]]; then
                            local num_changes="${change_type#modified:}"
                            badge="${YELLOW}[~$num_changes lines]${NC}"
                        fi
                        
                        echo -e "    - $file $badge"
                    fi
                done
                echo ""
            fi
        done
    fi
}

# Show detailed diff for a specific file
show_file_diff() {
    local workspace_dir="$1"
    local template_dir="$2"
    local rel_path="$3"
    local context_lines="${4:-5}"
    
    local workspace_file="${workspace_dir}/.devcontainer/${rel_path}"
    local template_file="${template_dir}/${rel_path}"
    
    echo ""
    log_info "Diff for: $rel_path"
    echo ""
    
    get_file_diff "$workspace_file" "$template_file" "$context_lines"
}

# Interactive review of changes
interactive_change_review() {
    local workspace_dir="$1"
    local template_dir="$2"
    
    if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
        return 0
    fi
    
    echo ""
    log_info "Review changes before applying?"
    echo "  [y] Review each file"
    echo "  [a] Apply all without review"
    echo "  [q] Quit without updating"
    echo ""
    read -p "Choice [y/a/q]: " choice
    
    case "$choice" in
        y|Y)
            for file in "${CHANGED_FILES[@]}"; do
                clear
                show_file_diff "$workspace_dir" "$template_dir" "$file"
                echo ""
                read -p "Apply this change? [Y/n]: " apply
                if [[ "$apply" =~ ^[nN] ]]; then
                    log_warn "Skipped: $file"
                    # Remove from changed files array
                    CHANGED_FILES=("${CHANGED_FILES[@]/$file}")
                fi
            done
            return 0
            ;;
        a|A)
            return 0
            ;;
        q|Q)
            log_info "Update cancelled"
            return 1
            ;;
        *)
            log_warn "Invalid choice, applying all changes"
            return 0
            ;;
    esac
}

# Export functions for use in other scripts
export -f calculate_checksum
export -f categorize_file
export -f files_differ
export -f get_file_diff
export -f count_significant_changes
export -f detect_workspace_changes
export -f display_change_summary
export -f show_file_diff
export -f interactive_change_review
