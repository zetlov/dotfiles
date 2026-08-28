#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd "${script_dir}/../.." && pwd)
helper="${repo_root}/scripts/install/windows-components.sh"
bootstrap="${repo_root}/scripts/install/bootstrap.sh"

# shellcheck source=../install/windows-components.sh
# shellcheck disable=SC1091
source "${helper}"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [ "${actual}" != "${expected}" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' \
            "${message}" "${expected}" "${actual}" >&2
        exit 1
    fi
}

assert_equals "" \
    "$(resolve_windows_components 0 0)" \
    "default selection"
assert_equals "glazewm,monitor-profiles" \
    "$(resolve_windows_components 1 0)" \
    "GlazeWM selection"
assert_equals "komorebi" \
    "$(resolve_windows_components 0 1)" \
    "Komorebi selection"

if resolve_windows_components yes 0 >/dev/null 2>&1; then
    fail "resolver accepted a non-boolean flag"
fi
if resolve_windows_components 1 1 >/dev/null 2>&1; then
    fail "resolver accepted both window managers"
fi

if rg -q '\bjq\b|components\.json' "${helper}"; then
    fail "Bash bridge duplicates catalog selection or requires preinstalled jq"
fi
if ! rg -Fq 'Windows integration: required catalog components' \
    "${bootstrap}"; then
    fail "dry-run does not describe catalog-driven required components"
fi

test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT
fake_repo="${test_root}/repo"
mkdir -p "${fake_repo}/windows"
touch "${fake_repo}/windows/install.ps1"

wslpath_log="${test_root}/wslpath.log"
pwsh_log="${test_root}/pwsh.log"
pwsh_count="${test_root}/pwsh-count.log"
fake_wslpath="${test_root}/wslpath"
fake_pwsh="${test_root}/pwsh.exe"

cat >"${fake_wslpath}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"${wslpath_log}"
printf '%s\n' 'C:\\dotfiles\\windows\\install.ps1'
EOF
chmod +x "${fake_wslpath}"
cat >"${fake_pwsh}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"${pwsh_log}"
printf '%s\n' invoked >>"${pwsh_count}"
EOF
chmod +x "${fake_pwsh}"

preflight_windows_components \
    "${fake_repo}" \
    "komorebi" \
    "${fake_wslpath}" \
    "${fake_pwsh}" >/dev/null

expected_preflight_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-Preflight
-AdditionalComponentCsv
komorebi
-AllowRollbackOnly
EOF
)
assert_equals "${expected_preflight_argv}" "$(cat "${pwsh_log}")" \
    "PowerShell 7 preflight argv"
assert_equals "1" "$(wc -l <"${pwsh_count}")" \
    "single PowerShell 7 preflight invocation"

apply_windows_components \
    "${fake_repo}" \
    "komorebi" \
    1 \
    "${fake_wslpath}" \
    "${fake_pwsh}"

expected_apply_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-AdditionalComponentCsv
komorebi
-AllowRollbackOnly
-AddKanataDefenderExclusion
EOF
)
assert_equals "${expected_apply_argv}" "$(cat "${pwsh_log}")" \
    "PowerShell 7 apply argv"
assert_equals "2" "$(wc -l <"${pwsh_count}")" \
    "one preflight and one apply invocation"
assert_equals "-w
${fake_repo}/windows/install.ps1" "$(cat "${wslpath_log}")" \
    "wslpath argv"

for invalid_component in \
    "wezterm" \
    "autostart" \
    "glazewm" \
    "glazewm,komorebi"; do
    if apply_windows_components \
        "${fake_repo}" "${invalid_component}" 0 \
        "${fake_wslpath}" "${fake_pwsh}" >/dev/null 2>&1; then
        fail "helper accepted invalid addition: ${invalid_component}"
    fi
done

rm -f "${pwsh_log}" "${pwsh_count}" "${wslpath_log}"
if apply_windows_components \
    "${test_root}/missing-repo" "" 0 \
    "${fake_wslpath}" "${fake_pwsh}" >/dev/null 2>&1; then
    fail "helper accepted a missing root installer"
fi
if [ -e "${pwsh_log}" ] || [ -e "${wslpath_log}" ]; then
    fail "missing installer preflight invoked a bridge dependency"
fi

if apply_windows_components \
    "${fake_repo}" "" 0 \
    "${test_root}/missing-wslpath" "${fake_pwsh}" >/dev/null 2>&1; then
    fail "helper accepted a missing wslpath"
fi
if [ -e "${pwsh_log}" ] || [ -e "${wslpath_log}" ]; then
    fail "missing wslpath preflight invoked a bridge dependency"
fi

if preflight_windows_components \
    "${fake_repo}" "" \
    "${fake_wslpath}" "${test_root}/missing-pwsh" \
    >"${test_root}/missing-pwsh.stdout" \
    2>"${test_root}/missing-pwsh.stderr"; then
    fail "helper accepted a missing PowerShell 7 executable"
fi
if [ -e "${pwsh_log}" ] || [ -e "${wslpath_log}" ]; then
    fail "missing PowerShell 7 preflight ran path conversion or PowerShell"
fi
if ! rg -Fq \
    'winget install --id Microsoft.PowerShell --source winget --installer-type wix' \
    "${test_root}/missing-pwsh.stderr"; then
    fail "missing PowerShell 7 error lacks the official fixed-path recovery"
fi

if [ "$(rg -c '^    apply_windows_components[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must invoke the Windows component bridge exactly once"
fi
if [ "$(rg -c '^    preflight_windows_components[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must invoke the Windows preflight exactly once"
fi
preflight_line=$(rg -n '^    preflight_windows_components[[:space:]]' \
    "${bootstrap}" | cut -d: -f1)
container_validation_line=$(rg -n '^"\$\{DOTFILES_DIR\}/scripts/validate-container-backend\.sh"' \
    "${bootstrap}" | cut -d: -f1)
if [ "${preflight_line}" -ge "${container_validation_line}" ]; then
    fail "Windows preflight must run before container validation"
fi
for legacy_installer in wezterm kanata komorebi glazewm; do
    if rg -Fq "windows/${legacy_installer}/install.ps1" \
        "${bootstrap}"; then
        fail "install.sh retains a legacy ${legacy_installer} invocation"
    fi
done
if rg -q 'powershell\.exe[[:space:]]+-' "${bootstrap}"; then
    fail "install.sh retains a Windows PowerShell executable invocation"
fi

echo "Windows bootstrap tests passed"
