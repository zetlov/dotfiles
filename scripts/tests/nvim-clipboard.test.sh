#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
lua "${ROOT_DIR}/scripts/tests/nvim-clipboard.test.lua" \
  "${ROOT_DIR}/stow/base/.config/nvim/lua/core/clipboard.lua"
printf 'Neovim clipboard checks passed.\n'
