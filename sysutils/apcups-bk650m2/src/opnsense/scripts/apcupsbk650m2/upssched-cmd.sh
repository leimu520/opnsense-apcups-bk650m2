#!/bin/sh

HOSTNAME=$(hostname)
UPS_NAME="BK650M2"
STATE_DIR="/var/db/nut"
COMM_ALERT_FLAG="${STATE_DIR}/apcups_comm_alert_sent"
NOTIFY_CONF="/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf"

# Connection-loss notifications can be turned off in the notification settings.
# Syslog records and state flags are kept either way.
comm_notify_enabled() {
    [ -f "${NOTIFY_CONF}" ] && /usr/bin/grep -q '"comm_alert_enabled"[[:space:]]*:[[:space:]]*true' "${NOTIFY_CONF}"
}

# The comm alert flag is only trusted for 1 hour. When the watchdog recovers
# the UPS by restarting upsmon, no COMMOK event ever fires (the fresh upsmon
# instance starts in the OK state), so without an expiry the flag would stick
# around and suppress the alert for the next outage.
comm_alert_flag_fresh() {
    [ -f "${COMM_ALERT_FLAG}" ] || return 1
    now=$(/bin/date +%s)
    mtime=$(/usr/bin/stat -f '%m' "${COMM_ALERT_FLAG}" 2>/dev/null || echo 0)
    [ "${now}" -gt 0 ] && [ $((now - mtime)) -lt 3600 ]
}

# Helper to read a single UPS variable. Uses stdbuf -o0 to tolerate upsc segfault after output.
upsc_var() {
    /usr/bin/stdbuf -o0 /usr/local/bin/upsc "${UPS_NAME}@localhost" "${1}" 2>/dev/null | tail -n 1
}

# Default to 30 minutes if runtime cannot be read.
runtime_minutes() {
    runtime_sec=$(upsc_var "battery.runtime")
    if [ -z "${runtime_sec}" ] || ! [ "${runtime_sec}" -eq "${runtime_sec}" ] 2>/dev/null; then
        echo "未知"
        return
    fi
    minutes=$(( (runtime_sec + 59) / 60 ))
    if [ "${minutes}" -lt 1 ]; then
        minutes=1
    fi
    echo "${minutes}"
}

# Send notification through the dispatcher. Failures are logged but not fatal.
send_notify() {
    subject="${1}"
    body="${2}"
    /usr/local/bin/python3 /usr/local/opnsense/scripts/apcupsbk650m2/notify.py \
        "${subject}" "${body}" || true
}

case "${1:-}" in
    onbatt_alert)
        logger -t apcups-bk650m2 "UPS switched to battery power"
        SUBJECT="${HOSTNAME}-UPS告警通知"
        BODY="[${HOSTNAME}]上的UPS已进入电池供电模式，预计续航$(runtime_minutes)分钟，请及时检查市电情况或关闭其他设备"
        send_notify "${SUBJECT}" "${BODY}"
        ;;
    online_alert)
        logger -t apcups-bk650m2 "UPS back on utility power"
        SUBJECT="${HOSTNAME}-UPS恢复通知"
        BODY="[${HOSTNAME}]上的UPS已恢复市电供电，告警解除"
        send_notify "${SUBJECT}" "${BODY}"
        ;;
    battery_check)
        /usr/local/bin/python3 /usr/local/opnsense/scripts/apcupsbk650m2/battery_check.py
        ;;
    reset_battery_alert)
        rm -f /var/db/nut/apcups_battery_alert_sent
        logger -t apcups-bk650m2 "Battery alert state reset"
        ;;
    lowbatt_alert)
        logger -t apcups-bk650m2 "UPS low battery"
        charge=$(upsc_var "battery.charge")
        [ -z "${charge}" ] && charge="低"
        SUBJECT="${HOSTNAME}-UPS告警通知"
        BODY="[${HOSTNAME}]上的UPS电池容量剩余${charge}%，请及时检查市电情况或关闭其他设备！"
        send_notify "${SUBJECT}" "${BODY}"
        ;;
    commbad_alert)
        logger -t apcups-bk650m2 "UPS communication lost"
        # Only reached when the loss persisted past the upssched grace timer.
        if ! comm_alert_flag_fresh; then
            mkdir -p "${STATE_DIR}"
            touch "${COMM_ALERT_FLAG}"
            if comm_notify_enabled; then
                SUBJECT="${HOSTNAME}-UPS告警通知"
                BODY="[${HOSTNAME}]上的UPS通信中断，无法获取UPS状态，请检查USB连接或UPS电源"
                send_notify "${SUBJECT}" "${BODY}"
            fi
        fi
        ;;
    commok_alert)
        logger -t apcups-bk650m2 "UPS communication restored"
        if [ -f "${COMM_ALERT_FLAG}" ]; then
            if comm_alert_flag_fresh && comm_notify_enabled; then
                SUBJECT="${HOSTNAME}-UPS恢复通知"
                BODY="[${HOSTNAME}]上的UPS通信已恢复，UPS状态获取正常"
                send_notify "${SUBJECT}" "${BODY}"
            fi
            rm -f "${COMM_ALERT_FLAG}"
        fi
        ;;
    nocomm_alert)
        logger -t apcups-bk650m2 "UPS not communicating"
        # Skip when we already alerted for this outage (fresh flag); NOCOMM is
        # only useful when no COMMBAD alert has gone out (e.g. upsd itself died).
        if comm_notify_enabled && ! comm_alert_flag_fresh; then
            SUBJECT="${HOSTNAME}-UPS告警通知"
            BODY="[${HOSTNAME}]上的UPS长时间无响应，请检查UPS是否开机以及USB连接是否正常"
            send_notify "${SUBJECT}" "${BODY}"
        fi
        ;;
    onbatt_shutdown|lowbatt_shutdown)
        logger -t apcups-bk650m2 "UPS shutdown policy triggered: ${1}"
        /usr/local/sbin/upsmon -c fsd
        ;;
    *)
        logger -t apcups-bk650m2 "Ignored upssched command: ${1:-empty}"
        ;;
esac
