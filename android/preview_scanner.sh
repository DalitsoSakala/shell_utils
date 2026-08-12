#!/usr/bin/env bash
# Bash script to scan for Composable previews, prompt selection, and run screenshot tests.

set -euo pipefail

# Optional file filter argument
TARGET_FILTER="${1:-}"

echo "Scanning project for @Preview composables..."

# Find all Kotlin files, excluding build, git, gradle directories
if [ -n "$TARGET_FILTER" ]; then
    # Filter files containing target filter and @Preview
    mapfile -t files < <(find . -name "*.kt" \
        -not -path "*/build/*" \
        -not -path "*/.*/*" \
        \( -name "*${TARGET_FILTER}*" -o -path "*${TARGET_FILTER}*" \) \
        -exec grep -l "@Preview" {} + 2>/dev/null || true)
else
    # Find all files containing @Preview
    mapfile -t files < <(find . -name "*.kt" \
        -not -path "*/build/*" \
        -not -path "*/.*/*" \
        -exec grep -l "@Preview" {} + 2>/dev/null || true)
fi

if [ ${#files[@]} -eq 0 ]; then
    if [ -n "$TARGET_FILTER" ]; then
        echo "No Kotlin files with @Preview found matching: $TARGET_FILTER"
    else
        echo "No @Preview annotations found in the project."
    fi
    exit 1
fi

# Arrays to store function names and file names
functions=()
file_names=()
paths=()

# Extract preview functions
for file in "${files[@]}"; do
    # Use awk to extract function names following @Preview
    while read -r func_name; do
        if [ -n "$func_name" ]; then
            functions+=("$func_name")
            file_names+=("$(basename "$file")")
            paths+=("$file")
        fi
    done < <(awk '/@Preview/ {found = 1; lines = 0} found {lines++; if ($0 ~ /fun[ \t]+[a-zA-Z0-9_]+/) {match($0, /fun[ \t]+[a-zA-Z0-9_]+/); sub(/.*fun[ \t]+/, "", $0); split($0, parts, /[( \t]/); print parts[1]; found = 0} if (lines > 10 || $0 ~ /\{/) {found = 0}}' "$file")
done

if [ ${#functions[@]} -eq 0 ]; then
    echo "No @Preview functions could be parsed."
    exit 1
fi

echo -e "\nDiscovered Previews:"
for i in "${!functions[@]}"; do
    num=$((i + 1))
    echo "  $num) ${functions[$i]} (in ${file_names[$i]})"
done
all_idx=$((${#functions[@]} + 1))
echo "  $all_idx) [Run All Previews]"

read -r -p "Select a preview to run (1-$all_idx): " choice

if [ -z "$choice" ]; then
    echo "No selection. Exiting."
    exit 0
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "Invalid selection."
    exit 1
fi

filter_arg=""
if [ "$choice" -eq "$all_idx" ]; then
    echo -e "\nRunning all previews..."
elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#functions[@]}" ]; then
    idx=$((choice - 1))
    filter_arg="*${functions[$idx]}*"
    echo -e "\nRunning preview for: ${functions[$idx]}"
else
    echo "Selection out of range."
    exit 1
fi

# Track start time of the build to locate newly updated reference screenshots
start_time=$(date +%s)

# Execute gradlew updateDebugScreenshotTest
if [ -n "$filter_arg" ]; then
    echo "Executing: ./gradlew updateDebugScreenshotTest --tests \"$filter_arg\""
    ./gradlew updateDebugScreenshotTest --tests "$filter_arg"
else
    echo "Executing: ./gradlew updateDebugScreenshotTest"
    ./gradlew updateDebugScreenshotTest
fi

echo -e "\nBuild Successful!"

# Find reference files changed since script started
echo -e "\nGenerated/Updated Previews Location:"
found_png=false

# We search inside any directories named 'screenshotTest' and 'reference'
while read -r png; do
    if [ -n "$png" ]; then
        # Check file modification time vs start_time
        file_mtime=$(stat -c %Y "$png" 2>/dev/null || stat -f %m "$png" 2>/dev/null || echo 0)
        if [ "$file_mtime" -ge "$((start_time - 5))" ]; then
            echo "  - $(realpath "$png")"
            found_png=true
        fi
    fi
done < <(find . -type f -name "*.png" -path "*/screenshotTest/reference/*" 2>/dev/null || true)

if [ "$found_png" = false ]; then
    # General fallback location printing
    general_ref_dir=$(find . -type d -path "*/screenshotTest/reference" 2>/dev/null | head -n 1 || true)
    if [ -n "$general_ref_dir" ]; then
        echo "  Previews directory: $(realpath "$general_ref_dir")"
    else
        echo "  Previews directory: (module)/src/screenshotTest/reference/"
    fi
fi
