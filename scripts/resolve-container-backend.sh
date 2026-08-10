#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <desktop|wsl> <auto|desktop|native|none>" >&2
    exit 2
fi

environment="$1"
backend="$2"

case "${environment}" in
    desktop|wsl) ;;
    *) echo "Environment must be desktop or wsl." >&2; exit 2 ;;
esac
case "${backend}" in
    auto|desktop|native|none) ;;
    *) echo "Container backend must be auto, desktop, native, or none." >&2; exit 2 ;;
esac

if [ "${backend}" = "auto" ]; then
    if [ "${environment}" = "wsl" ]; then
        backend=desktop
    else
        backend=native
    fi
fi

if [ "${backend}" = "desktop" ] && [ "${environment}" != "wsl" ]; then
    echo "Docker Desktop backend is supported only in WSL." >&2
    exit 1
fi

printf '%s\n' "${backend}"
