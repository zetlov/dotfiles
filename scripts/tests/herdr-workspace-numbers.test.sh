#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"
PLUGIN_SCRIPT="${ROOT_DIR}/scripts/herdr/numbered-workspaces/renumber.py"

if command -v python >/dev/null 2>&1; then
    python_command=(python)
elif command -v python3 >/dev/null 2>&1; then
    python_command=(python3)
elif command -v mise >/dev/null 2>&1; then
    python_command=(mise exec -- python)
else
    echo "FAIL: numbered-workspaces tests require Python 3" >&2
    exit 1
fi

"${python_command[@]}" - "${PLUGIN_SCRIPT}" <<'PY'
import importlib.util
import subprocess
import sys
import unittest
from unittest import mock


plugin_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("numbered_workspaces", plugin_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def workspace(workspace_id, repo_key=None, linked=None):
    value = {"workspace_id": workspace_id, "tokens": {}}
    if repo_key is not None:
        value["worktree"] = {
            "repo_key": repo_key,
            "is_linked_worktree": linked,
        }
    return value


class DisplayOrderTests(unittest.TestCase):
    def test_groups_linked_worktrees_beside_their_parent(self):
        workspaces = [
            workspace("parent", "repo", False),
            workspace("unrelated"),
            workspace("child-a", "repo", True),
            workspace("child-b", "repo", True),
        ]

        ordered = module.display_order(workspaces)

        self.assertEqual(
            [item["workspace_id"] for item in ordered],
            ["parent", "child-a", "child-b", "unrelated"],
        )

    def test_does_not_group_linked_worktrees_without_a_parent(self):
        workspaces = [
            workspace("child", "repo", True),
            workspace("unrelated"),
        ]

        self.assertEqual(module.display_order(workspaces), workspaces)

    def test_assigns_only_reachable_jump_numbers(self):
        workspaces = [workspace(f"w{index}") for index in range(1, 11)]

        assignments = module.number_assignments(workspaces)

        self.assertEqual(assignments[0], ("w1", "1"))
        self.assertEqual(assignments[8], ("w9", "9"))
        self.assertEqual(assignments[9], ("w10", None))


class HerdrResponseTests(unittest.TestCase):
    def test_retries_a_transient_empty_response(self):
        responses = [
            subprocess.CompletedProcess([], 0, stdout="", stderr=""),
            subprocess.CompletedProcess(
                [],
                0,
                stdout='{"result":{"workspaces":[]}}',
                stderr="",
            ),
        ]

        with mock.patch.object(module.subprocess, "run", side_effect=responses) as run:
            result = module.run_herdr(["workspace", "list"])

        self.assertEqual(result, {"workspaces": []})
        self.assertEqual(run.call_count, 2)


unittest.main(argv=[sys.argv[0]])
PY

printf 'Herdr workspace numbering tests passed.\n'
