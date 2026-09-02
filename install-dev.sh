#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SRC_DIR="${ROOT_DIR}/sysutils/apcups-bk650m2/src/opnsense"
WWW_DIR="${ROOT_DIR}/sysutils/apcups-bk650m2/src/www"

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root on OPNsense." >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}" ]; then
    echo "Source directory not found: ${SRC_DIR}" >&2
    exit 1
fi

if ! command -v configctl >/dev/null 2>&1; then
    echo "configctl not found. Run this script on OPNsense." >&2
    exit 1
fi

echo "Installing APC BK650M2 plugin files into /usr/local/opnsense ..."
cp -R "${SRC_DIR}/"* /usr/local/opnsense/

if [ -d "${WWW_DIR}" ]; then
    echo "Installing APC BK650M2 widget files into /usr/local/www ..."
    cp -R "${WWW_DIR}/"* /usr/local/www/
    chmod 644 /usr/local/www/widgets/widgets/apcups.widget.php
fi

chmod 755 /usr/local/opnsense/scripts/apcupsbk650m2/*.sh
chmod 755 /usr/local/opnsense/scripts/apcupsbk650m2/*.php
chmod 755 /usr/local/opnsense/scripts/apcupsbk650m2/*.py
mkdir -p /var/db/nut
chmod -R 755 /usr/local/opnsense/mvc/app/controllers/OPNsense/ApcUps
chmod -R 755 /usr/local/opnsense/mvc/app/models/OPNsense/ApcUps
chmod -R 755 /usr/local/opnsense/mvc/app/views/OPNsense/ApcUps
chmod -R 755 /usr/local/opnsense/service/templates/OPNsense/ApcUps

echo "Reloading configd actions ..."
service configd restart

echo "Rendering NUT templates ..."
configctl template reload OPNsense/ApcUps || echo "Warning: template reload reported an error (this is normal before the first save in the UI)."
if [ -f /usr/local/opnsense/scripts/apcupsbk650m2/notify.conf ]; then
    chmod 600 /usr/local/opnsense/scripts/apcupsbk650m2/notify.conf
else
    echo "Warning: notify.conf not generated yet. It will be created after you save the notification settings in the UI."
fi
if [ -f /etc/cron.d/apcups-bk650m2 ]; then
    chmod 644 /etc/cron.d/apcups-bk650m2
else
    echo "Warning: cron file not generated yet. It will be created after you save the settings in the UI."
fi

echo "Clearing menu and ACL caches ..."
rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json
rm -f /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json

echo "Restarting lighttpd ..."
service lighttpd onerestart || true

echo "Restarting APC BK650M2 NUT service ..."
configctl apcupsbk650m2 restart || true

echo "Done."
echo "Open: https://<opnsense-host>/ui/apcups/"
echo "Diagnostics: configctl apcupsbk650m2 diagnostics BK650M2@localhost"
