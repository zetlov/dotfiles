#!/bin/bash

set -euo pipefail

if command -v awww-daemon >/dev/null 2>&1; then
    exec awww-daemon
fi

if command -v swww-daemon >/dev/null 2>&1; then
    exec swww-daemon
fi

echo "No wallpaper daemon found (expected awww-daemon or swww-daemon)" >&2
exit 127
