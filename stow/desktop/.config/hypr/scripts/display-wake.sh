#!/usr/bin/env bash
set -euo pipefail

wake_output() {
    hyprctl dispatch dpms on "$@" >/dev/null || true
}

# Some monitors need a little time to renegotiate the link after DPMS wake.
# Retry both globally and per output to avoid requiring a cable hotplug.
for delay in 0 0.5 1; do
    sleep "$delay"
    wake_output

    mapfile -t monitors < <(hyprctl -j monitors 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
    for monitor in "${monitors[@]}"; do
        [ -n "$monitor" ] || continue
        wake_output "$monitor"
    done
done
