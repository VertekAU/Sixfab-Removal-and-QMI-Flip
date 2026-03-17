#!/usr/bin/env bash
# VCM — Sixfab ECM to QMI migration
# Usage: curl -sS https://raw.githubusercontent.com/VertekAU/Sixfab-Removal-and-QMI-Flip/main/deploy.sh | sudo bash
set -euo pipefail

BASE="https://raw.githubusercontent.com/VertekAU/Sixfab-Removal-and-QMI-Flip/main"

mkdir -p /usr/local/sbin /var/lib/vcm /var/log
rm -f /var/lib/vcm/migration_qmi_done

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
systemctl start vcm-migrate-sixfab-ecm-to-qmi.service
echo "Migration running. Follow with:"
echo "  sudo journalctl -u vcm-migrate-sixfab-ecm-to-qmi.service -f"
