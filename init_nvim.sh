#!/usr/bin/env bash
# Install the vendored NvChad Neovim config and bootstrap Lazy plugins.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_CONFIG_SRC="${REPO_DIR}/nvim"
NVIM_CONFIG_DST="${HOME}/.config/nvim"

if ! command -v nvim >/dev/null 2>&1; then
    echo "Error: nvim is not installed or not on PATH." >&2
    exit 1
fi

if [ ! -d "$NVIM_CONFIG_SRC" ]; then
    echo "Error: Neovim config source not found at ${NVIM_CONFIG_SRC}" >&2
    exit 1
fi

mkdir -p "${HOME}/.config"

backup_path=""
if [ -e "$NVIM_CONFIG_DST" ] || [ -L "$NVIM_CONFIG_DST" ]; then
    if [ -L "$NVIM_CONFIG_DST" ] && [ "$(readlink -f "$NVIM_CONFIG_DST")" = "$(readlink -f "$NVIM_CONFIG_SRC")" ]; then
        echo "Neovim config already linked to ${NVIM_CONFIG_SRC}"
    else
        backup_path="${NVIM_CONFIG_DST}.bak.$(date +%Y%m%d%H%M%S)"
        mv "$NVIM_CONFIG_DST" "$backup_path"
        echo "Backed up existing config to ${backup_path}"
        ln -s "$NVIM_CONFIG_SRC" "$NVIM_CONFIG_DST"
        echo "Linked ${NVIM_CONFIG_DST} -> ${NVIM_CONFIG_SRC}"
    fi
else
    ln -s "$NVIM_CONFIG_SRC" "$NVIM_CONFIG_DST"
    echo "Linked ${NVIM_CONFIG_DST} -> ${NVIM_CONFIG_SRC}"
fi

echo "Bootstrapping Lazy plugins (headless Lazy! sync)..."
nvim --headless "+Lazy! sync" +qa

echo "Done. Open Neovim with: nvim"
if [ -n "$backup_path" ]; then
    echo "Previous config saved at: ${backup_path}"
fi
