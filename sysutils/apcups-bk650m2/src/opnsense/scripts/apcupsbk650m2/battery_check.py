#!/usr/local/bin/python3
"""
Periodically check UPS battery charge while on battery power and send
a notification when it drops below the configured threshold.
"""

import json
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path

CONFIG_PATH = "/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf"
STATE_FILE = "/var/db/nut/apcups_battery_alert_sent"


def log(msg):
    sys.stderr.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")


def load_config():
    try:
        return json.loads(Path(CONFIG_PATH).read_text(encoding="utf-8"))
    except Exception as e:
        log(f"Failed to load config: {e}")
        return {"enabled": False}


def get_ups_vars(target="BK650M2@localhost"):
    try:
        output = subprocess.check_output(
            ["/usr/bin/stdbuf", "-o0", "/usr/local/bin/upsc", target],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
    except subprocess.CalledProcessError as e:
        output = e.output or ""
    except Exception as e:
        log(f"upsc failed: {e}")
        return {}

    vars = {}
    for line in output.splitlines():
        parts = line.split(":", 1)
        if len(parts) == 2:
            vars[parts[0].strip()] = parts[1].strip()
    return vars


def alert_already_sent():
    return Path(STATE_FILE).exists()


def mark_alert_sent():
    try:
        Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
        Path(STATE_FILE).touch()
    except Exception as e:
        log(f"Failed to mark alert sent: {e}")


def reset_alert():
    try:
        Path(STATE_FILE).unlink(missing_ok=True)
    except Exception as e:
        log(f"Failed to reset alert: {e}")


def send_notification(subject, body):
    try:
        subprocess.run(
            ["/usr/local/bin/python3", "/usr/local/opnsense/scripts/apcupsbk650m2/notify.py", subject, body],
            check=False,
            timeout=60,
        )
    except Exception as e:
        log(f"Failed to send notification: {e}")


def main():
    cfg = load_config()
    if not cfg.get("enabled"):
        log("Plugin disabled")
        return

    vars = get_ups_vars()
    if not vars:
        log("No UPS data")
        return

    status = vars.get("ups.status", "")
    charge_str = vars.get("battery.charge", "")

    # Reset alert state when back on utility power
    if "OL" in status:
        reset_alert()
        log("On utility power, alert state reset")
        return

    if "OB" not in status:
        log(f"Unknown status: {status}")
        return

    if not cfg.get("battery_alert_enabled"):
        log("Battery alert disabled")
        return

    try:
        charge = int(float(charge_str))
    except ValueError:
        log(f"Invalid battery charge: {charge_str}")
        return

    threshold = int(cfg.get("battery_alert_threshold", 50))

    if charge <= threshold and not alert_already_sent():
        hostname = socket.gethostname()
        subject = f"{hostname}-UPS告警通知"
        body = f"[{hostname}]上的UPS电池容量剩余{charge}%，请及时检查市电情况或关闭其他设备！"
        send_notification(subject, body)
        mark_alert_sent()
        log(f"Battery alert sent at {charge}%")
    else:
        log(f"Battery charge {charge}%, threshold {threshold}%, alert sent: {alert_already_sent()}")

    # Percentage-based shutdown
    shutdown_mode = cfg.get("shutdown_mode", "timer")
    shutdown_threshold = int(cfg.get("battery_shutdown_threshold", 30))
    if shutdown_mode == "battery" and charge <= shutdown_threshold:
        log(f"Battery shutdown threshold reached at {charge}%, initiating shutdown")
        try:
            subprocess.run(
                ["/usr/local/sbin/upsmon", "-c", "fsd"],
                check=False,
                timeout=30,
            )
        except Exception as e:
            log(f"Failed to initiate shutdown: {e}")


if __name__ == "__main__":
    main()
