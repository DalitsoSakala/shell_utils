#!/usr/bin/env bash
# Neovim reference helper and snippets viewer alias.

# Function to view all Neovim custom snippets configured by this project
nvimsnips() {
    local shell_utils_dir="/home/dalitso/Projects/shell_utils"
    local kotlin_json="${shell_utils_dir}/nvim/snippets/kotlin.json"
    local go_json="${shell_utils_dir}/nvim/snippets/go.json"
    local react_json="${shell_utils_dir}/nvim/snippets/react.json"
    
    echo -e "\033[1;36m================================================================================\033[0m"
    echo -e "\033[1;36m  Neovim Custom Snippets Configured in shell_utils\033[0m"
    echo -e "\033[1;36m================================================================================\033[0m"
    
    if [ -f "$kotlin_json" ]; then
        echo -e "\n\033[1;32mKotlin (Jetpack Compose, Room, Retrofit) Snippets:\033[0m"
        echo "--------------------------------------------------"
        if command -v jq >/dev/null 2>&1; then
            jq -r 'to_entries[] | "\(.value.prefix)\t- \(.value.description)"' "$kotlin_json" | column -t -s $'\t' | sed 's/^/  /'
        else
            echo "  (jq is required for clean parsing, showing raw keys)"
            grep -E '"(prefix|description)"' "$kotlin_json" | awk 'NR%2==1 {printf "  %-16s", $2} NR%2==0 {print " - "$2}' | tr -d '",:'
        fi
    else
        echo -e "\n  Kotlin snippets file not found at: $kotlin_json"
    fi
    
    if [ -f "$go_json" ]; then
        echo -e "\n\033[1;32mGo (GORM) Snippets:\033[0m"
        echo "-------------------"
        if command -v jq >/dev/null 2>&1; then
            jq -r 'to_entries[] | "\(.value.prefix)\t- \(.value.description)"' "$go_json" | column -t -s $'\t' | sed 's/^/  /'
        else
            echo "  (jq is required for clean parsing, showing raw keys)"
            grep -E '"(prefix|description)"' "$go_json" | awk 'NR%2==1 {printf "  %-16s", $2} NR%2==0 {print " - "$2}' | tr -d '",:'
        fi
    else
        echo -e "\n  Go snippets file not found at: $go_json"
    fi

    if [ -f "$react_json" ]; then
        echo -e "\n\033[1;32mReact (JS/TS) Snippets:\033[0m"
        echo "-----------------------"
        if command -v jq >/dev/null 2>&1; then
            jq -r 'to_entries[] | "\(.value.prefix)\t- \(.value.description)"' "$react_json" | column -t -s $'\t' | sed 's/^/  /'
        else
            echo "  (jq is required for clean parsing, showing raw keys)"
            grep -E '"(prefix|description)"' "$react_json" | awk 'NR%2==1 {printf "  %-16s", $2} NR%2==0 {print " - "$2}' | tr -d '",:'
        fi
    else
        echo -e "\n  React snippets file not found at: $react_json"
    fi
    echo
}
