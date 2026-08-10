#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
MISE_CONFIG="${REPO_ROOT}/mise.toml"

python3 - "${MISE_CONFIG}" <<'PY'
import pathlib
import sys
import tomllib


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


config_path = pathlib.Path(sys.argv[1])
with config_path.open("rb") as config_file:
    config = tomllib.load(config_file)

tasks = config.get("tasks", {})
expected_tasks = ("check:fast", "check:configs", "check:zebar", "check:windows")
missing_tasks = [task for task in expected_tasks if task not in tasks]
if missing_tasks:
    fail(f"root mise config is missing verification tasks: {', '.join(missing_tasks)}")

lint_command = str(tasks.get("lint", {}).get("run", ""))
if "git ls-files" not in lint_command:
    fail("shell lint should select tracked files with git ls-files")
if "find ." in lint_command:
    fail("shell lint should not scan untracked working-tree files with find")

configs_command = str(tasks["check:configs"].get("run", ""))
if "luac" not in configs_command or "jq" not in configs_command:
    fail("check:configs should validate both Lua and JSON syntax")
configs_tools = tasks["check:configs"].get("tools", {})
if configs_tools.get("lua") != "5.4.8":
    fail("check:configs should pin its task-local Lua runtime")

zebar_task = tasks["check:zebar"]
zebar_definition = " ".join(
    (
        str(zebar_task.get("run", "")),
        " ".join(str(item) for item in zebar_task.get("depends", [])),
        str(zebar_task.get("dir", "")),
    )
)
if "zebar" not in zebar_definition.lower():
    fail("check:zebar should delegate to the Zebar verification workflow")

windows_definition = str(tasks["check:windows"].get("run", ""))
if "Pester" not in windows_definition and "powershell" not in windows_definition.lower():
    fail("check:windows should run the Windows PowerShell verification workflow")
PY

echo "verification task tests passed"
