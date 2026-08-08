#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"
CONFIG_PATH="${ROOT_DIR}/stow/base/.config/herdr/config.toml"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "${CONFIG_PATH}" ]] || fail "Herdr config is missing"

git -C "${ROOT_DIR}" check-ignore -q "${CONFIG_PATH}" \
    && fail "Herdr config is ignored by Git"

if command -v herdr >/dev/null 2>&1; then
    HERDR_CONFIG_PATH="${CONFIG_PATH}" herdr config check
else
    if command -v python >/dev/null 2>&1; then
        python_command=(python)
    elif command -v python3 >/dev/null 2>&1; then
        python_command=(python3)
    elif command -v mise >/dev/null 2>&1; then
        python_command=(mise exec -- python)
    else
        fail "Herdr fallback validation requires Python 3"
    fi
    "${python_command[@]}" -c '
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config["onboarding"] is False
assert config["theme"]["name"] == "catppuccin"
assert config["terminal"]["default_shell"] == "zsh"
assert config["update"]["channel"] == "stable"
' "${CONFIG_PATH}" || fail "Herdr config is invalid"
fi

grep -Fq 'herdr completion zsh' "${ROOT_DIR}/stow/base/.zshrc" \
    || fail "Herdr zsh completion is not configured"

printf 'Herdr configuration checks passed.\n'
