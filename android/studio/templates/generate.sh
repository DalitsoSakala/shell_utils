#!/usr/bin/env bash
# Generate Android Studio live template XML files and refresh the nvim
# LuaSnip snippets from the canonical .template.kt bodies in this directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${SCRIPT_DIR}/generate.py" all
