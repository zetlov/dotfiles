#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"
CONFIG_PATH="${ROOT_DIR}/stow/base/.config/starship.toml"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "${CONFIG_PATH}" ]] || fail "Starship config is missing"

if command -v python >/dev/null 2>&1; then
    python_command=(python)
elif command -v python3 >/dev/null 2>&1; then
    python_command=(python3)
elif command -v mise >/dev/null 2>&1; then
    python_command=(mise exec -- python)
else
    fail "Starship configuration validation requires Python 3"
fi

"${python_command[@]}" -c '
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config["format"].endswith("$line_break$character")

character = config["character"]
assert character["success_symbol"] == "[>](bold green)"
assert character["error_symbol"] == "[>](bold red)"
' "${CONFIG_PATH}" || fail "Starship must keep Unicode decorations above an ASCII input prompt"

printf 'Starship configuration checks passed.\n'
