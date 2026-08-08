#!/usr/bin/env bash

set -euo pipefail

action="${1:-}"
mode="${2:-}"
destination="${3:-clipboard}"
selection="${4:-}"

# shellcheck disable=SC1091
source "$HOME/.config/hypr/scripts/load_zetshell_settings.sh"

SCREENSHOT_DIR="$ZETSHELL_SCREENSHOT_DIR"

ensure_deps() {
    local missing=()
    local dep

    for dep in grim wl-copy hyprctl jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ "$mode" == "region" || "$mode" == "window" ]]; then
        if ! command -v slurp >/dev/null 2>&1; then
            missing+=("slurp")
        fi
    fi

    if ((${#missing[@]} > 0)); then
        printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
        exit 1
    fi
}

timestamped_path() {
    mkdir -p "$SCREENSHOT_DIR"
    printf '%s/screenshot_%s.png\n' "$SCREENSHOT_DIR" "$(date +%Y%m%d_%H%M%S)"
}

region_geometry() {
    if [[ -n "$selection" ]]; then
        printf '%s\n' "$selection"
        return
    fi

    slurp -f '%x,%y %wx%h' || {
        echo "Selection cancelled" >&2
        exit 1
    }
}

window_geometry() {
    if [[ -n "$selection" ]]; then
        printf '%s\n' "$selection"
        return
    fi

    local selection

    selection="$(
        hyprctl -j clients |
            jq -r '
                map(select(.mapped == true and .hidden == false and .workspace.id >= 0 and (.size[0] > 0 and .size[1] > 0)))
                | .[]
                | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1]) \(.class) :: \(.title)"
            ' |
            slurp -r -f '%x,%y %wx%h'
    )" || {
        echo "Window selection cancelled" >&2
        exit 1
    }

    printf '%s\n' "$selection"
}

focused_output() {
    local monitor

    monitor="$(hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name' | head -n 1)"
    [[ -n "$monitor" ]] || {
        echo "Could not determine focused output" >&2
        exit 1
    }

    printf '%s\n' "$monitor"
}

capture_to_file() {
    local file_path="$1"

    case "$mode" in
        region)
            grim -g "$(region_geometry)" "$file_path"
            ;;
        window)
            grim -g "$(window_geometry)" "$file_path"
            ;;
        output)
            grim -o "$(focused_output)" "$file_path"
            ;;
        *)
            echo "Unsupported screenshot mode: $mode" >&2
            exit 2
            ;;
    esac
}

case "$action" in
    screenshot)
        ensure_deps

        if [[ "$destination" == "clipboard" ]]; then
            tmp_path="$(mktemp --suffix=.png)"
            trap 'rm -f "$tmp_path"' EXIT
            capture_to_file "$tmp_path"
            wl-copy --type image/png <"$tmp_path"
            echo "Captured $mode to clipboard"
            exit 0
        fi

        screenshot_path="$(timestamped_path)"
        capture_to_file "$screenshot_path"

        if command -v swappy >/dev/null 2>&1; then
            setsid -f swappy -f "$screenshot_path" >/dev/null 2>&1 || true
            echo "Saved $mode to $screenshot_path and opened swappy"
        else
            echo "Saved $mode to $screenshot_path"
        fi
        ;;
    *)
        echo "Usage: $0 screenshot <region|window|output> <clipboard|save> [geometry]" >&2
        exit 2
        ;;
esac
