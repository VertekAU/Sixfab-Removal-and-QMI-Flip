#!/usr/bin/env bash
# VCM — Sixfab ECM to QMI migration
# Usage: curl -sS https://raw.githubusercontent.com/VertekAU/Sixfab-Removal-and-QMI-Flip/main/deploy.sh | sudo bash
set -euo pipefail

BASE="https://raw.githubusercontent.com/VertekAU/Sixfab-Removal-and-QMI-Flip/main"

mkdir -p /usr/local/sbin /var/lib/vcm /var/log

# If already migrated, print status report and exit
if [ -f /var/lib/vcm/migration_qmi_done ]; then
    echo "=== ALREADY MIGRATED ==="
    echo "Marker:   $(cat /var/lib/vcm/migration_qmi_done)"
    WWAN_IP="$(ip -4 addr show wwan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
    WWAN_GW="$(ip route show default dev wwan0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
    WWAN_METRIC="$(ip route show default dev wwan0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="metric"){print $(i+1); exit}}')"
    echo "wwan0:    ${WWAN_IP:-no IP} (gw=${WWAN_GW:-none} metric=${WWAN_METRIC:-0})"
    for iface in wlan0 eth0; do
        IFACE_IP="$(ip -4 addr show $iface 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
        IFACE_METRIC="$(ip route show default dev $iface 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="metric"){print $(i+1); exit}}')"
        [ -n "${IFACE_IP:-}" ] && echo "$iface:    $IFACE_IP metric=${IFACE_METRIC:-0}"
    done
    [ -d /opt/sixfab ] && echo "Sixfab:   present (unexpected)" || echo "Sixfab:   absent"
    systemctl is-active core_manager.service 2>/dev/null | grep -q active \
        && echo "Services: core_manager running (unexpected)" \
        || echo "Services: core_manager not running"
    exit 0
fi

curl -sS "$BASE/migrate.sh"   -o /usr/local/sbin/vcm_migrate_sixfab_ecm_to_qmi.sh
curl -sS "$BASE/reconnect.sh" -o /usr/local/sbin/vcm_qmi_reconnect.sh

bash -n /usr/local/sbin/vcm_migrate_sixfab_ecm_to_qmi.sh \
    && echo "Syntax OK" \
    || { echo "ERROR: syntax check failed."; exit 1; }

chmod 0755 /usr/local/sbin/vcm_migrate_sixfab_ecm_to_qmi.sh \
           /usr/local/sbin/vcm_qmi_reconnect.sh
chown root:root /usr/local/sbin/vcm_migrate_sixfab_ecm_to_qmi.sh \
                /usr/local/sbin/vcm_qmi_reconnect.sh

cat > /etc/systemd/system/vcm-migrate-sixfab-ecm-to-qmi.service <<'UNIT'
[Unit]
Description=VCM migrate Sixfab ECM to QMI
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=stdbuf -oL -eL /usr/local/sbin/vcm_migrate_sixfab_ecm_to_qmi.sh
TimeoutStartSec=1200
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/vcm-qmi-reconnect.service <<'UNIT'
[Unit]
Description=VCM QMI reconnect on boot
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/vcm_qmi_reconnect.sh
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable vcm-migrate-sixfab-ecm-to-qmi.service \
                 vcm-qmi-reconnect.service 2>/dev/null || true
systemctl start vcm-migrate-sixfab-ecm-to-qmi.service &
sleep 2
journalctl -u vcm-migrate-sixfab-ecm-to-qmi.service -f --no-pager | grep -m 1 "Consumed.*CPU time" || true
echo "=== Migration service finished. Run: journalctl -u vcm-migrate-sixfab-ecm-to-qmi.service to review ==="