#!/usr/bin/env python3

"""Publish workspace numbers in Herdr's visible sidebar order."""

from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from typing import Any


MAX_SHORTCUT_NUMBER = 9
RESPONSE_ATTEMPTS = 3
RESPONSE_RETRY_SECONDS = 0.05
TOKEN_NAME = "num"
TOKEN_SOURCE = "dotfiles.numbered-workspaces"


def display_order(workspaces: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Reproduce Herdr's expanded worktree-group ordering."""
    members_by_key: dict[str, list[dict[str, Any]]] = {}
    for workspace in workspaces:
        worktree = workspace.get("worktree")
        if isinstance(worktree, dict) and isinstance(worktree.get("repo_key"), str):
            members_by_key.setdefault(worktree["repo_key"], []).append(workspace)

    grouped_keys = {
        key
        for key, members in members_by_key.items()
        if len(members) >= 2
        and any(
            member.get("worktree", {}).get("is_linked_worktree") is False
            for member in members
        )
    }
    emitted_keys: set[str] = set()
    ordered: list[dict[str, Any]] = []

    for workspace in workspaces:
        worktree = workspace.get("worktree")
        key = worktree.get("repo_key") if isinstance(worktree, dict) else None
        if key not in grouped_keys:
            ordered.append(workspace)
            continue
        if key in emitted_keys:
            continue

        emitted_keys.add(key)
        members = members_by_key[key]
        parent = next(
            member
            for member in members
            if member["worktree"].get("is_linked_worktree") is False
        )
        ordered.extend([parent, *(member for member in members if member is not parent)])

    return ordered


def number_assignments(
    workspaces: list[dict[str, Any]],
) -> list[tuple[str, str | None]]:
    """Return visible workspace IDs and their reachable shortcut numbers."""
    return [
        (
            workspace["workspace_id"],
            str(index) if index <= MAX_SHORTCUT_NUMBER else None,
        )
        for index, workspace in enumerate(display_order(workspaces), start=1)
    ]


def run_herdr(arguments: list[str]) -> dict[str, Any]:
    executable = os.environ.get("HERDR_BIN_PATH", "herdr")
    invalid_response: Exception | None = None
    for attempt in range(RESPONSE_ATTEMPTS):
        completed = subprocess.run(
            [executable, *arguments],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "no error output"
            raise RuntimeError(f"herdr {' '.join(arguments)} failed: {detail}")
        try:
            response = json.loads(completed.stdout)
            result = response["result"]
            if not isinstance(result, dict):
                raise TypeError("result is not an object")
            return result
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            invalid_response = error
            if attempt + 1 < RESPONSE_ATTEMPTS:
                time.sleep(RESPONSE_RETRY_SECONDS)

    raise RuntimeError("Herdr returned an invalid JSON response") from invalid_response


def synchronize() -> None:
    result = run_herdr(["workspace", "list"])
    workspaces = result.get("workspaces")
    if not isinstance(workspaces, list):
        raise RuntimeError("Herdr workspace list has no workspaces array")

    by_id = {workspace["workspace_id"]: workspace for workspace in workspaces}
    for workspace_id, number in number_assignments(workspaces):
        workspace = by_id[workspace_id]
        current = workspace.get("tokens", {}).get(TOKEN_NAME)
        if current == number:
            continue
        arguments = [
            "workspace",
            "report-metadata",
            workspace_id,
            "--source",
            TOKEN_SOURCE,
        ]
        if number is None:
            arguments.extend(["--clear-token", TOKEN_NAME])
        else:
            arguments.extend(["--token", f"{TOKEN_NAME}={number}"])
        run_herdr(arguments)


def main() -> int:
    state_directory = Path(
        os.environ.get("HERDR_PLUGIN_STATE_DIR", tempfile.gettempdir())
    )
    state_directory.mkdir(parents=True, exist_ok=True)
    with (state_directory / "renumber.lock").open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        synchronize()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"numbered-workspaces: {error}", file=sys.stderr)
        raise SystemExit(1) from error
