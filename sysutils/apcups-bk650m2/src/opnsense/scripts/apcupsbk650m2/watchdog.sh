#!/bin/sh
#
# APC BK650M2 watchdog: auto-recover when the UPS becomes unreachable.
# Called from /etc/cron.d/apcups-bk650m2 every few minutes.
#

set -eu

HOSTNAME=$(hostname)
UPS_NAME="${APCUPS_UPS_NAME:-BK650M2}"
STATE_DIR="/var/db/nut"
FAIL_FILE="${STATE_DIR}/apcups_watchdog_failures"
LAST_ALERT_FILE="${STATE_DIR}/apcups_watchdog_last_alert"
NOTIFY_CONF="/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf"
MAX_FAILS=3
RETRY_DELAY=3
ALERT_COOLDOWN=900

log() {
    logger -t apcups-bk650m2 "${1}"
}

# Watchdog notifications are connection-related and respect the
# "enable disconnect notification" switch in the notification settings.
comm_notify_enabled() {
    [ -f "${NOTIFY_CONF}" ] && /usr/bin/grep -q '"comm_alert_enabled"[[:space:]]*:[[:space:]]*true' "${NOTIFY_CONF}"
}

notify() {
    subject="${1}"
    body="${2}"
    if ! comm_notify_enabled; then
        return 0
    fi
    /usr/local/bin/python3 /usr/local/opnsense/scripts/apcupsbk650m2/notify.py \
        "${subject}" "${body}" || true
}

# Try to read UPS status. Treat as reachable if upsc prints a valid ups.status
# line, even when upsc itself segfaults after output (common on this hardware).
upsc_status() {
    /usr/bin/stdbuf -o0 /usr/local/bin/upsc "${UPS_NAME}@localhost" ups.status 2>/dev/null | tail -n 1
}

check_ups() {
    local status
    status=$(upsc_status)
    if [ -n "${status}" ]; then
        return 0
    fi
    return 1
}

# Attempt the check a few times before declaring failure, to tolerate transient
# upsc segfaults or brief communication hiccups.
check_ups_with_retry() {
    local i
    for i in 1 2 3; do
        if check_ups; then
            return 0
        fi
        if [ "${i}" -lt 3 ]; then
            sleep "${RETRY_DELAY}"
        fi
    done
    return 1
}

# Throttle notifications: do not send more than one alert per cooldown period.
alert_on_cooldown() {
    local now last
    if [ ! -f "${LAST_ALERT_FILE}" ]; then
        return 1
    fi
    now=$(date +%s 2>/dev/null || echo 0)
    last=$(stat -f '%m' "${LAST_ALERT_FILE}" 2>/dev/null || echo 0)
    if [ "${now}" -gt 0 ] && [ "${last}" -gt 0 ] && [ $((now - last)) -lt "${ALERT_COOLDOWN}" ]; then
        return 0
    fi
    return 1
}

mark_alert_sent() {
    touch "${LAST_ALERT_FILE}" 2>/dev/null || true
}

mkdir -p "${STATE_DIR}"

if check_ups_with_retry; then
    if [ -f "${FAIL_FILE}" ]; then
        rm -f "${FAIL_FILE}"
        log "Watchdog: UPS communication restored"
        notify "${HOSTNAME}-UPS恢复通知" "[${HOSTNAME}]上的UPS watchdog 检测到通信已恢复"
    fi
    exit 0
fi

fails=0
if [ -f "${FAIL_FILE}" ]; then
    fails=$(cat "${FAIL_FILE}" 2>/dev/null || echo 0)
    case "${fails}" in
        ''|*[!0-9]*) fails=0 ;;
    esac
fi
fails=$((fails + 1))
echo "${fails}" > "${FAIL_FILE}"

log "Watchdog: UPS check failed (${fails}/${MAX_FAILS})"

if [ "${fails}" -ge "${MAX_FAILS}" ]; then
    if ! alert_on_cooldown; then
        notify "${HOSTNAME}-UPS告警通知" "[${HOSTNAME}]上的UPS通信异常，watchdog 正在尝试重新连接"
        mark_alert_sent
    fi

    # Recovery order follows field data for the BK650M2: when the UPS firmware
    # wedges its USB HID interface, driver restarts (soft or forced) never
    # recover it while a bus-level USB reset always does. Soft restart is kept
    # first because it is cheap and fixes transient driver-side issues; the USB
    # reset follows immediately instead of after another doomed driver restart.
    log "Watchdog: attempting soft NUT restart"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh restart || true
    sleep 5

    if check_ups_with_retry; then
        rm -f "${FAIL_FILE}"
        log "Watchdog: UPS reconnected after soft restart"
        notify "${HOSTNAME}-UPS恢复通知" "[${HOSTNAME}]上的UPS已通过 watchdog 重新连接"
        exit 0
    fi

    log "Watchdog: soft restart failed, attempting USB reset"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh reset-usb || true
    sleep 5

    if check_ups_with_retry; then
        rm -f "${FAIL_FILE}"
        log "Watchdog: UPS reconnected after USB reset"
        notify "${HOSTNAME}-UPS恢复通知" "[${HOSTNAME}]上的UPS已通过 USB 重置重新连接"
        exit 0
    fi

    log "Watchdog: USB reset failed, attempting force restart"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh force-restart || true
    sleep 5

    if check_ups_with_retry; then
        rm -f "${FAIL_FILE}"
        log "Watchdog: UPS reconnected after force restart"
        notify "${HOSTNAME}-UPS恢复通知" "[${HOSTNAME}]上的UPS已通过 watchdog 深度重启重新连接"
        exit 0
    fi

    log "Watchdog: failed to reconnect UPS"
fi
