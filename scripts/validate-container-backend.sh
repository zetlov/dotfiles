#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <desktop|wsl> <desktop|native|none> [pacman-database] [startup-timeout-seconds]" >&2
    exit 2
fi

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
environment="$1"
backend="$2"
pacman_database="${3:-/var/lib/pacman/local}"
startup_timeout_seconds="${4:-0}"

if [[ ! "${startup_timeout_seconds}" =~ ^[0-9]+$ ]]; then
    echo "Startup timeout must be a non-negative integer." >&2
    exit 2
fi

case "${environment}:${backend}" in
    desktop:native|desktop:none|wsl:desktop|wsl:native|wsl:none) ;;
    *) echo "Invalid environment and container backend combination." >&2; exit 2 ;;
esac

if [ "${backend}" != "desktop" ]; then
    exit 0
fi

native_packages=$("${SCRIPT_DIR}/find-native-container-packages.sh" \
    "${pacman_database}")
if [ -n "${native_packages}" ]; then
    echo "Distro-managed Docker packages conflict with Docker Desktop: ${native_packages//$'\n'/, }." >&2
    echo "Remove them before using Docker Desktop integration, or select --container-backend=native." >&2
    exit 1
fi

deadline=$((SECONDS + startup_timeout_seconds))
while ! command -v docker >/dev/null 2>&1 \
    || ! docker version >/dev/null 2>&1; do
    if [ "${SECONDS}" -ge "${deadline}" ]; then
        echo "Docker Desktop WSL integration is unavailable." >&2
        echo "Start Docker Desktop and enable WSL integration, or select --container-backend=native or none." >&2
        exit 1
    fi
    sleep 2
done
