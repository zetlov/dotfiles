#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/user-home"
printf 'No missing TeX files.\n' > "${TEST_ROOT}/empty.log"
mkdir -p "${TEST_ROOT}/dotfiles/packages"
printf 'texlive-meta\n' > "${TEST_ROOT}/dotfiles/packages/tex.txt"

cat > "${TEST_ROOT}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
echo "FAIL: dry-run invoked sudo" >&2
exit 99
STUB
chmod +x "${TEST_ROOT}/bin/sudo"

cat > "${TEST_ROOT}/bin/pacman" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-Fq" ]; then
    printf 'texlive-example\n'
fi
STUB
chmod +x "${TEST_ROOT}/bin/pacman"

HOME="${TEST_ROOT}/user-home" DOTFILES_DIR="${TEST_ROOT}/dotfiles" \
    PATH="${TEST_ROOT}/bin:/usr/bin:/bin" \
    "${REPO_ROOT}/scripts/tex-install-missing.sh" \
    --from-log "${TEST_ROOT}/empty.log" --dry-run >/dev/null

if [ -e "${TEST_ROOT}/user-home/.cache/tex-install-missing.fy" ]; then
    echo "FAIL: dry-run must not update the pacman files database marker" >&2
    exit 1
fi

printf "LaTeX Error: File \`example.sty' not found\n" > "${TEST_ROOT}/missing.log"
before_hash=$(sha256sum "${TEST_ROOT}/dotfiles/packages/tex.txt" | awk '{print $1}')
HOME="${TEST_ROOT}/user-home" DOTFILES_DIR="${TEST_ROOT}/dotfiles" \
    PATH="${TEST_ROOT}/bin:/usr/bin:/bin" \
    "${REPO_ROOT}/scripts/tex-install-missing.sh" \
    --from-log "${TEST_ROOT}/missing.log" --dry-run --update-list --yes >/dev/null
after_hash=$(sha256sum "${TEST_ROOT}/dotfiles/packages/tex.txt" | awk '{print $1}')

if [ "${before_hash}" != "${after_hash}" ]; then
    echo "FAIL: --dry-run --update-list must not modify packages/tex.txt" >&2
    exit 1
fi

echo "tex dry-run tests passed"
