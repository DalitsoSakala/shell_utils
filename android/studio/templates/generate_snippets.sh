#!/usr/bin/env bash
# Regenerate the nvim LuaSnip Kotlin snippets from the canonical .template.kt
# bodies. Run via init_nvim.sh, or manually when templates change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${SCRIPT_DIR}/generate.py" json
