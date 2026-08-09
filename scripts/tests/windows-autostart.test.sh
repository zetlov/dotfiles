#!/usr/bin/env bash
set -euo pipefail

repo_root=$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)
config_path="$repo_root/windows/autostart/apps.json"
komorebi_path="$repo_root/windows/komorebi/komorebi.json"

python3 - "$config_path" "$komorebi_path" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
komorebi_path = pathlib.Path(sys.argv[2])
with config_path.open(encoding="utf-8") as config_file:
    config = json.load(config_file)

expected = {
    "Zen": 1,
    "Zotero": 2,
    "Raindrop": 2,
    "Todoist": 2,
    "Notion Calendar": 2,
    "Spotify": 3,
    "Discord": 3,
    "Obsidian": 4,
}

apps = config["apps"]
actual = {app["name"]: app["workspace"] for app in apps}
if actual != expected:
    raise SystemExit(f"unexpected Windows autostart mapping: {actual!r}")

if len(apps) != len(expected):
    raise SystemExit("Windows autostart apps must be unique")

for app in apps:
    if app["launch_type"] not in {"executable", "appx"}:
        raise SystemExit(f"unsupported launch type for {app['name']}")
    if not 0 <= app["delay_seconds"] <= 300:
        raise SystemExit(f"invalid delay for {app['name']}")

with komorebi_path.open(encoding="utf-8") as komorebi_file:
    komorebi = json.load(komorebi_file)

expected_executables = {
    "zen.exe": 1,
    "zotero.exe": 2,
    "Raindrop.io.exe": 2,
    "Todoist.exe": 2,
    "Notion Calendar.exe": 2,
    "Spotify.exe": 3,
    "Discord.exe": 3,
    "Obsidian.exe": 4,
}
actual_executables = {}
for index, workspace in enumerate(komorebi["monitors"][0]["workspaces"], start=1):
    for rule in workspace.get("initial_workspace_rules", []):
        if rule["id"] in expected_executables:
            actual_executables[rule["id"]] = index

if actual_executables != expected_executables:
    raise SystemExit(f"unexpected Komorebi app routing: {actual_executables!r}")
PY

module_path="$repo_root/windows/autostart/AppAutostart.psm1"
install_path="$repo_root/windows/autostart/install.ps1"
uninstall_path="$repo_root/windows/autostart/uninstall.ps1"

for path in "$module_path" "$install_path" "$uninstall_path"; do
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Windows autostart component: $path" >&2
    exit 1
  fi
done

rg -q 'Dotfiles App - ' "$module_path"
rg -q 'New-ScheduledTaskTrigger' "$module_path"
rg -q 'LogonType Interactive' "$module_path"
rg -q 'Register-ScheduledTask' "$module_path"
rg -q 'Unregister-ScheduledTask' "$module_path"

echo "Windows autostart tests passed"
