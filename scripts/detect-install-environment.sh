#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [kernel-osrelease-file]" >&2
    exit 2
fi

osrelease_file="${1:-/proc/sys/kernel/osrelease}"
if [ ! -r "${osrelease_file}" ]; then
    echo "Cannot read kernel release evidence: ${osrelease_file}" >&2
    exit 1
fi

if grep -qiE '(microsoft|wsl)' "${osrelease_file}"; then
    printf '%s\n' wsl
else
    printf '%s\n' desktop
fi
