# os-apcups-bk650m2 — APC UPS plugin for OPNsense

A purpose-built OPNsense plugin for APC Back-UPS units connected over USB,
developed and battle-tested on an **APC Back-UPS BK650M2-CH** running
OPNsense 26.1 / FreeBSD 14.3. It drives the UPS through
[Network UPS Tools](https://networkupstools.org/) (`nut`, `usbhid-ups`
driver) and adds the operational glue that generic NUT front-ends lack:
self-healing watchdog, tolerant status parsing, Chinese-first UI with
e-mail / WeCom / SMS notifications, an NUT server mode for LAN clients,
and a dashboard widget.

> **Why this plugin?** The official `os-nut` plugin generates configurations
> that can fail to start on APC USB units (missing `port=auto`), and `upsc`
> on this platform intermittently segfaults after printing its data
> ([opnsense/plugins#5509](https://github.com/opnsense/plugins/issues/5509)).
> On several APC firmwares the USB HID interface itself also wedges every
> few days and only a bus-level USB reset recovers it. This plugin was
> built to survive all three. It is not a replacement for the `nut`
> package — it manages NUT for you.

## Features

- **Status page** — connection state, UPS status, battery charge, runtime,
  load, input voltage, model and serial; auto-refresh every 10 s.
- **Diagnostics page** — one click collects `upsc` output, NUT service
  status, USB device tree, NUT config files, MONITOR lines and the last
  80 UPS-related syslog lines.
- **Settings** — enable/disable, UPS name, driver, port, USB vendor ID
  (APC = `051d`, editable for other USB HID brands), NUT monitor account.
- **UPS Server mode** — expose the UPS on TCP 3493 to LAN clients
  (Synology DSM "NUT server", Proxmox `nut-client`, WinNUT, any NUT
  secondary) with a dedicated read-only `upsmon slave` account. The
  firewall stays the master and performs the final powerdown.
- **Shutdown policies** — disabled / on low battery / at a battery-charge
  percentage / after N seconds on battery.
- **Notifications** — e-mail (SMTP, SSL/STARTTLS), WeCom (企业微信) bot and
  app messages, Alibaba Cloud SMS or a custom HTTP endpoint. Power events
  (on battery / online / low battery) and connection events
  (COMMBAD / COMMOK / NOCOMM) are sent through one dispatcher
  (`notify.py`).
- **Notification hardening** — connection alerts are debounced: a drop
  that recovers within the grace period (default 120 s, configurable
  30–3600 s) stays silent; a sustained outage alerts once. Alerts can be
  turned off entirely on the notification page while auto-recovery keeps
  running.
- **Watchdog self-healing** — every 2 minutes a cron job probes the UPS;
  after 3 consecutive failures it escalates: soft restart →
  **bus-level USB reset** → forced driver restart. Field data from a
  BK650M2 (7 wedges in 10 days) shows soft/forced driver restarts never
  recover a wedged APC firmware while a USB reset always does — hence the
  ordering.
- **Dashboard widget** — Lobby widget (JS) plus a legacy PHP widget,
  showing UPS state and battery charge.

## Requirements

- OPNsense 24.x+ (developed on 26.1, FreeBSD 14.3)
- The `nut` package (installed automatically as a plugin dependency)
- An APC UPS on USB (vendor ID `051d`; other USB HID vendors work by
  changing the VendorID setting)
- Do **not** run alongside `os-nut` — both manage `/usr/local/etc/nut/*`

## Install (development / manual)

Copy this repository to your OPNsense box, then:

```sh
sh install-dev.sh
```

Then open `https://<opnsense-host>/ui/apcups/`. Uninstall with
`uninstall-dev.sh`. See [INSTALL.md](INSTALL.md) for details and for
building a proper `os-apcups-bk650m2-x.y.z.txz` package inside an
OPNsense plugins tree (`/usr/plugins/sysutils/apcups-bk650m2`).

## UPS Server (NUT server mode)

1. On the settings page enable **UPS Server**, set a client user/password.
2. Allow TCP 3493 from the interface your clients sit on (Firewall →
   Rules). Note that NUT allows anonymous *reads* by default — standard
   NUT behaviour; credentials are required to register a monitoring
   session (`LOGIN`) and privileged operations are reserved for the
   firewall's local `master` account.
3. Point your clients at the firewall:

```
MONITOR <upsname>@<firewall-ip> 1 <serverUser> <serverPassword> slave
```

| Client | Setting |
|---|---|
| Synology DSM | Hardware & Power → UPS → "NUT server" |
| Proxmox VE | `apt install nut-client`, set MODE=netclient |
| Windows | [WinNUT-Client](https://github.com/nutdotnet/WinNUT-client) |

## CLI

```sh
upsc BK650M2@localhost
configctl apcupsbk650m2 status BK650M2@localhost
configctl apcupsbk650m2 diagnostics BK650M2@localhost
configctl apcupsbk650m2 restart          # soft restart (keeps the driver)
configctl apcupsbk650m2 force-restart    # stop driver, start fresh
configctl apcupsbk650m2 reset-usb        # deep recovery incl. USB reset
```

## Repository layout

```
sysutils/apcups-bk650m2/     OPNsense plugin tree (drop into /usr/plugins)
  Makefile, pkg-descr
  src/opnsense/mvc/...       model, controllers, forms, view
  src/opnsense/scripts/...   status.php, diagnostics.php, service.sh,
                             watchdog.sh, upssched-cmd.sh, notify.py,
                             battery_check.py
  src/opnsense/service/...   configd actions + NUT config templates
  src/opnsense/www/...       dashboard widget
install-dev.sh               quick install to a live OPNsense
uninstall-dev.sh
```

## 中文说明

这是为 APC Back-UPS（USB 连接）打造的 OPNsense 专用插件，在 BK650M2-CH +
OPNsense 26.1 上长期实测。它底层使用 NUT（`usbhid-ups` 驱动），解决了
os-nut 在 APC USB 场景下的一系列实际问题：

- os-nut 生成的配置缺少 `port=auto` 导致 NUT 无法启动；
- 平台 `upsc` 命令输出数据后随机段错误（[opnsense/plugins#5509](https://github.com/opnsense/plugins/issues/5509)），本插件全部调用均
  `stdbuf -o0` + 解析输出而非依赖退出码；
- 部分 APC 固件的 USB HID 接口每隔一两天会死锁，重启驱动无效、只有
  总线级 USB 重置能恢复——watchdog 每 2 分钟探测，连续 3 次失败后按
  "软重启 → USB 重置 → 深度重启"自动恢复；
- 掉线通知带防抖（默认 120 秒宽限期，闪断不打扰），可在通知页关闭；
- 通知渠道：邮件（SSL/STARTTLS）、企业微信机器人/应用、阿里云短信、
  自定义 HTTP；
- UPS Server 模式：开放 TCP 3493 给群晖/Proxmox/WinNUT 等从机客户端，
  独立只读账号，防火墙保持 master 负责最终断电；
- 仪表盘小组件、诊断页一键收集信息、界面全中文。

安装与更多细节见 [INSTALL.md](INSTALL.md) 与
[PROJECT_NOTES.md](PROJECT_NOTES.md)（中文，含完整设计记录与排查手册）。

## License

[BSD-2-Clause](LICENSE)
