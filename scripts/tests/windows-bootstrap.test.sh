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
    "$(resolve_windows_components 0 0 0)" \
    "default selection"
assert_equals "glazewm" \
    "$(resolve_windows_components 1 0 0)" \
    "GlazeWM selection"
assert_equals "monitor-profiles" \
    "$(resolve_windows_components 0 0 1)" \
    "monitor profile selection"
assert_equals "glazewm,monitor-profiles" \
    "$(resolve_windows_components 1 0 1)" \
    "GlazeWM and monitor profile selection"
assert_equals "komorebi" \
    "$(resolve_windows_components 0 1 0)" \
    "Komorebi selection"
assert_equals "komorebi,monitor-profiles" \
    "$(resolve_windows_components 0 1 1)" \
    "Komorebi and monitor profile selection"
assert_equals "docker-desktop" \
    "$(resolve_windows_prerequisite_component desktop)" \
    "Docker Desktop prerequisite selection"
assert_equals "" \
    "$(resolve_windows_prerequisite_component native)" \
    "native container prerequisite selection"
assert_equals "" \
    "$(resolve_windows_prerequisite_component none)" \
    "disabled container prerequisite selection"

if resolve_windows_components yes 0 0 >/dev/null 2>&1; then
    fail "resolver accepted a non-boolean flag"
fi
if resolve_windows_components 0 0 yes >/dev/null 2>&1; then
    fail "resolver accepted a non-boolean monitor profile flag"
fi
if resolve_windows_components 1 1 0 >/dev/null 2>&1; then
    fail "resolver accepted both window managers"
fi
if resolve_windows_prerequisite_component invalid >/dev/null 2>&1; then
    fail "prerequisite resolver accepted an invalid container backend"
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

preflight_windows_components \
    "${fake_repo}" \
    "komorebi,monitor-profiles" \
    "${fake_wslpath}" \
    "${fake_pwsh}" >/dev/null

expected_combined_preflight_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-Preflight
-AdditionalComponentCsv
komorebi,monitor-profiles
-AllowRollbackOnly
EOF
)
assert_equals "${expected_combined_preflight_argv}" "$(cat "${pwsh_log}")" \
    "combined rollback preflight argv"

apply_windows_components \
    "${fake_repo}" \
    "komorebi,monitor-profiles" \
    0 \
    "${fake_wslpath}" \
    "${fake_pwsh}"

expected_combined_apply_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-AdditionalComponentCsv
komorebi,monitor-profiles
-AllowRollbackOnly
EOF
)
assert_equals "${expected_combined_apply_argv}" "$(cat "${pwsh_log}")" \
    "combined rollback apply argv"
assert_equals "4" "$(wc -l <"${pwsh_count}")" \
    "two preflight and two apply invocations"

preflight_windows_prerequisite_component \
    "${fake_repo}" \
    "docker-desktop" \
    "${fake_wslpath}" \
    "${fake_pwsh}" >/dev/null

expected_prerequisite_preflight_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-Preflight
-ComponentCsv
docker-desktop
EOF
)
assert_equals "${expected_prerequisite_preflight_argv}" "$(cat "${pwsh_log}")" \
    "Docker Desktop prerequisite preflight argv"

apply_windows_prerequisite_component \
    "${fake_repo}" \
    "docker-desktop" \
    "${fake_wslpath}" \
    "${fake_pwsh}"

expected_prerequisite_apply_argv=$(cat <<'EOF'
-NoProfile
-ExecutionPolicy
Bypass
-File
C:\dotfiles\windows\install.ps1
-Mode
Install
-ComponentCsv
docker-desktop
EOF
)
assert_equals "${expected_prerequisite_apply_argv}" "$(cat "${pwsh_log}")" \
    "Docker Desktop prerequisite apply argv"
assert_equals "-w
${fake_repo}/windows/install.ps1" "$(cat "${wslpath_log}")" \
    "wslpath argv"

for invalid_component in \
    "wezterm" \
    "autostart" \
    "glazewm,komorebi" \
    "monitor-profiles,glazewm"; do
    if apply_windows_components \
        "${fake_repo}" "${invalid_component}" 0 \
        "${fake_wslpath}" "${fake_pwsh}" >/dev/null 2>&1; then
        fail "helper accepted invalid addition: ${invalid_component}"
    fi
done

if apply_windows_prerequisite_component \
    "${fake_repo}" "wezterm" \
    "${fake_wslpath}" "${fake_pwsh}" >/dev/null 2>&1; then
    fail "prerequisite bridge accepted a non-prerequisite component"
fi

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

fake_windows_powershell="${test_root}/powershell.exe"
bootstrapped_pwsh="${test_root}/PowerShell/7/pwsh.exe"
windows_powershell_log="${test_root}/windows-powershell.log"
mkdir -p "$(dirname "${bootstrapped_pwsh}")"
cat >"${fake_windows_powershell}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"${windows_powershell_log}"
touch "${bootstrapped_pwsh}"
EOF
chmod +x "${fake_windows_powershell}"

ensure_windows_powershell \
    "${bootstrapped_pwsh}" \
    "${fake_windows_powershell}"
if ! rg -Fq 'Microsoft.PowerShell' "${windows_powershell_log}"; then
    fail "PowerShell bootstrap did not request the official WinGet package"
fi

rm -f "${windows_powershell_log}"
ensure_windows_powershell \
    "${bootstrapped_pwsh}" \
    "${fake_windows_powershell}"
if [ -e "${windows_powershell_log}" ]; then
    fail "PowerShell bootstrap was not idempotent"
fi

if [ "$(rg -c '^    apply_windows_components[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must invoke the Windows component bridge exactly once"
fi
if [ "$(rg -c '^    preflight_windows_components[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must invoke the Windows preflight exactly once"
fi
if [ "$(rg -c '^        preflight_windows_prerequisite_component[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must preflight the Windows prerequisite once"
fi
if [ "$(rg -c '^        apply_windows_prerequisite_component[[:space:]]' \
    "${bootstrap}")" -ne 1 ]; then
    fail "install.sh must apply the Windows prerequisite once"
fi
preflight_line=$(rg -n '^    preflight_windows_components[[:space:]]' \
    "${bootstrap}" | cut -d: -f1)
prerequisite_apply_line=$(rg -n \
    '^        apply_windows_prerequisite_component[[:space:]]' \
    "${bootstrap}" | cut -d: -f1)
container_validation_line=$(rg -n '^"\$\{DOTFILES_DIR\}/scripts/validate-container-backend\.sh"' \
    "${bootstrap}" | cut -d: -f1)
if [ "${preflight_line}" -ge "${container_validation_line}" ]; then
    fail "Windows preflight must run before container validation"
fi
if [ "${prerequisite_apply_line}" -ge "${container_validation_line}" ]; then
    fail "Docker Desktop installation must run before container validation"
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
