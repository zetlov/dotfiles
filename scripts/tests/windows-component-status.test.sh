#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd "${script_dir}/../.." && pwd)
root_readme="${repo_root}/README.md"
autostart_readme="${repo_root}/windows/autostart/README.md"

while IFS='|' read -r component lifecycle; do
  row="| ${component} | ${lifecycle} |"
  if ! rg -Fq "${row}" "${root_readme}"; then
    echo "FAIL: Windows component table is missing exact row: ${row}" >&2
    exit 1
  fi
done < <(jq -r '.components[] | [.name, .lifecycle] | join("|")' \
  "${repo_root}/windows/components.json")

if ! rg -qi 'rollback-only' "${autostart_readme}"; then
  echo "FAIL: Windows autostart must identify its rollback-only lifecycle" >&2
  exit 1
fi

if ! rg -q 'mise run check:all-local' "${root_readme}"; then
  echo "FAIL: README must expose the comprehensive local verification task" >&2
  exit 1
fi

for required_text in \
  'windows/install.ps1' \
  'windows/components.json' \
  '-ListComponents' \
  '-PlanOnly'; do
  if ! rg -Fq -- "${required_text}" "${root_readme}"; then
    echo "FAIL: README must document the Windows root orchestrator: ${required_text}" >&2
    exit 1
  fi
done

echo "Windows component status tests passed"
