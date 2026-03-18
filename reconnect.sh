#!/usr/bin/env bash
set -euo pipefail
sleep 10
qmicli -d /dev/cdc-wdm0 --dms-get-operating-mode
ip link set wwan0 down
echo 'Y' | tee /sys/class/net/wwan0/qmi/raw_ip >/dev/null
ip link set wwan0 up
qmicli -d /dev/cdc-wdm0 --wda-get-data-format
qmicli -p -d /dev/cdc-wdm0 --device-open-net='net-raw-ip|net-no-qos-header' --wds-start-network="apn='super',ip-type=4" --client-no-release-cid
udhcpc -q -f -i wwan0

# Fix wwan0 route metric so WiFi remains preferred when available
WAN_GW="$(ip route show default dev wwan0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
if [ -n "${WAN_GW:-}" ]; then
    ip route del default dev wwan0 2>/dev/null || true
    ip route add default via "$WAN_GW" dev wwan0 metric 700
fi

echo "[$(date -Is)] QMI reconnect complete."