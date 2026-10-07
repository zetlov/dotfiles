#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
COMMON_PACKAGES="${ROOT_DIR}/packages/common.txt"
WSL_PACKAGES="${ROOT_DIR}/packages/wsl.txt"
LSP_CONFIG="${ROOT_DIR}/stow/base/.config/nvim/lua/plugins/lsp.lua"
DEBUG_CONFIG="${ROOT_DIR}/stow/base/.config/nvim/lua/plugins/debug.lua"
TEST_SCRIPT="${ROOT_DIR}/scripts/tests/cpp-development.test.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for package in cmake ninja clang ccache gdb; do
    if ! rg -x -q "${package}" "${COMMON_PACKAGES}"; then
        fail "${package} should be installed as an OS-managed C++ development tool"
    fi
done

if rg -q 'automatic_installation' "${LSP_CONFIG}"; then
    fail "mason-lspconfig should not use the removed automatic_installation option"
fi

if ! rg -F -q 'cmd = { "/usr/bin/clangd", "--background-index", "--clang-tidy" }' \
    "${LSP_CONFIG}"; then
    fail "Neovim should use the OS-managed clangd executable"
fi

if ! rg -F -q 'command = "/usr/bin/clang-format"' \
    "${ROOT_DIR}/stow/base/.config/nvim/lua/plugins/formatting.lua"; then
    fail "Neovim should use the OS-managed clang-format executable"
fi

if rg -q 'clangtidy' "${ROOT_DIR}/stow/base/.config/nvim/lua/plugins/linting.lua"; then
    fail "clang-tidy diagnostics should come from clangd instead of running twice on save"
fi

if rg -i -q 'Arch Linux ARM|x86_64 only|ARM only' "${WSL_PACKAGES}"; then
    fail "the shared WSL package profile should not claim a single CPU architecture"
fi

command -v lua >/dev/null 2>&1 || fail "Lua is required for Neovim C++ configuration checks"
lua "${TEST_SCRIPT}" "${LSP_CONFIG}" "${DEBUG_CONFIG}"

printf 'C++ development environment configuration checks passed.\n'
