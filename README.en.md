<div align="right">

[简体中文](README.md) | **English**

</div>

# os-apcups-bk650m2 — APC UPS plugin for OPNsense

A purpose-built OPNsense plugin for APC Back-UPS units connected over USB,
developed and battle-tested on an **APC Back-UPS BK650M2-CH** running
OPNsense 26.1 / FreeBSD 14.3. It drives the UPS through
[Network UPS Tools](https://networkupstools.org/) (`nut`, `usbhid-ups`
driver) and adds the operational glue that generic NUT front-ends lack:
a self-healing watchdog, tolerant status parsing, e-mail / WeCom / SMS
notifications, an NUT server mode for LAN clients, and a dashboard widget.

> **Why this plugin?** The official `os-nut` plugin generates configurations
> that can fail to start on APC USB units (missing `port=auto`), and `upsc`
> on this platform intermittently segfaults after printing its data
> ([opnsense/plugins#5509](https://github.com/opnsense/plugins/issues/5509)).
> On several APC firmwares the USB HID interface itself also wedges every
> few days — driver restarts do not recover it, only a bus-level USB reset
> does. This plugin was built to survive all three. It is not a replacement
> for the `nut` package — it manages NUT for you.

**Table of contents**

1. [Features](#features)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [What gets installed where](#what-gets-installed-where)
5. [Configuration](#configuration)
6. [UPS Server (NUT server mode)](#ups-server-nut-server-mode)
7. [Watchdog self-healing](#watchdog-self-healing)
8. [Dashboard widget](#dashboard-widget)
9. [Diagnostics & troubleshooting](#diagnostics--troubleshooting)
10. [Building the .txz package](#building-the-txz-package)
11. [Compatibility](#compatibility)
12. [FAQ](#faq)
13. [License](#license)

## Features

- **Status page** — connection state, UPS status, battery charge, runtime,
  load, input voltage, model and serial; auto-refresh every 10 s (paused
  while the browser tab is hidden).
- **Diagnostics page** — one click collects `upsc` output, NUT service
  status, USB device tree, NUT config files, MONITOR lines and the last
  80 UPS-related syslog lines.
- **Shutdown policies** — disabled / on low battery / at a battery-charge
  percentage / after N seconds on battery.
- **Notifications** — e-mail (SMTP, SSL/STARTTLS), WeCom (企业微信) bot and
  app messages, Alibaba Cloud SMS or a custom HTTP endpoint, with a
  test-send button per channel.
- **UPS Server mode** — expose the UPS on TCP 3493 to LAN clients
  (Synology DSM, Proxmox, WinNUT, any NUT secondary) with a dedicated
  read-only account. The firewall stays the master and performs the final
  powerdown.
- **Watchdog self-healing** — every minute a cron job probes the UPS and
  escalates on failure: **bus-level USB reset** → soft restart → forced
  driver restart (see [Watchdog](#watchdog-self-healing)).
- **Dashboard widget** — Lobby widget (JS) plus a legacy PHP widget,
  showing UPS state and battery charge.

## Requirements

- OPNsense 24.x or later (developed and tested on 26.1 / FreeBSD 14.3)
- The `nut` package (installed automatically when built as a package;
  for the dev install see [Quick start](#quick-start))
- An APC UPS on USB — default vendor ID `051d`; other USB HID brands work
  by changing the VendorID setting
- **Do not** run it alongside the official `os-nut` plugin — both manage
  `/usr/local/etc/nut/*`

## Quick start

1. Uninstall or disable `os-nut` if it is installed
   (**System → Firmware → Plugins**).
2. Copy this repository to your OPNsense box, e.g. `/root/opnsense-apcups-bk650m2`,
   then from SSH/console:

   ```sh
   pkg install -y nut          # dev install must provide the NUT package
   cd /root/opnsense-apcups-bk650m2
   sh install-dev.sh
   ```

   `install-dev.sh` copies the plugin files into `/usr/local/opnsense`,
   restarts configd, renders the NUT templates, clears the menu caches and
   restarts the web UI. `uninstall-dev.sh` removes everything again.
3. Open `https://<opnsense-host>/ui/apcups/`, tick **启用** (Enable), review
   the defaults and press Save. The status page should show 在线 (online)
   within seconds.

When built as a proper package (`os-apcups-bk650m2-x.y.z.txz`, see
[below](#building-the-txz-package)) the `nut` dependency is pulled in
automatically.

## What gets installed where

| Location | Purpose |
|---|---|
| `/usr/local/opnsense/mvc/app/{models,controllers,views}/OPNsense/ApcUps/` | Model, REST API controllers, forms and the page view |
| `/usr/local/opnsense/service/conf/actions.d/actions_apcupsbk650m2.conf` | configd actions (`start/stop/restart/force-restart/reset-usb/status/diagnostics`) |
| `/usr/local/opnsense/scripts/apcupsbk650m2/` | Backend scripts: `status.php`, `diagnostics.php`, `service.sh`, `watchdog.sh`, `upssched-cmd.sh`, `notify.py`, `battery_check.py` |
| `/usr/local/opnsense/service/templates/OPNsense/ApcUps/` | Config templates, rendered by `configctl template reload OPNsense/ApcUps` |
| `/usr/local/opnsense/www/js/widgets/ApcUps.js` (+ `Metadata/`) | Dashboard widget |
| `/usr/local/www/widgets/widgets/apcups.widget.php` | Legacy dashboard widget |

The templates render the live configuration:

| Rendered file | Content |
|---|---|
| `/etc/rc.conf.d/nut`, `/etc/rc.conf.d/nut_upsmon` | rc enable flags |
| `/usr/local/etc/nut/nut.conf` | NUT mode (`standalone` / `none`) |
| `/usr/local/etc/nut/ups.conf` | Driver section: `usbhid-ups`, `port=auto`, `user=root`, `pollonly`, `pollinterval=15`, low-battery overrides |
| `/usr/local/etc/nut/upsd.conf` | LISTEN addresses, `MAXAGE 60` |
| `/usr/local/etc/nut/upsd.users` | Monitor accounts (master, plus the UPS Server client account) |
| `/usr/local/etc/nut/upsmon.conf` | MONITOR line, shutdown command, notify flags, `DEADTIME 45` |
| `/usr/local/etc/nut/upssched.conf` | Event timers (power events, connection debounce, shutdown timers) |
| `/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf` | JSON consumed by `notify.py` |
| `/etc/cron.d/apcups-bk650m2` | Watchdog schedule (every minute) |

## Configuration

### General (设置页)

| Field | Default | Notes |
|---|---|---|
| 启用 (Enable) | on | Master switch; renders all NUT configs |
| UPS 名称 | `BK650M2` | NUT device name used by upsc/upsmon |
| 驱动 | `usbhid-ups` | Keep for APC USB units |
| 端口 | `auto` | **Must be `auto`** for USB — this is the setting os-nut misses |
| 监控用户名 / 密码 | `monuser` / `apcupsbk650m2` | Local NUT master account |
| USB VendorID | `051d` | APC; other USB HID vendors can be entered |
| UPS Server / 客户端用户名 / 密码 | off / `upsclient` / – | See [UPS Server](#ups-server-nut-server-mode) |

### Shutdown policies (关机策略)

| Mode | Behaviour |
|---|---|
| 不关机 (no shutdown) | Monitor and notify only |
| UPS 低电量时关机 (on low battery) | Shutdown when the UPS reports low battery (`override.battery.*.low`) |
| 电量降到指定百分比后关机 (at charge %) | Checked every minute while on battery; triggers `upsmon -c fsd` at the threshold |
| 电池供电 N 秒后关机 (N s on battery) | `upssched` timer starts on battery, cancelled when mains returns |

### Notifications (通知页)

Pick any combination of channels; each has a **test-send button**:

- **E-mail** — SMTP host/port; port 465 uses implicit SSL, 587/25 use
  STARTTLS. QQ/163 mailboxes need an app-specific 授权码, and the sender
  address must match the SMTP username.
- **企业微信机器人 (WeCom bot)** — webhook URL.
- **企业微信应用 (WeCom app)** — CorpID / CorpSecret / AgentId / touser.
- **SMS** — Alibaba Cloud (sign + template) or a custom JSON HTTP endpoint.
- **电量阈值通知 (charge threshold alert)** — checked every minute while on
  battery; one alert per discharge below the percentage.
- **启用掉线通知 (connection alerts)** — master switch for connection events
  (COMMBAD / COMMOK / NOCOMM and watchdog recoveries). When off, recovery
  still runs — only the push messages are silenced.

Connection alerts are **debounced on every path**: the upssched debounce
timer, the watchdog and NOCOMM all honour the grace period
(掉线通知宽限期, default 120 s, range 30–3600 s). An outage that heals —
by itself or via the watchdog — inside the grace window sends **no
notification at all**; before a sustained outage alerts, a final
"still unreachable" re-check runs, so a recovered UPS is never reported as
down. Every outage produces at most one alert + one recovery pair (the
three alert paths share a flag file and never duplicate). BK650M2 firmware
wedges are usually repaired within 2-3 minutes — set the grace period to
600 if you do not want to hear about them. All messages go through one
dispatcher (`notify.py`), and the whole notification config is just the
rendered JSON file `notify.conf` (its input fields are validated to keep
the JSON unbreakable).

## UPS Server (NUT server mode)

Let NAS/VM hosts shut down gracefully from this UPS — the firewall is the
NUT *master* (owns the USB device and the final powerdown), clients are
*secondaries*.

1. **设置页 (Settings)** → tick **启用 UPS 网络服务（UPS Server）**, set a
   client password, Save. upsd now listens on `0.0.0.0`/`::` port 3493.
2. **Firewall → Rules**: allow TCP 3493 from the interface/subnet your
   clients sit on.
3. Configure the clients as *netclient* / secondary:

| Client | Where |
|---|---|
| Synology DSM | 控制面板 → 硬件和电源 → UPS → 启用 UPS 支持，类型选“Synology NUT 服务器”，填防火墙 IP 和客户端账号 |
| Proxmox VE | `nut-client` package, `MODE=netclient` + `MONITOR` line |
| Windows | [WinNUT-Client](https://github.com/nutdotnet/WinNUT-client) |

   Generic NUT client line: `MONITOR <upsname>@<firewall-ip> 1 <user> <pass> slave`

4. Verify from the client: `upsc BK650M2@<firewall-ip>`.

Security model: NUT allows anonymous *reads* by default (standard NUT
behaviour — status values are not sensitive), but registering a monitoring
session (`LOGIN`) requires the client account, and privileged commands
(`MASTER`, instant commands) are only available to the firewall's local
master account — **LAN clients can watch the UPS but can never shut your
firewall down**. Credential files are rendered `root:nut 0640`. If the
client password is empty, the client account is not generated at all and
local monitoring keeps working.

## Watchdog self-healing

The BK650M2 (like several APC firmwares) periodically wedges its USB HID
interface: the device stays on the bus, `usbhid-ups` keeps running, but
even the device descriptor becomes unreadable and only a bus-level reset
recovers it. Field data from one unit: 7 wedges in 10 days, driver
restarts recovered 0 of them, USB reset recovered 7/7. The watchdog is
built around that reality:

1. A cron job runs `watchdog.sh` **every minute**. A healthy probe is a
   single `upsc … ups.status` (3 quick retries, output-parsed, tolerant of
   the platform's `upsc` segfault).
2. **3 consecutive failed runs (~2-3 minutes)** trigger the escalation,
   ordered by field data: `service.sh reset-usb` (stops NUT and
   `usbconfig … reset`s the APC device — recovered 7/7 wedges) →
   `service.sh restart` (soft, driver untouched) → `service.sh
   force-restart` (driver fully stopped and restarted) as the last resort.
   A run lock prevents concurrent instances across cron ticks.
3. Every step is logged (`logger -t apcups-bk650m2`, visible in **Reporting
   → System Log → Log Files**), and notifications follow the
   [connection-alert policy](#notifications-通知页).

State files live in `/var/db/nut/` (`apcups_watchdog_failures`,
`apcups_watchdog_outage_start`, `apcups_watchdog_last_alert`,
`apcups_comm_alert_sent`). Expected outage per wedge is roughly
**3 minutes** from drop to full recovery.

While on battery, the watchdog also runs `battery_check.py` every minute:
the charge-threshold alert (once per discharge) and the "shut down at
charge %" policy are driven by it.

## Dashboard widget

Add the "APC UPS BK650M2" widget from the Lobby dashboard — first line
shows UPS state (在线/电池供电/离线), second line the battery charge. The
legacy PHP widget (`src/www/widgets/`) is included for older dashboards.

## Diagnostics & troubleshooting

The 诊断 tab (or `configctl apcupsbk650m2 diagnostics BK650M2@localhost`)
collects everything in one shot: `upsc`, `service nut status`,
`service nut_upsmon status`, `usbconfig`, NUT config files, the MONITOR
line and the last 80 UPS-related syslog lines.

| Symptom | Likely cause / fix |
|---|---|
| nut fails: "you must specify a port name" | 端口 must be `auto` (Settings → 端口), then Save and 重启 NUT |
| `upsc` prints data then crashes ("signal 11") | Known platform quirk ([#5509](https://github.com/opnsense/plugins/issues/5509)); harmless here — every internal caller parses output instead of exit codes |
| Status flips between 已断开/已连接 | Normal during a firmware wedge; the watchdog will USB-reset within ~3 minutes, check the system log for `apcups-bk650m2` |
| Driver start: "Can't claim USB device" / "No matching HID UPS found" | Kernel HID claim; try a loader.conf quirk: `hw.usb.quirk.0="0x051d 0x0002 0 0xffff UQ_HID_IGNORE"` (requires reboot; usually unnecessary) |
| Notifications fail | Use the per-channel 测试 button on the 通知 page — it shows the raw backend error |
| Both this plugin and os-nut installed | Uninstall os-nut; both write `/usr/local/etc/nut/*` |

## Building the .txz package

The repository layout already matches the OPNsense plugins tree. Copy
`sysutils/apcups-bk650m2` into a OPNsense plugins checkout
(`/usr/plugins/sysutils/apcups-bk650m2`) and build with the standard
OPNsense tools workflow; the package name will be
`os-apcups-bk650m2-x.y.z.txz` (`Makefile` declares `PLUGIN_DEPENDS=nut`).

## Compatibility

- Tested on: OPNsense 26.1.9 / FreeBSD 14.3-RELEASE, APC Back-UPS
  BK650M2-CH (vendor `051d`, USB HID).
- Any APC USB HID unit (Back-UPS / Smart-UPS with USB) should work with
  the defaults; other USB HID vendors can set their VendorID.
- Out of scope: SNMP, serial, multiple UPS units — this plugin is
  deliberately focused on one local USB UPS.

## FAQ

**Is a `upsc` segfault in my logs a problem?**
No. On this platform `upsc` intermittently crashes after printing its
data ([upstream issue](https://github.com/opnsense/plugins/issues/5509)).
The plugin always runs it through `stdbuf -o0` and parses the output, so
monitoring, watchdog and notifications are unaffected.

**Why does my UPS "disconnect" every few days?**
That is the APC firmware USB wedge described above — a device-side
firmware bug, not an OPNsense/NUT fault. The watchdog detects it in ~2-3
minutes and recovers it automatically in about 3.

**Can I run this next to os-nut?**
No. Both generate `/usr/local/etc/nut/*`.

**Does the UPS Server expose my UPS without authentication?**
Reads are anonymous by default (standard NUT). Registering a session
needs the client account, and nothing a LAN client can do will shut the
firewall down.

**Does the UI follow the OPNsense language setting?**
Not yet — the interface strings are currently Chinese only. Planned
improvement: switch to the standard OPNsense gettext mechanism so the UI
follows the system language automatically.

## License

[BSD-2-Clause](LICENSE)
