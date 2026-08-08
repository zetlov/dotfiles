#!/usr/bin/env bash

set -euo pipefail

LIMIT="${CLIPBOARD_LIMIT:-120}"

find_entry() {
    local wanted="$1"
    cliphist list | awk -F '\t' -v wanted="$wanted" '$1 == wanted && !found { print; found = 1 }'
}

list_entries() {
    cliphist list | head -n "$LIMIT" | jq -R -s '
        split("\n")
        | map(select(length > 0))
        | map(
            capture("^(?<id>[^\t]+)\t(?<preview>.*)$")
            | .kind = (if (.preview | startswith("[[ binary data")) then "image" else "text" end)
            | .title = (
                if .kind == "image" then
                    "Image"
                else
                    (.preview | gsub("\\s+"; " ") | if length > 96 then .[:96] + "…" else . end)
                end
            )
            | .subtitle = (
                if .kind == "image" then .preview else "Clipboard history" end
            )
            | .id = (.id | tonumber)
        )
    '
}

copy_entry() {
    local entry
    local entry_file
    local tmp
    entry="$(find_entry "$1")"
    [[ -n "$entry" ]] || {
        echo "Clipboard entry not found: $1" >&2
        exit 1
    }

    entry_file="$(mktemp)"
    tmp="$(mktemp)"
    trap 'rm -f "$entry_file" "$tmp"' RETURN

    printf '%s\n' "$entry" >"$entry_file"
    cliphist decode <"$entry_file" >"$tmp"
    wl-copy <"$tmp"
    echo "Copied clipboard entry $1"
}

delete_entry() {
    local entry
    entry="$(find_entry "$1")"
    [[ -n "$entry" ]] || {
        echo "Clipboard entry not found: $1" >&2
        exit 1
    }

    printf '%s\n' "$entry" | cliphist delete
    echo "Deleted clipboard entry $1"
}

case "${1:-list}" in
    list)
        list_entries
        ;;
    copy)
        copy_entry "${2:-}"
        ;;
    delete)
        delete_entry "${2:-}"
        ;;
    *)
        echo "Usage: $0 {list|copy|delete}" >&2
        exit 2
        ;;
esac
