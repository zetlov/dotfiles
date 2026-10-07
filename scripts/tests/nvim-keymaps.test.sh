#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
INSERT_KEYMAPS="${ROOT_DIR}/stow/base/.config/nvim/lua/keymaps/insert.lua"
KEYMAPS_INIT="${ROOT_DIR}/stow/base/.config/nvim/lua/keymaps/init.lua"
TEST_SCRIPT="${ROOT_DIR}/scripts/tests/nvim-keymaps.test.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v lua >/dev/null 2>&1 || fail "Lua is required for Neovim keymap checks"

lua "${TEST_SCRIPT}" "${INSERT_KEYMAPS}" "${KEYMAPS_INIT}"

printf 'Neovim keymap configuration checks passed.\n'
