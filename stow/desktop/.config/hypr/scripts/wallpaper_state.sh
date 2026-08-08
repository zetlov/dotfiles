#!/bin/bash

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zetshell"
STATE_FILE="$STATE_DIR/wallpapers.json"
CURRENT_WALLPAPER="$STATE_DIR/current-wallpaper"
WALL_DIR="${WALLPAPER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers}"
RECENT_LIMIT=12
DEFAULT_MODE="dark"

ensure_state() {
    mkdir -p "$STATE_DIR"
    if [ ! -f "$STATE_FILE" ]; then
        printf '%s\n' "{\"favorites\":[],\"recent\":[],\"mode\":\"$DEFAULT_MODE\"}" > "$STATE_FILE"
    fi
}

current_mode() {
    ensure_state
    jq -r --arg default_mode "$DEFAULT_MODE" '.mode // $default_mode' "$STATE_FILE"
}

current_path() {
    if [ -L "$CURRENT_WALLPAPER" ] || [ -f "$CURRENT_WALLPAPER" ]; then
        readlink -f "$CURRENT_WALLPAPER" 2>/dev/null || true
    fi
}

list_wallpapers() {
    ensure_state

    local current
    current="$(current_path)"

    local files_json
    if [ -d "$WALL_DIR" ]; then
        files_json="$(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort | jq -R -s 'split("\n")[:-1]')"
    else
        files_json='[]'
    fi

    local favorites_json
    favorites_json="$(jq -c '.favorites // []' "$STATE_FILE" 2>/dev/null || printf '[]')"

    local recent_json
    recent_json="$(jq -c '.recent // []' "$STATE_FILE" 2>/dev/null || printf '[]')"

    local mode
    mode="$(current_mode)"

    jq -n \
        --arg current "$current" \
        --arg mode "$mode" \
        --argjson files "$files_json" \
        --argjson favorites "$favorites_json" \
        --argjson recent "$recent_json" '
        {
          currentPath: $current,
          currentName: (if $current == "" then "" else ($current | split("/") | last) end),
          mode: $mode,
          favorites: $favorites,
          recent: $recent,
          wallpapers: (
            $files
            | map(
                . as $path
                | {
                    path: $path,
                    name: ($path | split("/") | last),
                    current: $path == $current,
                    favorite: ($favorites | index($path) != null),
                    recent: ($recent | index($path) != null),
                    recentIndex: (($recent | index($path)) // 9999)
                  }
              )
            | sort_by(
                (if .current then 0 elif .recent then 1 elif .favorite then 2 else 3 end),
                .recentIndex,
                .name
              )
            | map(del(.recentIndex))
          )
        }'
}

update_recent() {
    ensure_state
    local path="$1"
    local temp
    temp="$(mktemp)"
    jq --arg path "$path" --argjson limit "$RECENT_LIMIT" '
        .favorites = (.favorites // []) |
        .recent = (([$path] + ((.recent // []) | map(select(. != $path))))[:$limit]) |
        .mode = (.mode // "dark")
    ' "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"
}

toggle_favorite() {
    ensure_state
    local path="$1"
    local temp
    temp="$(mktemp)"
    jq --arg path "$path" '
        .favorites = (.favorites // []) |
        .recent = (.recent // []) |
        .mode = (.mode // "dark") |
        if (.favorites | index($path)) == null then
            .favorites += [$path]
        else
            .favorites |= map(select(. != $path))
        end
    ' "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"
}

set_mode() {
    ensure_state
    local mode="${1:-}"
    if [ "$mode" != "dark" ] && [ "$mode" != "light" ]; then
        echo "Unsupported mode: $mode" >&2
        exit 1
    fi

    local temp
    temp="$(mktemp)"
    jq --arg mode "$mode" '
        .favorites = (.favorites // []) |
        .recent = (.recent // []) |
        .mode = $mode
    ' "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"

    local current
    current="$(current_path)"
    if [ -n "$current" ] && [ -f "$current" ]; then
        "$HOME/.config/hypr/scripts/switch_wallpaper.sh" "$current"
    fi
}

apply_wallpaper() {
    local path="$1"

    if [ ! -f "$path" ]; then
        echo "Wallpaper not found: $path" >&2
        exit 1
    fi

    "$HOME/.config/hypr/scripts/switch_wallpaper.sh" "$path"
    update_recent "$path"
}

command="${1:-list}"

case "$command" in
    list)
        list_wallpapers
        ;;
    apply)
        apply_wallpaper "${2:-}"
        ;;
    toggle-favorite)
        toggle_favorite "${2:-}"
        ;;
    set-mode)
        set_mode "${2:-}"
        ;;
    *)
        echo "Unknown command: $command" >&2
        exit 1
        ;;
esac
