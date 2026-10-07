#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
OPTIONS_CONFIG="${ROOT_DIR}/stow/base/.config/nvim/lua/core/options.lua"
TEST_SCRIPT="${ROOT_DIR}/scripts/tests/nvim-cursor.test.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v lua >/dev/null 2>&1 || fail "Lua is required for Neovim cursor checks"

lua "${TEST_SCRIPT}" "${OPTIONS_CONFIG}"

printf 'Neovim cursor configuration checks passed.\n'
