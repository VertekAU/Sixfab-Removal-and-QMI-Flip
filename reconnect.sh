#!/usr/bin/env bash
set -uo pipefail

LOG_PREFIX="[vcm-qmi-reconnect $(date -Is)]"

# Wait for QMI device node (up to 30s)
for i in $(seq 1 30); do
    [ -e /dev/cdc-wdm0 ] && break
    [ "$i" -eq 30 ] && { echo "$LOG_PREFIX cdc-wdm0 not found after 30s — wwan0 unavailable, wlan0 sufficient"; exit 0; }
    sleep 1
done

# Wait for wwan0 interface to appear (up to 30s)
for i in $(seq 1 30); do
    ip link show wwan0 >/dev/null 2>&1 && break
    [ "$i" -eq 30 ] && { echo "$LOG_PREFIX wwan0 not found after 30s — skipping LTE setup, wlan0 sufficient"; exit 0; }
    sleep 1
done

# Check for a valid (non-APIPA) IPv4 on wwan0
CURRENT_IP="$(ip -4 addr show wwan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
HEALTHY=0
if [ -n "${CURRENT_IP:-}" ]; then
    case "$CURRENT_IP" in
        169.254.*) ;;
        *) HEALTHY=1 ;;
    esac
fi

if [ "$HEALTHY" -eq 1 ]; then
    echo "$LOG_PREFIX wwan0 already has valid IP $CURRENT_IP — skipping QMI setup (healthy path)"
else
    echo "$LOG_PREFIX wwan0 has no valid IP (current: ${CURRENT_IP:-none}) — running QMI setup (fallback path)"

    qmicli -d /dev/cdc-wdm0 --dms-get-operating-mode || true
    ip link set wwan0 down
    echo 'Y' | tee /sys/class/net/wwan0/qmi/raw_ip >/dev/null
    ip link set wwan0 up
    qmicli -d /dev/cdc-wdm0 --wda-get-data-format || true
    qmicli -p -d /dev/cdc-wdm0 --device-open-net='net-raw-ip|net-no-qos-header' \
        --wds-start-network="apn='super',ip-type=4" --client-no-release-cid || true
    udhcpc -q -f -i wwan0 || true

    CURRENT_IP="$(ip -4 addr show wwan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
    if [ -z "${CURRENT_IP:-}" ]; then
        echo "$LOG_PREFIX QMI setup ran but wwan0 has no IP — wlan0 sufficient, continuing"
        exit 0
    fi
    echo "$LOG_PREFIX QMI setup complete, wwan0 IP: $CURRENT_IP"
fi

# Unconditionally fix wwan0 default route metric to 700 so wlan0 remains preferred
WAN_GW="$(ip route show default dev wwan0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
if [ -n "${WAN_GW:-}" ]; then
    ip route del default dev wwan0 2>/dev/null || true
    ip route add default via "$WAN_GW" dev wwan0 metric 700
    echo "$LOG_PREFIX wwan0 default route set via $WAN_GW metric 700"
else
    echo "$LOG_PREFIX no default route on wwan0 to fix"
fi

exit 0
