#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ZSHRC="${ROOT_DIR}/stow/base/.zshrc"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_HOME="${TEST_ROOT}/user-home"
SYSTEM_PLUGIN_ROOT="${TEST_ROOT}/system-plugins"
mkdir -p "${TEST_HOME}/.oh-my-zsh"
mkdir -p \
  "${SYSTEM_PLUGIN_ROOT}/zsh-autosuggestions" \
  "${SYSTEM_PLUGIN_ROOT}/zsh-syntax-highlighting"
printf '%s\n' 'export TEST_OH_MY_ZSH_LOADED=1' \
  >"${TEST_HOME}/.oh-my-zsh/oh-my-zsh.sh"
printf '%s\n' 'export TEST_AUTOSUGGESTIONS_LOADED=1' \
  >"${SYSTEM_PLUGIN_ROOT}/zsh-autosuggestions/zsh-autosuggestions.zsh"
printf '%s\n' 'export TEST_SYNTAX_HIGHLIGHTING_LOADED=1' \
  >"${SYSTEM_PLUGIN_ROOT}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

HOME="${TEST_HOME}" ZSH_SYSTEM_PLUGIN_ROOT="${SYSTEM_PLUGIN_ROOT}" \
  /usr/bin/zsh -f -c \
  'source "$1"; [[ "${TEST_OH_MY_ZSH_LOADED:-}" = 1 && "${TEST_AUTOSUGGESTIONS_LOADED:-}" = 1 && "${TEST_SYNTAX_HIGHLIGHTING_LOADED:-}" = 1 ]]' \
  zsh-test "${ZSHRC}"

rm -rf "${TEST_HOME}/.oh-my-zsh"
HOME="${TEST_HOME}" ZSH_SYSTEM_PLUGIN_ROOT="${SYSTEM_PLUGIN_ROOT}" \
  /usr/bin/zsh -f -c \
  'source "$1"; [[ "${TEST_AUTOSUGGESTIONS_LOADED:-}" = 1 && "${TEST_SYNTAX_HIGHLIGHTING_LOADED:-}" = 1 ]]' \
  zsh-test "${ZSHRC}"

printf 'PASS: zsh config loads Oh My Zsh with a portable fallback\n'
