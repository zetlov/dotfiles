#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NETWORK_SERVICE="${SCRIPT_DIR}/../../stow/desktop/.config/quickshell/zetshell/services/NetworkService.qml"
NETWORK_STATUS="${SCRIPT_DIR}/../../stow/desktop/.local/bin/zetshell-network-status.sh"

if rg -q 'pendingCommand\s*=.*password|command:\s*\["bash",\s*"-lc",\s*root\.pendingCommand\]' \
    "${NETWORK_SERVICE}"; then
    echo "FAIL: Wi-Fi credentials must not be placed in process arguments" >&2
    exit 1
fi
if rg -q 'password\.trim\(\)' "${NETWORK_SERVICE}"; then
    echo "FAIL: Wi-Fi passwords must preserve leading and trailing spaces" >&2
    exit 1
fi

if ! rg -q 'pendingCommand\s*=\s*\["nmcli",\s*"--ask"' "${NETWORK_SERVICE}" \
    || ! rg -q 'stdinEnabled:\s*true' "${NETWORK_SERVICE}" \
    || ! rg -q 'actionProcess\.write\(root\.pendingInput\)' "${NETWORK_SERVICE}"; then
    echo "FAIL: password-protected Wi-Fi should pass credentials to nmcli over stdin" >&2
    exit 1
fi

if [ ! -x "${NETWORK_STATUS}" ]; then
    echo "FAIL: network status collection should be an executable, testable helper" >&2
    exit 1
fi

fixture_root=$(mktemp -d)
fixture_bin="${fixture_root}/bin"
mkdir -p "${fixture_bin}"
trap 'rm -rf "${fixture_root}"' EXIT
cat > "${fixture_bin}/nmcli" <<'EOF'
#!/usr/bin/env bash
if [ -n "${NMCLI_LOG:-}" ]; then
    printf '%s\n' "$*" >> "${NMCLI_LOG}"
fi
if [ "${NMCLI_FIXTURE:-wifi}" = "ethernet" ]; then
    case "$*" in
        "radio wifi") printf 'disabled\n' ;;
        "-t -e yes -f DEVICE,TYPE,STATE,CONNECTION dev status")
            printf 'enp5s0:ethernet:connected:Wired connection 1\n'
            ;;
        "-t -e no -f UUID,TYPE connection show"|"-t -e yes -f NAME,TYPE connection show --active")
            ;;
        "-t -e yes -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list")
            exit 10
            ;;
        *) exit 1 ;;
    esac
    exit 0
fi
case "$*" in
    "radio wifi") printf 'enabled\n' ;;
    "-t -e yes -f DEVICE,TYPE,STATE,CONNECTION dev status")
        printf 'wlan0:wifi:connected:Friendly\\: profile\n'
        ;;
    "-t -e no -f UUID,TYPE connection show")
        printf '11111111-1111-1111-1111-111111111111:802-11-wireless\n'
        ;;
    "-e no -g 802-11-wireless.ssid connection show uuid 11111111-1111-1111-1111-111111111111")
        printf 'Cafe:Guest\n'
        ;;
    "-t -e yes -f NAME,TYPE connection show --active")
        printf 'Friendly\\: profile:802-11-wireless\n'
        ;;
    "-t -e yes -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list")
        printf '*:Cafe\\:Guest:73:WPA2\n'
        ;;
    *)
        printf 'unexpected nmcli invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "${fixture_bin}/nmcli"

network_json=$(HOME="${fixture_root}/home" XDG_CACHE_HOME="${fixture_root}/cache" \
    NMCLI_LOG="${fixture_root}/nmcli.log" PATH="${fixture_bin}:/usr/bin:/bin" \
    "${NETWORK_STATUS}")
if ! jq -e '
    .label == "Cafe:Guest"
    and .connectionName == "Friendly: profile"
    and .networks[0].ssid == "Cafe:Guest"
    and .networks[0].profileUuid == "11111111-1111-1111-1111-111111111111"
    and .networks[0].known == true
    and .networks[0].signal == 73
' <<< "${network_json}" >/dev/null; then
    echo "FAIL: network status should preserve escaped SSIDs and map profiles by UUID" >&2
    exit 1
fi

HOME="${fixture_root}/home" XDG_CACHE_HOME="${fixture_root}/cache" \
    NMCLI_LOG="${fixture_root}/nmcli.log" PATH="${fixture_bin}:/usr/bin:/bin" \
    "${NETWORK_STATUS}" >/dev/null
profile_query_count=$(rg -c '802-11-wireless\.ssid connection show uuid' \
    "${fixture_root}/nmcli.log")
if [ "${profile_query_count}" -ne 1 ]; then
    echo "FAIL: saved Wi-Fi profiles should be cached between refreshes" >&2
    exit 1
fi
HOME="${fixture_root}/home" XDG_CACHE_HOME="${fixture_root}/cache" \
    "${NETWORK_STATUS}" --invalidate
HOME="${fixture_root}/home" XDG_CACHE_HOME="${fixture_root}/cache" \
    NMCLI_LOG="${fixture_root}/nmcli.log" PATH="${fixture_bin}:/usr/bin:/bin" \
    "${NETWORK_STATUS}" >/dev/null
profile_query_count=$(rg -c '802-11-wireless\.ssid connection show uuid' \
    "${fixture_root}/nmcli.log")
if [ "${profile_query_count}" -ne 2 ]; then
    echo "FAIL: invalidating the profile cache should refresh saved Wi-Fi mappings" >&2
    exit 1
fi

ethernet_json=$(HOME="${fixture_root}/home" XDG_CACHE_HOME="${fixture_root}/ethernet-cache" \
    NMCLI_FIXTURE=ethernet PATH="${fixture_bin}:/usr/bin:/bin" "${NETWORK_STATUS}")
if ! jq -e '
    .state == "ethernet"
    and .label == "Wired connection 1"
    and .deviceName == "enp5s0"
    and .networks == []
' <<< "${ethernet_json}" >/dev/null; then
    echo "FAIL: network status should survive an unavailable Wi-Fi scan" >&2
    exit 1
fi

echo "network credential tests passed"
