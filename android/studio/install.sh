#!/usr/bin/env bash
# Install Compose live templates (compDetail, compForm) into Android Studio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILES=(
    "${SCRIPT_DIR}/compose_templates.xml"
    "${SCRIPT_DIR}/architecture_templates.xml"
)

for SOURCE in "${SOURCE_FILES[@]}"; do
    if [ ! -f "$SOURCE" ]; then
        echo "Missing ${SOURCE}; running the generator..." >&2
        bash "${SCRIPT_DIR}/templates/generate.sh"
        break
    fi
done

TARGET_DIRS=()

# Add <base>/AndroidStudio*/templates dirs if any exist.
add_variants() {
    local base="$1"
    [ -d "$base" ] || return 0
    for dir in "$base"/AndroidStudio*; do
        [ -d "$dir" ] || continue
        TARGET_DIRS+=("$dir/templates")
    done
}

case "$(uname -s)" in
    Linux)
        add_variants "${HOME}/.config/Google"
        add_variants "${HOME}/.config/JetBrains"
        ;;
    Darwin)
        add_variants "${HOME}/Library/Application Support/Google"
        add_variants "${HOME}/Library/Application Support/JetBrains"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        add_variants "${APPDATA:-}/Google"
        add_variants "${LOCALAPPDATA:-}/Google"
        ;;
    *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

if [ ${#TARGET_DIRS[@]} -eq 0 ]; then
    echo "No Android Studio config directory found."
    echo "Copy these into the templates folder of your Android Studio:"
    echo "  ${SCRIPT_DIR}/compose_templates.xml"
    echo "  ${SCRIPT_DIR}/architecture_templates.xml"
    echo "  Linux:   ~/.config/Google/AndroidStudio*/templates/"
    echo "  Linux:   ~/.config/JetBrains/AndroidStudio*/templates/ (Toolbox)"
    echo "  macOS:   ~/Library/Application Support/Google/AndroidStudio*/templates/"
    echo "  Windows: %APPDATA%\\Google\\AndroidStudio*\\templates\\"
    echo "Then restart Android Studio."
    exit 0
fi

for tdir in "${TARGET_DIRS[@]}"; do
    mkdir -p "$tdir"
    for src in "${SOURCE_FILES[@]}"; do
        cp "$src" "$tdir/$(basename "$src")"
        echo "Installed -> ${tdir}/$(basename "$src")"
    done
done

echo
echo "Done. Restart Android Studio, then type the abbreviation in a Kotlin file"
echo "to expand a template."
echo "  Compose group:      compDetail, compForm, compCard, compTextField"
echo "  Architecture group: compDomainModel, compRepository, compUseCase,"
echo "                      compEntity, compDao, compDto, compApi,"
echo "                      compRepositoryImpl, compViewModel, compNavGraph"
