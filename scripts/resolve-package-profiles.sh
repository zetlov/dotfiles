#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <desktop|wsl> <minimal:0|1> <desktop|native|none> <nvidia:0|1> <tex:0|1>" >&2
    exit 2
fi

environment="$1"
minimal="$2"
backend="$3"
with_nvidia="$4"
with_tex="$5"

case "${environment}" in
    desktop|wsl) ;;
    *) echo "Environment must be desktop or wsl." >&2; exit 2 ;;
esac
case "${backend}" in
    desktop|native|none) ;;
    *) echo "Container backend must be resolved before selecting profiles." >&2; exit 2 ;;
esac
for flag in "${minimal}" "${with_nvidia}" "${with_tex}"; do
    case "${flag}" in
        0|1) ;;
        *) echo "Profile flags must be 0 or 1." >&2; exit 2 ;;
    esac
done

printf '%s\n' common.txt
if [ "${minimal}" -eq 0 ]; then
    printf '%s.txt\n' "${environment}"
fi
if [ "${backend}" = "native" ]; then
    printf '%s\n' container-native.txt
fi
if [ "${with_nvidia}" -eq 1 ]; then
    printf '%s\n' desktop-nvidia.txt
fi
if [ "${with_tex}" -eq 1 ]; then
    printf '%s\n' tex.txt
fi
