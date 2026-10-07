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

if command -v python >/dev/null 2>&1; then
    python_command=(python)
elif command -v python3 >/dev/null 2>&1; then
    python_command=(python3)
elif command -v mise >/dev/null 2>&1; then
    python_command=(mise exec -- python)
else
    fail "Herdr configuration validation requires Python 3"
fi
"${python_command[@]}" -c '
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config["onboarding"] is False
assert config["theme"]["name"] == "terminal"
assert config["theme"]["custom"]["panel_bg"] == "reset"
assert config["theme"]["custom"]["sidebar_bg"] == "reset"
assert config["terminal"]["default_shell"] == "zsh"
assert config["update"]["channel"] == "stable"
assert config["ui"]["status_indicators"] == "symbols"
assert "status_indecators" not in config["ui"]

keys = config["keys"]
commands = keys["command"]
assert keys["switch_tab"] == ""
assert keys["switch_workspace"] == "prefix+1..9"
assert keys["last_pane"] == "prefix+backtick"
assert keys["previous_workspace"] == "prefix+left"
assert keys["next_workspace"] == "prefix+right"
assert config["ui"]["sidebar"]["spaces"]["rows"][0] == [
    "$num",
    "state_icon",
    "workspace",
]
assert {command["command"] for command in commands} == {"lazygit", "fzf"}
command_keys = [command["key"] for command in commands]
assert all(key.startswith("prefix+") for key in command_keys)
assert len(set(command_keys)) == len(command_keys)
action_keys = {
    binding
    for action, value in keys.items()
    if action not in ("prefix", "command")
    for binding in (value if isinstance(value, list) else [value])
}
assert not set(command_keys) & action_keys
' "${CONFIG_PATH}" || fail "Herdr config is invalid"

if command -v herdr >/dev/null 2>&1; then
    HERDR_CONFIG_PATH="${CONFIG_PATH}" herdr config check
fi

grep -Fq 'herdr completion zsh' "${ROOT_DIR}/stow/base/.zshrc" \
    || fail "Herdr zsh completion is not configured"

printf 'Herdr configuration checks passed.\n'
