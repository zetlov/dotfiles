#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ZSHRC="${ROOT_DIR}/stow/base/.zshrc"
CODEX_POWERSHELL_WRAPPER="${ROOT_DIR}/stow/base/.local/libexec/codex-wsl/powershell.exe"
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

mkdir -p "${TEST_ROOT}/bin"
cat >"${TEST_ROOT}/bin/mise" <<'EOF'
#!/bin/sh
set -eu

case "${1:-}" in
  activate)
    exit 0
    ;;
  x)
    printf '%s\n' "${PATH}" >"${CALL_LOG}.path"
    printf '<%s>\n' "$@" >"${CALL_LOG}.args"
    ;;
  *)
    exit 91
    ;;
esac
EOF
chmod +x "${TEST_ROOT}/bin/mise"

codex_log="${TEST_ROOT}/codex"
HOME="${TEST_HOME}" \
  WSL_INTEROP="/run/WSL/test_interop" \
  ZSH_SYSTEM_PLUGIN_ROOT="${SYSTEM_PLUGIN_ROOT}" \
  CALL_LOG="${codex_log}" \
  PATH="${TEST_ROOT}/bin:/usr/bin" \
  /usr/bin/zsh -f -c 'source "$1"; codex --version' zsh-test "${ZSHRC}"
grep -Fq "${TEST_HOME}/.local/libexec/codex-wsl" "${codex_log}.path"
printf '%s\n' '<x>' '<npm:@openai/codex>' '<-->' '<codex>' '<--version>' \
  >"${TEST_ROOT}/expected-codex.args"
cmp -s "${TEST_ROOT}/expected-codex.args" "${codex_log}.args"

[ -x "${CODEX_POWERSHELL_WRAPPER}" ]
cat >"${TEST_ROOT}/bin/init" <<'EOF'
#!/bin/sh
set -eu
printf '<%s>\n' "$@" >"${CALL_LOG}.init"
EOF
chmod +x "${TEST_ROOT}/bin/init"

CALL_LOG="${codex_log}" \
  CODEX_WSL_INIT="${TEST_ROOT}/bin/init" \
  CODEX_WSL_POWERSHELL="C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" \
  "${CODEX_POWERSHELL_WRAPPER}" -NoProfile -Command 'Write-Output ok'
printf '%s\n' \
  '<C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe>' \
  '<-NoProfile>' \
  '<-Command>' \
  '<Write-Output ok>' \
  >"${TEST_ROOT}/expected-init.args"
cmp -s "${TEST_ROOT}/expected-init.args" "${codex_log}.init"

printf 'PASS: zsh config and Codex WSL clipboard launcher behave as expected\n'
