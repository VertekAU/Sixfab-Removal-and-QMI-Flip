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
echo "[$(date -Is)] QMI reconnect complete."
