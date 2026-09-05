#!/bin/sh
#
# APC BK650M2 watchdog: auto-recover when the UPS becomes unreachable.
# Called from /etc/cron.d/apcups-bk650m2 every minute.
#

set -eu

HOSTNAME=$(hostname)
UPS_NAME="${APCUPS_UPS_NAME:-BK650M2}"
STATE_DIR="/var/db/nut"
FAIL_FILE="${STATE_DIR}/apcups_watchdog_failures"
OUTAGE_START_FILE="${STATE_DIR}/apcups_watchdog_outage_start"
LAST_ALERT_FILE="${STATE_DIR}/apcups_watchdog_last_alert"
COMM_ALERT_FLAG="${STATE_DIR}/apcups_comm_alert_sent"
LOCK_DIR="${STATE_DIR}/apcups_watchdog_lock"
NOTIFY_CONF="/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf"
MAX_FAILS=3
RETRY_DELAY=3
ALERT_COOLDOWN=900
LOCK_STALE=600

log() {
    logger -t apcups-bk650m2 "${1}"
}

# Watchdog notifications are connection-related and respect the
# "enable disconnect notification" switch in the notification settings.
comm_notify_enabled() {
    [ -f "${NOTIFY_CONF}" ] && /usr/bin/grep -q '"comm_alert_enabled"[[:space:]]*:[[:space:]]*true' "${NOTIFY_CONF}"
}

# Grace period (seconds) rendered from the same model field as the upssched
# debounce timers. Alerts stay silent until the outage has lasted this long.
comm_alert_grace() {
    grace=$(/usr/bin/grep -Eo '"comm_alert_grace"[[:space:]]*:[[:space:]]*[0-9]+' "${NOTIFY_CONF}" 2>/dev/null | /usr/bin/grep -Eo '[0-9]+$' || true)
    case "${grace}" in
        ''|*[!0-9]*) echo 120 ;;
        *) echo "${grace}" ;;
    esac
}

# The shared alert flag is owned by both this watchdog and upssched-cmd.sh and
# marks "an alert already went out for the current outage". Like there, it is
# only trusted for 1 hour: when the watchdog recovers the UPS by restarting
# upsmon, no COMMOK event ever fires, so without an expiry the flag would stick
# around and suppress the alert for the next outage.
comm_alert_flag_fresh() {
    [ -f "${COMM_ALERT_FLAG}" ] || return 1
    now=$(date +%s)
    mtime=$(stat -f '%m' "${COMM_ALERT_FLAG}" 2>/dev/null || echo 0)
    [ "${now}" -gt 0 ] && [ $((now - mtime)) -lt 3600 ]
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

# Attempt the check a few times before declaring failure, to tolerate transient
# upsc segfaults or brief communication hiccups. Prints the ups.status on
# success (nothing on failure) so callers can reuse the value.
probe_ups() {
    local i status
    for i in 1 2 3; do
        status=$(upsc_status)
        if [ -n "${status}" ]; then
            echo "${status}"
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

# Recovery bookkeeping shared by all recovery paths. The recovery notification
# is only sent when this outage was actually alerted (fresh shared flag), so a
# brief outage inside the grace window stays completely silent. The shared flag
# is cleared here too: a fresh upsmon never emits COMMOK, so upssched-cmd.sh
# would otherwise keep the outage marked as alerted.
recover() {
    if comm_alert_flag_fresh; then
        notify "${HOSTNAME}-UPS恢复通知" "${1}"
    fi
    rm -f "${FAIL_FILE}" "${OUTAGE_START_FILE}" "${COMM_ALERT_FLAG}" 2>/dev/null || true
    log "Watchdog: UPS communication restored"
}

# Serialize runs: with a 1-minute cron the escalation sequence can outlive one
# tick, and two concurrent instances would fight over the UPS and double-send
# notifications. A leftover lock from a killed run is stolen once it is older
# than LOCK_STALE seconds.
acquire_lock() {
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
        return 0
    fi
    now=$(date +%s)
    lock_mtime=$(stat -f '%m' "${LOCK_DIR}" 2>/dev/null || echo 0)
    case "${lock_mtime}" in
        ''|*[!0-9]*) lock_mtime=0 ;;
    esac
    if [ "${now}" -gt 0 ] && [ $((now - lock_mtime)) -lt "${LOCK_STALE}" ]; then
        return 1
    fi
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    mkdir "${LOCK_DIR}" 2>/dev/null
}

mkdir -p "${STATE_DIR}"

if ! acquire_lock; then
    log "Watchdog: previous run still active, exiting"
    exit 0
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

ups_status=$(probe_ups) || ups_status=""
if [ -n "${ups_status}" ]; then
    if [ -f "${FAIL_FILE}" ]; then
        recover "[${HOSTNAME}]上的UPS watchdog 检测到通信已恢复"
    fi
    # Periodic battery maintenance: the upssched ONBATT timer only fires once,
    # but the threshold alert and the percentage-based shutdown need repeated
    # checks while on battery power.
    case "${ups_status}" in
        *OB*) /usr/local/bin/python3 /usr/local/opnsense/scripts/apcupsbk650m2/battery_check.py || true ;;
    esac
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

# Remember when the current outage was first seen, so alerts can honor the
# notification grace period (same setting as the upssched debounce).
if [ ! -f "${OUTAGE_START_FILE}" ]; then
    touch "${OUTAGE_START_FILE}" 2>/dev/null || true
fi

log "Watchdog: UPS check failed (${fails}/${MAX_FAILS})"

if [ "${fails}" -ge "${MAX_FAILS}" ] && ! comm_alert_flag_fresh; then
    # Alert policy mirrors the upssched debounce: stay silent while the outage
    # is still inside the grace period, and never send a second alert when
    # upssched (COMMBAD/NOCOMM timer) already notified about this outage.
    now=$(date +%s)
    grace=$(comm_alert_grace)
    outage_start=$(stat -f '%m' "${OUTAGE_START_FILE}" 2>/dev/null || echo 0)
    case "${outage_start}" in
        ''|*[!0-9]*) outage_start=0 ;;
    esac
    if [ "${now}" -ge "$((outage_start + grace))" ] && ! alert_on_cooldown; then
        notify "${HOSTNAME}-UPS告警通知" "[${HOSTNAME}]上的UPS通信异常，watchdog 正在尝试重新连接"
        mark_alert_sent
        # Claim the outage in the shared flag so upssched will not double-alert.
        touch "${COMM_ALERT_FLAG}" 2>/dev/null || true
    fi
fi

if [ "${fails}" -ge "${MAX_FAILS}" ]; then
    # Recovery order follows field data for the BK650M2: when the UPS firmware
    # wedges its USB HID interface, a bus-level USB reset revived it 7/7 times
    # while plain NUT restarts never did. The reset-usb action also restarts
    # all of NUT, so it covers the transient driver/daemon issues a soft
    # restart would fix; the weaker restarts only follow as fallbacks.
    log "Watchdog: attempting USB reset"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh reset-usb || true
    sleep 5

    next_status=$(probe_ups) || next_status=""
    if [ -n "${next_status}" ]; then
        recover "[${HOSTNAME}]上的UPS已通过 USB 重置重新连接"
        exit 0
    fi

    log "Watchdog: USB reset failed, attempting soft NUT restart"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh restart || true
    sleep 5

    next_status=$(probe_ups) || next_status=""
    if [ -n "${next_status}" ]; then
        recover "[${HOSTNAME}]上的UPS已通过 watchdog 软重启重新连接"
        exit 0
    fi

    log "Watchdog: soft restart failed, attempting force restart"
    /usr/local/opnsense/scripts/apcupsbk650m2/service.sh force-restart || true
    sleep 5

    next_status=$(probe_ups) || next_status=""
    if [ -n "${next_status}" ]; then
        recover "[${HOSTNAME}]上的UPS已通过 watchdog 深度重启重新连接"
        exit 0
    fi

    log "Watchdog: failed to reconnect UPS"
fi
