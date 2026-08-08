#!/bin/bash

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zetshell"
CURRENT_WALLPAPER="$STATE_DIR/current-wallpaper"
WALL_DIR="${WALLPAPER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers}"
FALLBACK_WALLPAPER="${FALLBACK_WALLPAPER:-$WALL_DIR/default.jpg}"

if [ -L "$CURRENT_WALLPAPER" ] || [ -f "$CURRENT_WALLPAPER" ]; then
    TARGET="$(readlink -f "$CURRENT_WALLPAPER")"
else
    TARGET="$FALLBACK_WALLPAPER"
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
    exit 0
fi

"$HOME/.config/hypr/scripts/switch_wallpaper.sh" "$TARGET"
