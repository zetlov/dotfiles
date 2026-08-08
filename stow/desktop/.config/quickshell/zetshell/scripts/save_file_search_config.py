#!/usr/bin/env python3

import json
import sys
from pathlib import Path


CONFIG_PATH = Path.home() / ".config" / "zetshell" / "file_search.json"
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


def normalize_string_list(values):
    if not isinstance(values, list):
        return []

    normalized = []
    seen = set()
    for value in values:
        text = str(value).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        normalized.append(text)
    return normalized


def normalize_extension_list(values):
    normalized = []
    seen = set()
    for value in normalize_string_list(values):
        text = value.lower()
        if not text.startswith("."):
            text = "." + text
        if text in seen:
            continue
        seen.add(text)
        normalized.append(text)
    return normalized


def normalize_config(payload):
    if not isinstance(payload, dict):
        raise ValueError("Config payload must be an object")

    roots = normalize_string_list(payload.get("roots"))
    exclude = normalize_string_list(payload.get("exclude"))
    exclude_extensions = normalize_extension_list(payload.get("excludeExtensions"))
    if not roots:
        raise ValueError("At least one root is required")

    include_quicklink_directories = payload.get("includeQuicklinkDirectories", DEFAULT_CONFIG["includeQuicklinkDirectories"])
    if not isinstance(include_quicklink_directories, bool):
        include_quicklink_directories = DEFAULT_CONFIG["includeQuicklinkDirectories"]

    max_items = payload.get("maxItems", DEFAULT_CONFIG["maxItems"])
    root_search_min_query = payload.get("rootSearchMinQuery", DEFAULT_CONFIG["rootSearchMinQuery"])
    try:
        max_items = int(max_items)
        root_search_min_query = int(root_search_min_query)
    except Exception as exc:
        raise ValueError("Numeric settings must be integers") from exc

    if max_items <= 0:
        raise ValueError("maxItems must be greater than 0")
    if root_search_min_query < 0:
        raise ValueError("rootSearchMinQuery must be 0 or greater")

    return {
        "roots": roots,
        "includeQuicklinkDirectories": include_quicklink_directories,
        "exclude": exclude,
        "excludeExtensions": exclude_extensions,
        "maxItems": max_items,
        "rootSearchMinQuery": root_search_min_query,
    }


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: save_file_search_config.py '<json>'")

    payload = json.loads(sys.argv[1])
    config = normalize_config(payload)
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(config, ensure_ascii=False))


if __name__ == "__main__":
    main()
