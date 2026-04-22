# Sixfab ECM to QMI Migration — Claude Code Context

## Project Purpose

This three-file system migrates Vertek Raspberry Pi "Core" devices from Sixfab's ECM mode to raw QMI mode, removing the Sixfab agent stack entirely. It is deployed via:

```
curl -sS https://raw.githubusercontent.com/VertekAU/Sixfab-Removal-and-QMI-Flip/main/deploy.sh | sudo bash
```

## Files

- **deploy.sh** — Entry point. Downloads migrate.sh and reconnect.sh, installs them, creates two systemd services, and starts the migration service. If already migrated, prints a status report and exits.
- **migrate.sh** — One-time migration: stops/masks Sixfab agents, flips modem from ECM to QMI mode via AT commands, runs the initial QMI bearer setup, verifies LTE, writes a marker file, then uninstalls Sixfab. Idempotent — exits early if marker exists.
- **reconnect.sh** — Boot script run by `vcm-qmi-reconnect.service` on every boot to re-establish the wwan0 LTE connection.

## Device Context

- Raspberry Pi running Raspberry Pi OS
- Quectel modem connected via USB, exposed as `/dev/cdc-wdm0` and `wwan0`
- **wlan0** is the primary interface (venue WiFi), always preferred
- **wwan0** is the LTE fallback — must have higher route metric than wlan0
- Target metrics: wlan0 = 600, wwan0 = 700
- APN is `super` (Telstra wholesale), no username/password required
- The migration is one-and-done — migrate.sh must never run again after the marker file exists at `/var/lib/vcm/migration_qmi_done`

## Known Issue to Fix

**reconnect.sh is too aggressive on boot.** It unconditionally runs the full QMI setup sequence (link down, raw_ip toggle, link up, wds-start-network, udhcpc) on every boot, even if the modem comes up on its own. This disrupts the connection during the boot window and causes wwan0 to land on a 169.254.x.x APIPA address instead of a real LTE IP.

The Sixfab docs confirm the qmicli + udhcpc sequence is a one-time manual setup — it does not need to run on every boot unconditionally. However, the modem driver (qmi_wwan) does NOT automatically negotiate a bearer session, so a boot script IS needed as a fallback — just not as the default unconditional path.

## Required Fix for reconnect.sh

Rewrite reconnect.sh to be a health-check-first script:

1. Wait for `/dev/cdc-wdm0` to exist (up to 30s)
2. Wait for wwan0 to appear and settle (up to 30s)
3. Check if wwan0 already has a valid IPv4 (not 169.254.x.x) — if yes, skip to step 5
4. If no valid IP, run the full QMI setup sequence (current logic: link down, raw_ip, link up, wds-start-network, udhcpc) — this is the fallback path
5. Ensure wwan0 default route is set at metric 700 (run unconditionally after any successful IP assignment, not gated on WAN_GW being non-empty as it currently is)
6. Log clearly whether it took the healthy path or the fallback path
7. Always exit 0 — wlan0 is sufficient for operation if wwan0 fails

## Constraints — Do Not Change

- Do not change the APN, QMI flags (`net-raw-ip|net-no-qos-header`), or raw_ip setup — these are correct and working across the fleet
- Do not change migrate.sh logic — the migration sequence is correct
- Do not introduce ModemManager or NetworkManager dependencies
- Do not add Python or any dependency not already present (bash, qmicli, udhcpc, ip, awk are all available)
- Keep reconnect.sh self-contained and minimal — it runs as a systemd oneshot on every boot

## General Code Review Notes

While fixing the above, also tidy the scripts for:
- Consistency in style and error messaging
- Any obvious edge cases or races not already handled
- Log output clarity (all output goes to journald via systemd)

Do not refactor the overall architecture or split files further — the three-file structure is intentional.