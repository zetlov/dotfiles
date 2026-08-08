#!/usr/bin/env python3

import json
import os
import re
from pathlib import Path


HOME = Path.home()
QUICKLINKS_PATH = HOME / ".config" / "zetshell" / "quicklinks.json"
FILE_SEARCH_CONFIG_PATH = HOME / ".config" / "zetshell" / "file_search.json"
DEFAULT_CONFIG = {
    "roots": [
        "~/Desktop",
        "~/Documents",
        "~/Downloads",
    ],
    "includeQuicklinkDirectories": True,
    "exclude": [
        ".git",
        ".cache",
        ".direnv",
        ".next",
        ".nuxt",
        ".pytest_cache",
        ".mypy_cache",
        "__pycache__",
        "node_modules",
        ".venv",
        "venv",
        "build",
        "dist",
        "target",
    ],
    "excludeExtensions": [],
    "maxItems": 15000,
    "rootSearchMinQuery": 2,
}


def normalize_extension(value: str) -> str:
    text = str(value).strip().lower()
    if not text:
        return ""
    if not text.startswith("."):
        text = "." + text
    return text


def normalize_path(path: Path) -> str:
    try:
        return str(path.resolve())
    except OSError:
        return str(path)


def load_config() -> dict:
    config = dict(DEFAULT_CONFIG)
    if not FILE_SEARCH_CONFIG_PATH.exists():
        return config

    try:
        payload = json.loads(FILE_SEARCH_CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception:
        return config

    if not isinstance(payload, dict):
        return config

    roots = payload.get("roots")
    if isinstance(roots, list):
        config["roots"] = [str(value) for value in roots if isinstance(value, str) and value.strip()]

    include_quicklink_directories = payload.get("includeQuicklinkDirectories")
    if isinstance(include_quicklink_directories, bool):
        config["includeQuicklinkDirectories"] = include_quicklink_directories

    exclude = payload.get("exclude")
    if isinstance(exclude, list):
        config["exclude"] = [str(value) for value in exclude if isinstance(value, str) and value.strip()]

    exclude_extensions = payload.get("excludeExtensions")
    if isinstance(exclude_extensions, list):
        normalized = []
        seen = set()
        for value in exclude_extensions:
            if not isinstance(value, str):
                continue
            extension = normalize_extension(value)
            if not extension or extension in seen:
                continue
            seen.add(extension)
            normalized.append(extension)
        config["excludeExtensions"] = normalized

    max_items = payload.get("maxItems")
    if isinstance(max_items, int) and max_items > 0:
        config["maxItems"] = max_items

    root_search_min_query = payload.get("rootSearchMinQuery")
    if isinstance(root_search_min_query, int) and root_search_min_query >= 0:
        config["rootSearchMinQuery"] = root_search_min_query

    return config


def load_roots(config: dict) -> list[Path]:
    roots: list[Path] = []
    seen: set[str] = set()

    def add_root(path: Path) -> None:
        if not path.exists() or not path.is_dir():
            return
        normalized = normalize_path(path)
        if normalized in seen:
            return
        seen.add(normalized)
        roots.append(path)

    for raw_path in config["roots"]:
        add_root(Path(os.path.expanduser(raw_path)))

    if config["includeQuicklinkDirectories"] and QUICKLINKS_PATH.exists():
        try:
            payload = json.loads(QUICKLINKS_PATH.read_text(encoding="utf-8"))
        except Exception:
            payload = []
        if isinstance(payload, list):
            for item in payload:
                if not isinstance(item, dict):
                    continue
                raw = item.get("url") or item.get("path")
                if not raw or not isinstance(raw, str):
                    continue
                path = Path(os.path.expanduser(raw))
                if path.is_dir():
                    add_root(path)

    return roots


def tokenize(parts: list[str]) -> list[str]:
    tokens: set[str] = set()
    for part in parts:
        for token in re.findall(r"[a-z0-9]+", part.lower()):
            if len(token) >= 2:
                tokens.add(token)
    return sorted(tokens)


def display_path(path: Path) -> str:
    text = str(path)
    home_prefix = str(HOME)
    if text == home_prefix:
        return "~"
    if text.startswith(home_prefix + os.sep):
        return "~/" + text[len(home_prefix) + 1 :]
    return text


def main() -> None:
    config = load_config()
    roots = load_roots(config)
    excluded_dirs = set(config["exclude"])
    excluded_extensions = set(config["excludeExtensions"])
    max_items = int(config["maxItems"])
    items = []

    for root in roots:
        try:
            root_resolved = root.resolve()
        except OSError:
            root_resolved = root

        for current_root, dirnames, filenames in os.walk(root_resolved, topdown=True, followlinks=False):
            dirnames[:] = [
                dirname
                for dirname in dirnames
                if dirname not in excluded_dirs
            ]
            current_path = Path(current_root)
            dir_entries = sorted(dirnames)
            file_entries = sorted(filenames)

            for dirname in dir_entries:
                path = current_path / dirname
                relative = path.relative_to(root_resolved)
                items.append({
                    "path": str(path),
                    "name": dirname,
                    "relativePath": str(relative),
                    "parentPath": str(path.parent),
                    "displayPath": display_path(path),
                    "isDirectory": True,
                    "keywords": tokenize([dirname, str(relative), str(path.parent)]),
                })
                if len(items) >= max_items:
                    print(json.dumps(items, ensure_ascii=False))
                    return

            for filename in file_entries:
                path = current_path / filename
                if path.suffix.lower() in excluded_extensions:
                    continue
                relative = path.relative_to(root_resolved)
                items.append({
                    "path": str(path),
                    "name": filename,
                    "relativePath": str(relative),
                    "parentPath": str(path.parent),
                    "displayPath": display_path(path),
                    "isDirectory": False,
                    "keywords": tokenize([filename, str(relative), str(path.parent)]),
                })
                if len(items) >= max_items:
                    print(json.dumps(items, ensure_ascii=False))
                    return

    print(json.dumps(items, ensure_ascii=False))


if __name__ == "__main__":
    main()
