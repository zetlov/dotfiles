#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <desktop|wsl> <architecture> <with-nvidia:0|1> <minimal:0|1>" >&2
    exit 2
fi

environment="$1"
architecture="$2"
with_nvidia="$3"
minimal="$4"

case "${environment}" in
    desktop|wsl) ;;
    *) echo "Environment must be desktop or wsl." >&2; exit 2 ;;
esac
case "${with_nvidia}:${minimal}" in
    0:0|0:1|1:0|1:1) ;;
    *) echo "Profile flags must be 0 or 1." >&2; exit 2 ;;
esac

if [ "${environment}" = "desktop" ] && [ "${architecture}" != "x86_64" ]; then
    echo "The native ARM full bootstrap is not supported; use --link-only." >&2
    exit 1
fi
if [ "${with_nvidia}" -eq 1 ] \
    && { [ "${environment}" != "desktop" ] || [ "${architecture}" != "x86_64" ]; }; then
    echo "--with-nvidia is supported only on native x86_64 desktops." >&2
    exit 1
fi
if [ "${with_nvidia}" -eq 1 ] && [ "${minimal}" -eq 1 ]; then
    echo "--with-nvidia cannot be combined with --minimal." >&2
    exit 1
fi
