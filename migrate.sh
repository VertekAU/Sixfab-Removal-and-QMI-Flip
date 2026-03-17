#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/vcm/migration_qmi_done"
mkdir -p /var/lib/vcm

[ -f "$MARKER" ] && { echo "Already migrated."; exit 0; }

unmask_sixfab() {
    for u in core_agent.service core_manager.service; do
        systemctl unmask "$u" 2>/dev/null || true
        systemctl enable "$u" 2>/dev/null || true
        systemctl start  "$u" 2>/dev/null || true
    done
}

apt-get update -qq && apt-get install -y libqmi-utils udhcpc
pip3 install atcom --break-system-packages -q

for u in core_agent.service core_manager.service; do
    systemctl stop    "$u" 2>/dev/null || true
    systemctl disable "$u" 2>/dev/null || true
    systemctl mask    "$u" 2>/dev/null || true
done

for p in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
    [ -e "$p" ] && atcom -p "$p" -t 3 'AT+QCFG="usbnet",0' 2>/dev/null || true
done
sleep 2
for p in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
    [ -e "$p" ] && atcom -p "$p" -t 3 'AT+CFUN=1,1' 2>/dev/null || true
done

for i in $(seq 1 60); do [ -e /dev/cdc-wdm0 ] && break; sleep 3; done
[ -e /dev/cdc-wdm0 ] || { echo "ERROR: cdc-wdm0 not found."; unmask_sixfab; exit 1; }
sleep 5

qmicli -d /dev/cdc-wdm0 --dms-get-operating-mode
ip link set wwan0 down
echo 'Y' | tee /sys/class/net/wwan0/qmi/raw_ip >/dev/null
ip link set wwan0 up
qmicli -d /dev/cdc-wdm0 --wda-get-data-format
qmicli -p -d /dev/cdc-wdm0 --device-open-net='net-raw-ip|net-no-qos-header' --wds-start-network="apn='super',ip-type=4" --client-no-release-cid
udhcpc -q -f -i wwan0

ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1 || { echo "ERROR: ping failed."; unmask_sixfab; exit 1; }
echo "LTE verified."

bash -c "$(curl -sN https://install.connect.sixfab.com)" -- --uninstall || true
rm -rf /opt/sixfab 2>/dev/null || true

systemctl enable vcm-qmi-reconnect.service 2>/dev/null || true
date -Is > "$MARKER"
systemctl disable vcm-migrate-sixfab-ecm-to-qmi.service 2>/dev/null || true
systemctl daemon-reload || true
echo "=== MIGRATION COMPLETE $(date -Is) ==="
