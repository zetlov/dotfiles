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
if [ -n "${TEX_TEST_CALLS:-}" ]; then
    printf 'sudo\n' >> "$TEX_TEST_CALLS"
fi
echo "FAIL: dry-run invoked sudo" >&2
exit 99
STUB
chmod +x "${TEST_ROOT}/bin/sudo"

cat > "${TEST_ROOT}/bin/pacman" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-Fq" ]; then
    printf 'extra/texlive-example\nextra/unrelated-package\n'
    if [ "${TEX_TEST_MULTIPLE:-0}" = 1 ]; then
        printf 'extra/texlive-other\n'
    fi
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
    --from-log "${TEST_ROOT}/missing.log" --dry-run --update-list --yes \
    > "${TEST_ROOT}/missing.stdout"
after_hash=$(sha256sum "${TEST_ROOT}/dotfiles/packages/tex.txt" | awk '{print $1}')

if ! grep -qxF '[tex-install] [dry-run] would install: texlive-example' \
    "${TEST_ROOT}/missing.stdout"; then
    echo "FAIL: repository-qualified file owners must resolve to TeX packages" >&2
    exit 1
fi

if [ "${before_hash}" != "${after_hash}" ]; then
    echo "FAIL: --dry-run --update-list must not modify packages/tex.txt" >&2
    exit 1
fi

# Invalid arguments must fail before database sync or compilation.
assert_invalid_input() {
    local expected="$1"
    shift
    local status=0
    HOME="${TEST_ROOT}/user-home" DOTFILES_DIR="${TEST_ROOT}/dotfiles" \
        XDG_CACHE_HOME="${TEST_ROOT}/cache" TEX_TEST_CALLS="${TEST_ROOT}/calls" \
        PATH="${TEST_ROOT}/bin:/usr/bin:/bin" \
        "${REPO_ROOT}/scripts/tex-install-missing.sh" "$@" \
        > "${TEST_ROOT}/invalid.stdout" 2>&1 || status=$?
    if [ "$status" -eq 0 ] || ! grep -qF "$expected" "${TEST_ROOT}/invalid.stdout"; then
        echo "FAIL: invalid input must fail with diagnostic: $expected" >&2
        cat "${TEST_ROOT}/invalid.stdout" >&2
        exit 1
    fi
    if [ -e "${TEST_ROOT}/calls" ] || [ -e "${TEST_ROOT}/cache" ]; then
        echo "FAIL: invalid input must not sync the database or create cache state" >&2
        exit 1
    fi
}

assert_invalid_input 'requires a log file path' --from-log
assert_invalid_input 'requires a log file path' --from-log --yes
assert_invalid_input 'requires a log file path' --from-log ''
assert_invalid_input 'not a readable regular file' --from-log "${TEST_ROOT}/absent.log"
assert_invalid_input 'not a readable regular file' --from-log "${TEST_ROOT}"
assert_invalid_input 'not a readable regular file' "${TEST_ROOT}/absent.tex"
assert_invalid_input 'specify only one input' "${TEST_ROOT}/empty.log" "${TEST_ROOT}/missing.log"
assert_invalid_input 'specify only one input' --from-log "${TEST_ROOT}/empty.log" --from-log "${TEST_ROOT}/missing.log"
assert_invalid_input 'specify only one input' "${TEST_ROOT}/empty.log" --from-log "${TEST_ROOT}/missing.log"

# Give interactive selection a controlling terminal without running installers.
assert_choice() {
    local choice="$1" expected="${2:-}"
    printf '%s\n' "$choice" | \
        HOME="${TEST_ROOT}/user-home" DOTFILES_DIR="${TEST_ROOT}/dotfiles" \
        PATH="${TEST_ROOT}/bin:/usr/bin:/bin" TEX_TEST_MULTIPLE=1 \
        TEX_TEST_SCRIPT="${REPO_ROOT}/scripts/tex-install-missing.sh" \
        TEX_TEST_LOG="${TEST_ROOT}/missing.log" \
        script -q -e -c '"$TEX_TEST_SCRIPT" --from-log "$TEX_TEST_LOG" --dry-run' /dev/null \
        > "${TEST_ROOT}/choice.stdout"
    if [ -n "$expected" ]; then
        if ! grep -qF "[dry-run] would install: $expected" "${TEST_ROOT}/choice.stdout"; then
            echo "FAIL: valid choice must select $expected" >&2
            exit 1
        fi
    elif grep -qF '[dry-run] would install:' "${TEST_ROOT}/choice.stdout"; then
        echo "FAIL: invalid or empty choice must not select a package" >&2
        exit 1
    fi
}

assert_choice '1' texlive-example
assert_choice '2' texlive-other
assert_choice ''
assert_choice '0'
assert_choice '-1'
assert_choice '3'
assert_choice '99999999999999999999999999999999999999999999'
assert_choice '1+1'
assert_choice "opts[\$(touch ${TEST_ROOT}/injected)]"
if [ -e "${TEST_ROOT}/injected" ]; then
    echo "FAIL: interactive choice executed shell code" >&2
    exit 1
fi

# Build decisions must reflect this invocation, including its exit status.
cat > "${TEST_ROOT}/bin/latexmk" <<'STUB'
#!/usr/bin/env bash
set -eu
case "$TEX_TEST_BUILD_MODE" in
    success)
        printf 'Latexmk: All targets (paper.pdf) are up-to-date\n'
        ;;
    failure)
        printf 'Latexmk: Getting log file paper.log\n'
        printf 'Undefined control sequence.\n' >&2
        exit 12
        ;;
    cached)
        rebuild=0
        for arg in "$@"; do
            if [ "$arg" = -g ]; then
                rebuild=1
            fi
        done
        if [ "$rebuild" -eq 1 ]; then
            printf "LaTeX Error: File \`example.sty' not found\n" >&2
        else
            printf 'Latexmk: Nothing to do\n'
            printf 'pdflatex: gave an error in previous invocation of latexmk.\n' >&2
        fi
        exit 12
        ;;
    cap|recover)
        count=0
        if [ -f "$TEX_TEST_BUILD_COUNT" ]; then
            read -r count < "$TEX_TEST_BUILD_COUNT"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$TEX_TEST_BUILD_COUNT"
        if [ "$TEX_TEST_BUILD_MODE" = recover ] && [ "$count" -gt 1 ]; then
            printf 'Latexmk: All targets (paper.pdf) are up-to-date\n'
            exit 0
        fi
        printf "LaTeX Error: File \`example%s.sty' not found\n" "$count" >&2
        exit 12
        ;;
esac
STUB
chmod +x "${TEST_ROOT}/bin/latexmk"
printf '\\documentclass{article}\n' > "${TEST_ROOT}/paper.tex"
cp "${TEST_ROOT}/missing.log" "${TEST_ROOT}/paper.log"

assert_build() {
    local mode="$1" expected_status="$2" status=0
    rm -f -- "${TEST_ROOT}/build-count"
    HOME="${TEST_ROOT}/user-home" DOTFILES_DIR="${TEST_ROOT}/dotfiles" \
        PATH="${TEST_ROOT}/bin:/usr/bin:/bin" TEX_TEST_BUILD_MODE="$mode" \
        TEX_TEST_BUILD_COUNT="${TEST_ROOT}/build-count" \
        "${REPO_ROOT}/scripts/tex-install-missing.sh" "${TEST_ROOT}/paper.tex" \
        --dry-run --yes > "${TEST_ROOT}/build.stdout" 2>&1 || status=$?
    if [ "$status" -ne "$expected_status" ]; then
        echo "FAIL: $mode build returned $status instead of $expected_status" >&2
        cat "${TEST_ROOT}/build.stdout" >&2
        exit 1
    fi
}

assert_build success 0
if grep -qF '[dry-run] would install:' "${TEST_ROOT}/build.stdout"; then
    echo "FAIL: stale log must not trigger package installation after successful build" >&2
    exit 1
fi
assert_build failure 12
if ! grep -qF 'Undefined control sequence.' "${TEST_ROOT}/build.stdout"; then
    echo "FAIL: failed build must report compiler diagnostics" >&2
    exit 1
fi
assert_build cached 2
if ! grep -qF '[dry-run] would install: texlive-example' "${TEST_ROOT}/build.stdout"; then
    echo "FAIL: cached compiler failure must regenerate missing-package diagnostics" >&2
    exit 1
fi
assert_build recover 0
if [ "$(cat "${TEST_ROOT}/build-count")" -ne 2 ] \
    || ! grep -qF '[dry-run] would install: texlive-example' "${TEST_ROOT}/build.stdout"; then
    echo "FAIL: successful retry must clear the earlier compiler failure" >&2
    exit 1
fi
assert_build cap 4
if [ "$(cat "${TEST_ROOT}/build-count")" -ne 5 ] \
    || ! grep -qF 'hit retry cap (5)' "${TEST_ROOT}/build.stdout"; then
    echo "FAIL: retry exhaustion must stop after five builds with a diagnostic" >&2
    exit 1
fi

echo "tex dry-run tests passed"
