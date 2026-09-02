#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root on OPNsense." >&2
    exit 1
fi

echo "Stopping APC BK650M2 NUT service ..."
configctl apcupsbk650m2 stop 2>/dev/null || true

echo "Removing APC BK650M2 plugin files ..."
rm -rf /usr/local/opnsense/mvc/app/controllers/OPNsense/ApcUps
rm -rf /usr/local/opnsense/mvc/app/models/OPNsense/ApcUps
rm -rf /usr/local/opnsense/mvc/app/views/OPNsense/ApcUps
rm -rf /usr/local/opnsense/service/templates/OPNsense/ApcUps
rm -rf /usr/local/opnsense/scripts/apcupsbk650m2
rm -f /usr/local/opnsense/service/conf/actions.d/actions_apcupsbk650m2.conf
rm -f /usr/local/opnsense/scripts/apcupsbk650m2/notify.conf
rm -f /etc/cron.d/apcups-bk650m2
rm -f /usr/local/www/widgets/widgets/apcups.widget.php

echo "Reloading configd and clearing caches ..."
service configd restart
rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json

echo "Done."
