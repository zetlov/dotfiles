#!/usr/bin/env bash

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zetshell"
PROFILE_CACHE="${CACHE_DIR}/network-profiles.json"
PROFILE_CACHE_TTL=300

if [ "${1:-}" = "--invalidate" ]; then
    rm -f -- "${PROFILE_CACHE}"
    exit 0
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--invalidate]" >&2
    exit 2
fi

read_profile_cache() {
    local modified now
    [ -f "${PROFILE_CACHE}" ] || return 1
    jq -e 'type == "array"' "${PROFILE_CACHE}" >/dev/null 2>&1 || return 1
    modified=$(stat -c %Y "${PROFILE_CACHE}" 2>/dev/null) || return 1
    now=$(date +%s)
    [ $((now - modified)) -lt "${PROFILE_CACHE_TTL}" ] || return 1
    cat "${PROFILE_CACHE}"
}

collect_profiles() {
    local profiles ssid temporary_cache
    profiles=$(
        while IFS=: read -r uuid connection_type; do
            case "${connection_type}" in
                802-11-wireless|wifi)
                    ssid=$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "${uuid}" 2>/dev/null \
                        | sed -n '1p' || true)
                    if [ -n "${ssid}" ]; then
                        jq -cn --arg uuid "${uuid}" --arg ssid "${ssid}" \
                            '{uuid: $uuid, ssid: $ssid}'
                    fi
                    ;;
            esac
        done < <(nmcli -t -e no -f UUID,TYPE connection show 2>/dev/null || true)
        true
    )
    profiles=$(printf '%s\n' "${profiles}" | jq -sc 'map(select(type == "object"))')

    umask 077
    mkdir -p "${CACHE_DIR}"
    temporary_cache=$(mktemp "${PROFILE_CACHE}.tmp.XXXXXX")
    if printf '%s\n' "${profiles}" > "${temporary_cache}"; then
        mv -f -- "${temporary_cache}" "${PROFILE_CACHE}"
    else
        rm -f -- "${temporary_cache}"
    fi
    printf '%s\n' "${profiles}"
}

wifi_radio=$(nmcli radio wifi 2>/dev/null | sed -n '1p' | tr '[:upper:]' '[:lower:]')
device_status=$(nmcli -t -e yes -f DEVICE,TYPE,STATE,CONNECTION dev status 2>/dev/null || true)
active_connections=$(nmcli -t -e yes -f NAME,TYPE connection show --active 2>/dev/null || true)
wifi_rows=$(nmcli -t -e yes -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null || true)
wifi_rows=$(printf '%s\n' "${wifi_rows}" | sed '/^$/d' | sed -n '1,12p')

known_json=$(read_profile_cache || collect_profiles)

device_json=$(printf '%s\n' "${device_status}" | jq -Rsc 'split("\n") | map(select(length > 0))')
active_json=$(printf '%s\n' "${active_connections}" | jq -Rsc 'split("\n") | map(select(length > 0))')
rows_json=$(printf '%s\n' "${wifi_rows}" | jq -Rsc 'split("\n") | map(select(length > 0))')

jq -cn \
    --arg wifiRadio "${wifi_radio}" \
    --argjson devices "${device_json}" \
    --argjson activeConnections "${active_json}" \
    --argjson known "${known_json}" \
    --argjson rows "${rows_json}" '
    def nmcliFields:
      reduce (explode[]) as $character (
        {fields: [""], escaped: false};
        if .escaped then
          .fields[-1] += ($character | [.] | implode)
          | .escaped = false
        elif $character == 92 then
          .escaped = true
        elif $character == 58 then
          .fields += [""]
        else
          .fields[-1] += ($character | [.] | implode)
        end
      )
      | if .escaped then .fields[-1] += "\\" else . end
      | .fields;

    def parseDevice($line):
      ($line | nmcliFields) as $parts
      | {
          device: ($parts[0] // ""),
          type: ($parts[1] // ""),
          state: ($parts[2] // ""),
          connection: ($parts[3] // "")
        };

    def parseWifiRow($line):
      ($line | nmcliFields) as $parts
      | ($parts[1] // "") as $ssid
      | (($known | map(select(.ssid == $ssid)) | .[0]) // null) as $profile
      | {
          active: (($parts[0] // "") == "*"),
          ssid: $ssid,
          signal: (($parts[2] // "0") | tonumber? // 0),
          security: (($parts[3:] | join(":")) // ""),
          profileUuid: ($profile.uuid // ""),
          known: ($profile != null)
        }
      | .connectable = (.known or (.security == "" or .security == "--"));

    ($devices | map(parseDevice(.))) as $parsedDevices
    | ($parsedDevices | map(select(.type == "wifi" and (.state | startswith("connected")))) | .[0]) as $wifiStatus
    | ($parsedDevices | map(select(.type == "ethernet" and (.state | startswith("connected")))) | .[0]) as $ethStatus
    | ($activeConnections
       | map(nmcliFields)
       | map(select(.[1] == "vpn"))
       | .[0][0] // "") as $vpnName
    | ($rows | map(parseWifiRow(.)) | unique_by(.ssid) | map(select(.ssid != ""))) as $wifiNetworks
    | ($wifiNetworks | map(select(.active)) | .[0]) as $activeWifiRow
    | {
        state:
          (if $wifiStatus != null then "wifi"
           elif $ethStatus != null then "ethernet"
           elif $wifiRadio == "disabled" then "disabled"
           else "offline"
           end),
        label:
          (if $wifiStatus != null then (($activeWifiRow.ssid // "") | if . == "" then ($wifiStatus.connection // "Connected") else . end)
           elif $ethStatus != null then ($ethStatus.connection // "Connected")
           elif $wifiRadio == "disabled" then "Radio off"
           else "Offline"
           end),
        deviceName:
          (if $wifiStatus != null then ($wifiStatus.device // "")
           elif $ethStatus != null then ($ethStatus.device // "")
           else ""
           end),
        connectionName:
          (if $wifiStatus != null then ($wifiStatus.connection // "")
           elif $ethStatus != null then ($ethStatus.connection // "")
           else ""
           end),
        vpnName: $vpnName,
        wifiEnabled: ($wifiRadio != "disabled"),
        signal: ($activeWifiRow.signal // 0),
        security: ($activeWifiRow.security // ""),
        networks: $wifiNetworks
      }'
