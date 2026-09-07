#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
UI_CONFIG="${ROOT_DIR}/stow/base/.config/nvim/lua/plugins/ui.lua"
TEST_SCRIPT="${ROOT_DIR}/scripts/tests/nvim-ui.test.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v lua >/dev/null 2>&1 || fail "Lua is required for UI configuration checks"

lua "${TEST_SCRIPT}" "${UI_CONFIG}"

printf 'Neovim UI configuration checks passed.\n'
