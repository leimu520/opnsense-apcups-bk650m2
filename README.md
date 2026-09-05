<div align="right">

**简体中文** | [English](README.en.md)

</div>

# os-apcups-bk650m2 — APC UPS 专用 OPNsense 插件

一个为 USB 连接的 APC Back-UPS 打造的 OPNsense 专用插件，在 **APC Back-UPS
BK650M2-CH + OPNsense 26.1 / FreeBSD 14.3** 上长期开发实测。底层通过
[Network UPS Tools](https://networkupstools.org/)（`nut`，`usbhid-ups`
驱动）驱动 UPS，并补齐通用 NUT 前端缺失的运维能力：自愈 watchdog、
容错的状态解析、全中文界面、邮件 / 企业微信 / 短信通知、面向局域网客户端的
NUT 服务模式，以及仪表盘小组件。

> **为什么要做这个插件？** 官方 `os-nut` 插件生成的配置在 APC USB 设备上可能
> 无法启动（缺少 `port=auto`），且该平台的 `upsc` 会在输出数据后随机段错误
> （[opnsense/plugins#5509](https://github.com/opnsense/plugins/issues/5509)）。
> 此外部分 APC 固件的 USB HID 接口每隔几天就会死锁一次——重启驱动无效，只有
> 总线级 USB 重置能恢复。本插件为同时扛住这三个问题而生。它不替代 `nut`
> 软件包，而是替你管好 NUT。

**目录**

1. [功能特性](#功能特性)
2. [环境要求](#环境要求)
3. [快速开始](#快速开始)
4. [安装了哪些文件](#安装了哪些文件)
5. [配置说明](#配置说明)
6. [UPS Server（NUT 网络服务）](#ups-servernut-网络服务)
7. [Watchdog 自愈](#watchdog-自愈)
8. [仪表盘小组件](#仪表盘小组件)
9. [诊断与排障](#诊断与排障)
10. [构建 .txz 包](#构建-txz-包)
11. [兼容性](#兼容性)
12. [常见问题](#常见问题)
13. [许可证](#许可证)

## 功能特性

- **状态页** — 连接状态、UPS 状态、电量、续航、负载、输入电压、型号与序列号，
  每 10 秒自动刷新（浏览器标签页不可见时自动暂停）。
- **诊断页** — 一键收集 `upsc` 输出、NUT 服务状态、USB 设备树、NUT 配置文件、
  MONITOR 行和最近 80 行 UPS 相关系统日志。
- **关机策略** — 不关机 / 低电量关机 / 电量降到指定百分比关机 / 电池供电 N 秒后关机。
- **通知** — 邮件（SMTP，SSL/STARTTLS）、企业微信机器人与应用消息、阿里云短信
  或自定义 HTTP 接口，每个渠道可单独测试发送。
- **UPS Server 模式** — 通过 TCP 3493 向局域网客户端（群晖 DSM、Proxmox、
  WinNUT 及任何 NUT 从机）开放 UPS，使用独立只读账号；防火墙保持 master，
  负责最终断电。
- **Watchdog 自愈** — 每分钟 cron 探测 UPS，失败后按
  **总线级 USB 重置** → 软重启 → 深度重启逐级恢复（见 [Watchdog 自愈](#watchdog-自愈)）。
- **仪表盘小组件** — Lobby JS 小组件 + 旧版 PHP 小组件，显示 UPS 状态与电量。

## 环境要求

- OPNsense 24.x 及以上（开发实测：26.1 / FreeBSD 14.3）
- `nut` 软件包（构建为 .txz 包安装时自动带入；开发安装见[快速开始](#快速开始)）
- USB 连接的 APC UPS — 默认 VendorID `051d`；其他 USB HID 品牌改 VendorID 即可
- **不要**与官方 `os-nut` 插件同时启用 — 两者都会写 `/usr/local/etc/nut/*`

## 快速开始

1. 如已安装 `os-nut`，先卸载或停用（**系统 → 固件 → 插件**）。
2. 把本仓库拷贝到 OPNsense，例如 `/root/opnsense-apcups-bk650m2`，然后 SSH 执行：

   ```sh
   pkg install -y nut          # 开发安装需自备 NUT 软件包
   cd /root/opnsense-apcups-bk650m2
   sh install-dev.sh
   ```

   `install-dev.sh` 会把插件文件复制到 `/usr/local/opnsense`、重启 configd、
   渲染 NUT 模板、清理菜单缓存并重启 Web UI。`uninstall-dev.sh` 可整体卸载。
3. 打开 `https://<opnsense-host>/ui/apcups/`，勾选**启用**，确认默认值后保存。
   状态页应在数秒内显示"在线"。

构建为正式包（`os-apcups-bk650m2-x.y.z.txz`，见[下文](#构建-txz-包)）时会自动
带入 `nut` 依赖。

## 安装了哪些文件

| 位置 | 用途 |
|---|---|
| `/usr/local/opnsense/mvc/app/{models,controllers,views}/OPNsense/ApcUps/` | 模型、REST API 控制器、表单与页面视图 |
| `/usr/local/opnsense/service/conf/actions.d/actions_apcupsbk650m2.conf` | configd 动作（`start/stop/restart/force-restart/reset-usb/status/diagnostics`） |
| `/usr/local/opnsense/scripts/apcupsbk650m2/` | 后端脚本：`status.php`、`diagnostics.php`、`service.sh`、`watchdog.sh`、`upssched-cmd.sh`、`notify.py`、`battery_check.py` |
| `/usr/local/opnsense/service/templates/OPNsense/ApcUps/` | 配置模板，由 `configctl template reload OPNsense/ApcUps` 渲染 |
| `/usr/local/opnsense/www/js/widgets/ApcUps.js`（含 `Metadata/`） | 仪表盘小组件 |
| `/usr/local/www/widgets/widgets/apcups.widget.php` | 旧版仪表盘小组件 |

模板渲染出的运行配置：

| 渲染文件 | 内容 |
|---|---|
| `/etc/rc.conf.d/nut`、`/etc/rc.conf.d/nut_upsmon` | rc 启用开关 |
| `/usr/local/etc/nut/nut.conf` | NUT 模式（`standalone` / `none`） |
| `/usr/local/etc/nut/ups.conf` | 驱动段：`usbhid-ups`、`port=auto`、`user=root`、`pollonly`、`pollinterval=15`、低电量阈值覆写 |
| `/usr/local/etc/nut/upsd.conf` | LISTEN 地址、`MAXAGE 60` |
| `/usr/local/etc/nut/upsd.users` | 监控账号（master，及 UPS Server 客户端账号） |
| `/usr/local/etc/nut/upsmon.conf` | MONITOR 行、关机命令、通知标志、`DEADTIME 45` |
| `/usr/local/etc/nut/upssched.conf` | 事件定时器（电力事件、掉线防抖、关机定时器） |
| `/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf` | `notify.py` 消费的 JSON 配置 |
| `/etc/cron.d/apcups-bk650m2` | Watchdog 调度（每分钟） |

## 配置说明

### 通用（设置页）

| 字段 | 默认值 | 说明 |
|---|---|---|
| 启用 | 开 | 总开关；控制所有 NUT 配置的渲染 |
| UPS 名称 | `BK650M2` | upsc/upsmon 使用的 NUT 设备名 |
| 驱动 | `usbhid-ups` | APC USB 设备保持默认 |
| 端口 | `auto` | USB 场景**必须是 `auto`**——这正是 os-nut 缺失的配置 |
| 监控用户名 / 密码 | `monuser` / `apcupsbk650m2` | 本机 NUT master 账号 |
| USB VendorID | `051d` | APC；其他 USB HID 厂商可修改 |
| UPS Server / 客户端用户名 / 密码 | 关 / `upsclient` / – | 见 [UPS Server](#ups-servernut-网络服务) |

### 关机策略

| 模式 | 行为 |
|---|---|
| 不关机 | 只监控和通知 |
| UPS 低电量时关机 | UPS 上报低电量时关机（`override.battery.*.low`） |
| 电量降到指定百分比后关机 | 电池供电期间每分钟检查一次，达到阈值触发 `upsmon -c fsd` |
| 电池供电 N 秒后关机 | `upssched` 进入电池供电时启动定时器，来电即取消 |

### 通知（通知页）

各渠道可任意组合，每个渠道都有**测试发送按钮**：

- **邮件** — SMTP 主机/端口；465 端口走隐式 SSL，587/25 走 STARTTLS。
  QQ/163 邮箱需要授权码，且发件人地址必须与 SMTP 用户名一致。
- **企业微信机器人** — Webhook 地址。
- **企业微信应用** — CorpID / CorpSecret / AgentId / 接收用户。
- **短信** — 阿里云（签名 + 模板）或自定义 JSON HTTP 接口。
- **电量阈值通知** — 电池供电期间每分钟检查一次，低于阈值发送一次告警。
- **启用掉线通知** — 连接类事件（COMMBAD / COMMOK / NOCOMM 与 watchdog 恢复）
  的总开关。关闭后自动恢复照常运行，只是不再推送。

掉线通知**全路径防抖**：upssched 防抖定时器、watchdog、NOCOMM 三条路径都遵守
"掉线通知宽限期"（默认 120 秒，可配 30–3600 秒）。宽限期内自愈或被修复的掉线
**一条通知都不会发**；持续掉线在告警发送前还会做一次"仍然断连"复核。每次掉线
最多一组"告警 + 恢复"通知（三条告警路径共享标志文件，绝不重复）。BK650M2 固件
死锁通常 2-3 分钟内即被自动修复，若不想被打扰可把宽限期调到 600。所有消息经
统一分发器 `notify.py` 发送，整套通知配置就是渲染出的 JSON 文件 `notify.conf`
（相关输入字段已做字符校验，杜绝配置值破坏 JSON）。

## UPS Server（NUT 网络服务）

让 NAS / 虚拟化主机从这台 UPS 优雅关机——防火墙是 NUT *master*（独占 USB
设备和最终断电），客户端是 *secondary*。

1. **设置页** → 勾选**启用 UPS 网络服务（UPS Server）**，设置客户端密码并保存。
   upsd 开始监听 `0.0.0.0`/`::` 的 3493 端口。
2. **防火墙 → 规则**：放行客户端所在接口/子网到本机 TCP 3493。
3. 客户端按 *netclient* / 从机模式配置：

| 客户端 | 位置 |
|---|---|
| 群晖 DSM | 控制面板 → 硬件和电源 → UPS → 启用 UPS 支持，类型选“Synology NUT 服务器”，填防火墙 IP 和客户端账号 |
| Proxmox VE | `nut-client` 包，`MODE=netclient` + `MONITOR` 行 |
| Windows | [WinNUT-Client](https://github.com/nutdotnet/WinNUT-client) |

   通用 NUT 客户端配置行：`MONITOR <ups名>@<防火墙IP> 1 <用户> <密码> slave`

4. 客户端验证：`upsc BK650M2@<防火墙IP>`。

安全模型：NUT 默认允许匿名**读取**（标准行为——状态值不敏感），但注册监控会话
（`LOGIN`）需要客户端账号，特权命令（`MASTER`、即时命令）只有防火墙本机
master 账号可用——**局域网客户端只能看，永远关不了你的防火墙**。凭据文件渲染为
`root:nut 0640`；客户端密码留空时完全不生成客户端账号，本机监控不受影响。

## Watchdog 自愈

BK650M2（以及不少 APC 固件）的 USB HID 接口会周期性死锁：设备还在总线上、
`usbhid-ups` 进程还活着，但连设备描述符都读不出来，只有总线级重置能恢复。
实测数据：一台设备 10 天死锁 7 次，重启驱动 0 次成功，USB 重置 7/7 恢复。
watchdog 就是围绕这个现实设计的：

1. cron 每分钟运行一次 `watchdog.sh`。健康探测是一次 `upsc … ups.status`
   （3 次快速重试、解析输出内容而非退出码，兼容平台的 `upsc` 段错误）。
2. **连续 3 次失败（约 2-3 分钟）** 触发恢复，顺序按实测数据排列：
   `service.sh reset-usb`（停 NUT + `usbconfig … reset`，实测 7/7 有效）→
   `service.sh restart`（软重启，不动驱动）→ `service.sh force-restart`
   （驱动完全重启）兜底。带运行锁，恢复序列跨 cron 周期时不会并发。
3. 每一步都写系统日志（`logger -t apcups-bk650m2`，在 **报告 → 系统日志** 可查），
   告警与恢复通知遵守[掉线通知](#通知通知页)策略。

状态文件位于 `/var/db/nut/`（`apcups_watchdog_failures`、
`apcups_watchdog_outage_start`、`apcups_watchdog_last_alert`、
`apcups_comm_alert_sent`）。典型死锁从掉线到恢复约 **3 分钟**。

电池供电期间，watchdog 还会每分钟执行一次 `battery_check.py`：电量阈值告警
（每次掉电最多一次）与"电量降到指定百分比关机"策略都由它驱动。

## 仪表盘小组件

在 Lobby 仪表盘添加"APC UPS BK650M2"小组件——第一行显示 UPS 状态
（在线/电池供电/离线），第二行显示电量。旧版 PHP 小组件
（`src/www/widgets/`）供旧版面板使用。

## 诊断与排障

诊断页（或 `configctl apcupsbk650m2 diagnostics BK650M2@localhost`）一键收集：
`upsc`、`service nut status`、`service nut_upsmon status`、`usbconfig`、
NUT 配置文件、MONITOR 行和最近 80 行 UPS 相关系统日志。

| 症状 | 可能原因 / 处理 |
|---|---|
| nut 启动报 "you must specify a port name" | 端口必须是 `auto`（设置页 → 端口），保存后重启 NUT |
| `upsc` 输出数据后崩溃（"signal 11"） | 平台已知问题（[#5509](https://github.com/opnsense/plugins/issues/5509)）；本插件无害——所有调用都解析输出而非退出码 |
| 状态在 已断开/已连接 间跳动 | 固件死锁的典型表现；watchdog 约 3 分钟内 USB 重置恢复，可在系统日志搜 `apcups-bk650m2` |
| 驱动启动报 "Can't claim USB device" / "No matching HID UPS found" | 内核 HID 抢占；可尝试 loader.conf quirk：`hw.usb.quirk.0="0x051d 0x0002 0 0xffff UQ_HID_IGNORE"`（需重启，通常用不着） |
| 通知发送失败 | 用通知页对应渠道的测试按钮——会显示后端原始错误 |
| 本插件与 os-nut 同时安装 | 卸载 os-nut；两者都写 `/usr/local/etc/nut/*` |

## 构建 .txz 包

仓库目录结构已符合 OPNsense plugins tree。把 `sysutils/apcups-bk650m2` 拷入
OPNsense plugins 检出目录（`/usr/plugins/sysutils/apcups-bk650m2`），按标准
OPNsense tools 流程构建即可，包名形如 `os-apcups-bk650m2-x.y.z.txz`
（`Makefile` 声明 `PLUGIN_DEPENDS=nut`）。

## 兼容性

- 实测环境：OPNsense 26.1.9 / FreeBSD 14.3-RELEASE，APC Back-UPS BK650M2-CH
  （vendor `051d`，USB HID）。
- 任何 APC USB HID 设备（Back-UPS / Smart-UPS 带 USB）用默认配置应可直接使用；
  其他 USB HID 厂商改 VendorID 即可。
- 不在范围内：SNMP、串口、多 UPS——本插件刻意聚焦单台本地 USB UPS。

## 常见问题

**日志里 upsc 段错误要紧吗？**
不要紧。该平台 `upsc` 会在输出数据后随机崩溃
（[上游 issue](https://github.com/opnsense/plugins/issues/5509)）。
本插件统一用 `stdbuf -o0` 运行并解析输出，监控、watchdog 和通知都不受影响。

**UPS 为什么每隔几天就"断开"一次？**
就是上文说的 APC 固件 USB 死锁——设备端固件 bug，不是 OPNsense/NUT 的问题。
watchdog 约 2-3 分钟发现、约 3 分钟内自动恢复。

**能和 os-nut 一起装吗？**
不能。两者都生成 `/usr/local/etc/nut/*`。

**UPS Server 会不会让 UPS 裸奔在网络上？**
读取默认匿名（NUT 标准行为），注册监控会话需要客户端账号，而局域网客户端
做任何操作都关不了防火墙。

**插件界面支持跟随 OPNsense 语言切换吗？**
目前界面为硬编码中文，暂不支持多语言切换（见 [English](README.en.md) 文档中的
相同说明）。计划中的改进：改用 OPNsense 标准 gettext 机制，界面文字随系统
语言自动切换。

## 许可证

[BSD-2-Clause](LICENSE)
