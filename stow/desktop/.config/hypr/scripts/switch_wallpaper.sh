#!/bin/bash

set -euo pipefail

IMG="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zetshell"
WAL_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
CURRENT_WALLPAPER="$STATE_DIR/current-wallpaper"
STATE_FILE="$STATE_DIR/wallpapers.json"
THEME_JSON="$STATE_DIR/theme.json"
ADAPTER_SCRIPT="$HOME/.config/hypr/scripts/export_wal_theme.py"

backend_query() {
    if command -v awww >/dev/null 2>&1; then
        awww query >/dev/null 2>&1
        return
    fi

    if command -v swww >/dev/null 2>&1; then
        swww query >/dev/null 2>&1
        return
    fi

    return 127
}

backend_set() {
    if command -v awww >/dev/null 2>&1; then
        awww img "$IMG" \
            --transition-type grow \
            --transition-pos 0.8,0.9 \
            --transition-step 90 \
            --transition-fps 120
        return
    fi

    if command -v swww >/dev/null 2>&1; then
        swww img "$IMG" \
            --transition-type grow \
            --transition-pos 0.8,0.9 \
            --transition-step 90 \
            --transition-fps 120
        return
    fi

    echo "Error: no wallpaper backend found (expected awww or swww)" >&2
    return 127
}

if [ -z "$IMG" ]; then
    echo "Error: Specify image path!"
    exit 1
fi

if [ ! -f "$IMG" ]; then
    echo "Error: Wallpaper not found: $IMG"
    exit 1
fi

mkdir -p "$STATE_DIR"

ln -sfn "$IMG" "$CURRENT_WALLPAPER"

for _ in $(seq 1 40); do
    if backend_query; then
        break
    fi
    sleep 0.1
done

backend_set

if command -v wal >/dev/null 2>&1; then
    MODE="dark"
    if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
        MODE="$(jq -r '.mode // "dark"' "$STATE_FILE" 2>/dev/null || printf 'dark')"
    fi

    if [ "$MODE" = "light" ]; then
        wal -i "$IMG" -n -q -l
    else
        wal -i "$IMG" -n -q
    fi

    if [ -f "$WAL_CACHE_DIR/colors.json" ] && [ -x "$ADAPTER_SCRIPT" ]; then
        "$ADAPTER_SCRIPT" "$WAL_CACHE_DIR/colors.json" "$THEME_JSON" "$MODE"
        if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null 2>&1 || true
        fi
    fi
fi
