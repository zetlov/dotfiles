#!/usr/bin/env bash
set -euo pipefail

repo_root=$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)
config_path="$repo_root/windows/glazewm/startup-apps.json"
script_path="$repo_root/windows/glazewm/Start-GlazeWorkspaceApps.ps1"
module_path="$repo_root/windows/glazewm/GlazeWMAutoTile.psm1"

python3 - "$config_path" "$script_path" "$module_path" <<'PY'
import json
import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1])
script_path = pathlib.Path(sys.argv[2])
module_path = pathlib.Path(sys.argv[3])

with config_path.open(encoding="utf-8") as config_file:
    config = json.load(config_file)

applications = config["applications"]
for app in applications:
    launch_type = app.get("launchType", "start-app")
    if launch_type == "executable":
        if not app.get("pathCandidates"):
            raise SystemExit(f"missing executable path candidates for {app['name']}")
    elif launch_type == "start-app":
        if not app.get("startAppName"):
            raise SystemExit(f"missing Start Apps name for {app['name']}")
    else:
        raise SystemExit(f"unsupported launch type for {app['name']}: {launch_type}")

script = script_path.read_text(encoding="utf-8")
optional_properties = (
    "arguments",
    "launchType",
    "pathCandidates",
    "processCommandLinePattern",
    "startAppName",
    "startupWorkspace",
)
for property_name in optional_properties:
    direct_access = re.search(rf"\$app\.{re.escape(property_name)}\b", script)
    if direct_access:
        raise SystemExit(
            f"unsafe StrictMode access to optional property: {property_name}"
        )

placement = script.split("foreach ($entry in $launchedApplications)", 1)[1]
profile_guard = (
    "if (-not [string]::IsNullOrWhiteSpace($processCommandLinePattern))"
)
if profile_guard not in placement:
    raise SystemExit("startup placement must resolve PIDs only for profiled apps")

module = module_path.read_text(encoding="utf-8")
if "Get-GlazeWindowProcessId" not in module:
    raise SystemExit("startup placement must resolve missing process IDs by handle")
if "-Window $window" not in module:
    raise SystemExit("startup placement must use the window process ID resolver")
PY

echo "GlazeWM startup application tests passed"
