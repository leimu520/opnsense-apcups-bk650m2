#!/bin/sh

set -eu

UPS_NAME="${APCUPS_UPS_NAME:-BK650M2}"
DRIVER="${APCUPS_DRIVER:-usbhid-ups}"

action="${1:-restart}"

# Stop the NUT driver directly. The rc.d scripts do not always terminate the
# driver process cleanly (especially after a USB stall), which is why a manual
# restart via the UI or configd would previously fail until the firewall was
# rebooted.
stop_driver() {
    logger -t apcups-bk650m2 "Stopping UPS driver ${DRIVER} for ${UPS_NAME}"
    /usr/local/sbin/upsdrvctl stop "${UPS_NAME}" 2>/dev/null || true

    # Make absolutely sure no stale driver process keeps the USB device open.
    pkill -f "/usr/local/libexec/nut/${DRIVER}" 2>/dev/null || true
    pkill -f "usbhid-ups -a ${UPS_NAME}" 2>/dev/null || true

    # Give the kernel a moment to release the USB handle before restarting.
    sleep 2
}

# Reset the APC USB device. This is the last resort when the driver cannot
# re-attach to the UPS after a communication failure.
reset_usb() {
    local ugen
    ugen=$(/usr/sbin/usbconfig 2>/dev/null | /usr/bin/grep -iE 'APC|American Power Conversion|vendor=0x051d' | /usr/bin/awk '{print $1}' | /usr/bin/head -n 1)
    if [ -n "${ugen}" ]; then
        logger -t apcups-bk650m2 "Resetting USB device ${ugen}"
        /usr/sbin/usbconfig -d "${ugen}" reset 2>/dev/null || true
        sleep 3
    else
        logger -t apcups-bk650m2 "No APC USB device found to reset"
    fi
}

# upsd warns about world-readable credential files. Its rc scripts read the
# configs as root before dropping privileges, so root:nut 0640 keeps NUT
# working while hiding the passwords from other local users.
fix_perms() {
    /usr/sbin/chown root:nut /usr/local/etc/nut/upsd.users /usr/local/etc/nut/upsmon.conf 2>/dev/null || true
    /bin/chmod 640 /usr/local/etc/nut/upsd.users /usr/local/etc/nut/upsmon.conf 2>/dev/null || true
}

case "${action}" in
    start)
        fix_perms
        /usr/local/etc/rc.d/nut start || /usr/local/etc/rc.d/nut onestart
        /usr/local/etc/rc.d/nut_upsmon start || /usr/local/etc/rc.d/nut_upsmon onestart
        ;;
    stop)
        /usr/local/etc/rc.d/nut_upsmon stop || true
        /usr/local/etc/rc.d/nut stop || true
        stop_driver
        ;;
    restart)
        # Soft restart: preserve the running driver if possible. On some
        # systems the FreeBSD kernel HID driver claims the UPS once our driver
        # releases it, making a fresh driver start fail. Keeping the driver
        # running avoids that scenario for the common "restart NUT" case.
        /usr/local/etc/rc.d/nut_upsmon stop || true
        /usr/local/etc/rc.d/nut stop || true
        sleep 2
        fix_perms
        /usr/local/etc/rc.d/nut start || /usr/local/etc/rc.d/nut onestart
        /usr/local/etc/rc.d/nut_upsmon start || /usr/local/etc/rc.d/nut_upsmon onestart
        ;;
    force-restart)
        # Deep restart: stop the driver and start fresh. This requires the
        # kernel HID driver to be prevented from claiming the device, usually
        # via a /boot/loader.conf USB quirk.
        /usr/local/etc/rc.d/nut_upsmon stop || true
        /usr/local/etc/rc.d/nut stop || true
        stop_driver
        fix_perms
        /usr/local/etc/rc.d/nut start || /usr/local/etc/rc.d/nut onestart
        /usr/local/etc/rc.d/nut_upsmon start || /usr/local/etc/rc.d/nut_upsmon onestart
        ;;
    reset-usb)
        /usr/local/etc/rc.d/nut_upsmon stop || true
        /usr/local/etc/rc.d/nut stop || true
        stop_driver
        reset_usb
        fix_perms
        /usr/local/etc/rc.d/nut start || /usr/local/etc/rc.d/nut onestart
        /usr/local/etc/rc.d/nut_upsmon start || /usr/local/etc/rc.d/nut_upsmon onestart
        ;;
    *)
        echo "Unsupported action: ${action}" >&2
        exit 64
        ;;
esac

echo "ok"
