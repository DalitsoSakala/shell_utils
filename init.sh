#!/usr/bin/env bash
# Install selected shell_utils *_ref.sh helpers into ~/.bashrc.

set -euo pipefail

SHELL_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="${HOME}/.bashrc"
MARKER_BEGIN="# >>> shell_utils >>>"
MARKER_END="# <<< shell_utils <<<"

mapfile -t REF_FILES < <(find "$SHELL_UTILS_DIR" -maxdepth 1 -type f -name '*_ref.sh' | sort)

if [ ${#REF_FILES[@]} -eq 0 ]; then
    echo "No *_ref.sh files found in ${SHELL_UTILS_DIR}" >&2
    exit 1
fi

echo "Available *_ref.sh files in ${SHELL_UTILS_DIR}:"
for i in "${!REF_FILES[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "$(basename "${REF_FILES[$i]}")"
done
echo
echo "Enter numbers to include (space/comma separated), 'a' for all, or 'q' to cancel:"
read -r -p "> " selection

case "$selection" in
    q|Q|"")
        echo "Cancelled."
        exit 0
        ;;
    a|A)
        SELECTED=("${REF_FILES[@]}")
        ;;
    *)
        SELECTED=()
        # Normalize commas to spaces, then pick by 1-based index.
        selection="${selection//,/ }"
        for token in $selection; do
            if ! [[ "$token" =~ ^[0-9]+$ ]]; then
                echo "Invalid selection: '$token'" >&2
                exit 1
            fi
            idx=$((token - 1))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#REF_FILES[@]} ]; then
                echo "Out of range: $token" >&2
                exit 1
            fi
            SELECTED+=("${REF_FILES[$idx]}")
        done
        # Deduplicate while preserving order.
        if [ ${#SELECTED[@]} -gt 0 ]; then
            mapfile -t SELECTED < <(printf '%s\n' "${SELECTED[@]}" | awk '!seen[$0]++')
        fi
        ;;
esac

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "No files selected." >&2
    exit 1
fi

echo
echo "Will source:"
for f in "${SELECTED[@]}"; do
    echo "  - $(basename "$f")"
done
echo

write_block() {
    cat <<EOF
${MARKER_BEGIN}
# Sourced by ${SHELL_UTILS_DIR}/init.sh
if [ -d "${SHELL_UTILS_DIR}" ]; then
EOF
    for f in "${SELECTED[@]}"; do
        local base
        base="$(basename "$f")"
        cat <<EOF
    if [ -f "${SHELL_UTILS_DIR}/${base}" ]; then
        . "${SHELL_UTILS_DIR}/${base}"
    fi
EOF
    done
    cat <<EOF
fi
${MARKER_END}
EOF
}

touch "$BASHRC"
tmp="$(mktemp)"

# Drop the old single-file git.sh hook and any previous marked block.
awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    /if \[ -f "\$HOME\/shell_utils\/git\.sh" \]/ { old=1; next }
    old && /^fi$/ { old=0; next }
    old { next }
    $0 == begin { marked=1; next }
    marked && $0 == end { marked=0; next }
    marked { next }
    { print }
' "$BASHRC" > "$tmp"
mv "$tmp" "$BASHRC"

# Trim trailing blank lines, then append one blank line and the block.
tmp="$(mktemp)"
awk 'NF { blank = 0 } !NF { blank++ } { lines[NR] = $0 }
     END { end = NR; while (end > 0 && lines[end] == "") end--;
           for (i = 1; i <= end; i++) print lines[i] }' "$BASHRC" > "$tmp"
mv "$tmp" "$BASHRC"
printf '\n' >> "$BASHRC"
write_block >> "$BASHRC"

echo "Installed shell_utils block in ${BASHRC}"
echo "Done. Open a new shell or run: source ${BASHRC}"
