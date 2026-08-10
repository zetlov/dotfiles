#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [pacman-database]" >&2
    exit 2
fi

pacman_database="${1:-/var/lib/pacman/local}"
if [ -z "${pacman_database}" ] || [[ "${pacman_database}" != /* ]] \
    || [ ! -d "${pacman_database}" ]; then
    echo "Pacman database must be an existing absolute directory." >&2
    exit 1
fi

for description in "${pacman_database}"/*/desc; do
    if [ ! -f "${description}" ]; then
        continue
    fi
    package_name=$(awk '
        found { print; exit }
        $0 == "%NAME%" { found = 1 }
    ' "${description}")
    package_files="${description%/desc}/files"
    if { [ -f "${package_files}" ] \
        && grep -Eq '^usr/(sbin|bin)/(docker|dockerd)$' "${package_files}"; } \
        || [ "${package_name}" = "docker-compose" ]; then
        printf '%s\n' "${package_name}"
    fi
done
