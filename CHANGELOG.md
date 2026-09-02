# Changelog

## 2.1.0 (2026-09-02)

### 新增

- UPS Server（网络服务）模式：启用后 NUT 服务监听 TCP 3493（0.0.0.0/::），局域网内的 NAS（群晖等）、Proxmox、WinNUT 等客户端可作为从机监控这台 UPS。提供独立的客户端账号（`upsmon slave` 权限），凭据为空时不生成账号以保证本机监控不受影响。
- USB VendorID 可配置（默认 051d/APC）：插件不再硬编码厂商 ID，其他品牌的 USB HID UPS 理论上也可直接使用。
- 凭据文件权限加固：服务启动时自动将 `upsd.users`、`upsmon.conf` 调整为 `root:nut 0640`，消除 upsd 的"world readable"告警并隐藏密码。

### 变更

- `upsd.conf` 的 LISTEN 按服务模式二选一渲染（本机回环 或 全接口），避免 `::` 与 `::1` 重复绑定导致 upsd 启动失败。

## 2.0.3 (2026-09-02)

### 新增

- 掉线通知开关：通知页新增"启用掉线通知"，控制 UPS 通信中断（COMMBAD）、通信恢复（COMMOK）、长时间无响应（NOCOMM）以及 watchdog 恢复过程的通知。关闭后 watchdog 仍会自动恢复，只是不再推送这些通知（系统日志照常记录）。
- 掉线通知防抖（宽限期）：COMMBAD 不再立即提醒，而是经由 `upssched` 定时器延迟"掉线通知宽限期"（默认 120 秒，可配置 30-3600 秒）。短暂闪断并自行恢复的（COMMOK 会取消定时器）完全不推送，只有真正持续的掉线才提醒，避免骚扰。
- 掉线标志增加 1 小时新鲜度校验：watchdog 通过重启 upsmon 恢复时不会产生 COMMOK 事件，原逻辑会导致标志残留、下一次掉线漏报；现在过期标志自动失效。

### 修复与改进

- 根据主防火墙 10 天日志实证（7 次掉线全部由 UPS 固件 USB HID 接口死锁引起，软重启/深度重启 0 次成功、USB 重置 7/7 成功），调整 watchdog 恢复顺序为：软重启 → USB 重置 → 深度重启。
- watchdog 检测间隔从 5 分钟缩短为 2 分钟，3 次连续失败（约 6 分钟）即触发恢复，掉线平均恢复时间从约 15 分钟缩短到约 7 分钟。

## 2.0.2 (2026-06-17)

### 新增

- UPS 连接状态推送通知：通信中断（COMMBAD）、通信恢复（COMMOK）、长时间无响应（NOCOMM）时发送告警/恢复通知。
- 新增 watchdog 自动恢复机制：每 5 分钟检测一次 UPS 通信，连续 3 次失败会先软重启、再深度重启、最后重置 USB 设备并通知用户。
- `service.sh` 增加 `reset-usb` 动作，用于深度恢复 USB 连接。

### 修复与改进

- 修复“点击重启 NUT 后仍无法重连”的问题：
  - `service.sh restart` 改为软重启，保留正在运行的 UPS 驱动，避免 FreeBSD 内核 HID 驱动抢占 USB 设备后 NUT 无法再次认领的问题。
  - 新增 `force-restart` 动作：深度重启，停止并重新启动 UPS 驱动。
  - 新增 `reset-usb` 动作：深度重启 + 自动重置 APC USB 设备。
  - `ups.conf` 增加 `pollonly`、`pollinterval = 15`、`waitbeforereconnect = 30`、`maxretry = 3`、`retrydelay = 5`，提升 APC USB HID 连接稳定性，减少中断传输导致的掉线，并让驱动在意外错误后等待 UPS 固件恢复再重连。
- `upsd.conf` 增加 `MAXAGE 60`，与 `pollinterval = 15` 和 `pollfreq = 30` 匹配，避免 upsd 误判数据过期。
- `upsmon.conf` 将 `DEADTIME` 从 15 调整为 45，避免 pollinterval 变大后出现“data stale”误报。
- watchdog 改为三级恢复：软重启 → 深度重启 → USB 重置。
- watchdog 检测更宽容：
  - 对 `upsc` 连续重试 3 次，并兼容 `upsc` 输出后 segfault 的场景（只要输出里有 `ups.status` 就算连通）；
  - 连续失败阈值从 2 次提高到 3 次（15 分钟），减少误触发；
  - 告警通知增加 15 分钟冷却期，避免频繁发邮件。
- `status.php` 增加重试机制，减少网页上瞬时的“已断开”误报。
- `upsmon.conf` 为 `COMMOK`、`COMMBAD`、`NOCOMM` 增加 `EXEC` 标志，使连接事件能触发 `upssched`。
- `upssched-cmd.sh` 新增 `commbad_alert`、`commok_alert`、`nocomm_alert` 处理，并用状态文件避免重复告警。

## 2.0.1 (2026-06-15)

### 紧急修复

- 修复 v2.0.0 中保存按钮点击事件处理函数的 JavaScript 语法错误（多余一个 `});`），该错误导致整个页面 JS 失效，表现为：状态不刷新、诊断无响应、底部按钮不显示、配置无法加载。

## 2.0.0 (2026-06-15)

### 重构

- 将 `general.xml` 和 `shutdown.xml` 合并为 `settings.xml`，设置页只保留一个表单。
- 设置页现在只有一个“完整帮助”按钮，避免 general/shutdown 两个表单各渲染一个帮助按钮。
- 更新 `IndexController` 和 `index.volt` 以使用新的 `settingsForm`。

## 1.2.7 (2026-06-15)

### 修复

- 修复 `install-dev.sh` 菜单缓存路径错误：OPNsense 26.x 菜单缓存实际在 `/var/lib/php/tmp/`，旧脚本只清 `/tmp/` 导致缓存未生效。
- 增加“运行诊断”按钮与输出区域的上下左右间距。

## 1.2.6 (2026-06-15)

### 修复

- 修复 Services 菜单图标仍不显示的问题：移除 `<Services>` 上多余的 `order="50"` 属性。
- 调整“运行诊断”按钮位置，增加左上内边距，避免贴着标签页顶部和左侧。
- 状态页刷新/重启按钮也增加顶部间距，保持风格一致。

## 1.2.5 (2026-06-15)

### 修复

- 修复 Services 菜单图标不显示的问题：将 `icon` 改为正确的 `cssClass` 属性。
- 为设置/通知页底部的保存、测试通知按钮增加 `padding-bottom: 20px`，避免按钮紧贴内容框底部。

## 1.2.4 (2026-06-15)

### 新增

- 新增 OPNsense Lobby 仪表盘部件（widget），显示 UPS 状态和电池电量。
- 部件文件：`src/opnsense/www/js/widgets/ApcUps.js` + `Metadata/ApcUps.xml`。
- 旧版 PHP 小部件保留在 `src/www/widgets/widgets/apcups.widget.php` 以兼容旧面板。

## 1.2.3 (2026-06-15)

### 修复与改进

- “测试通知”按钮只在“通知”标签页显示，不再出现在“设置”标签页。
- 为 Services 菜单下的插件入口增加电池图标（`fa-battery-half`）。

## 1.2.2 (2026-06-15)

### 改进

- 统一通知标题/正文格式：
  - 标题统一为 `<设备名>-UPS告警通知`。
  - 切换到电池供电：`[设备名]上的UPS已进入电池供电模式，预计续航xx分钟，请及时检查市电情况或关闭其他设备`。
  - 电量阈值告警：`[设备名]上的UPS电池容量剩余xx%，请及时检查市电情况或关闭其他设备！`。
  - 低电量告警：与阈值告警格式一致，显示当前剩余电量。
  - 恢复市电：`[设备名]上的UPS已恢复市电供电，告警解除`。
- `upssched-cmd.sh` 实时读取 `battery.runtime` 和 `battery.charge` 填充通知内容。
- `battery_check.py` 使用系统 hostname 生成告警标题/正文。
- 测试通知文案与真实告警保持一致。

## 1.2.1 (2026-06-15)

### 修复

- 修复邮件通知在 163/QQ 等需要 SSL（端口 465）或 STARTTLS（端口 587）的邮箱上发送失败的问题。
- `notify.py` 根据端口自动选择 `SMTP_SSL`（465）或 `STARTTLS`（587/25）。
- 增加发件人与 SMTP 用户名不一致时的警告提示（163 等服务商要求两者一致）。
- 测试通知弹窗现在会显示失败渠道的原始后端输出，方便排查。

## 1.2.0 (2026-06-15)

### 新增

- 通知页每个渠道（邮件、企业微信机器人、企业微信应用、短信）增加“测试发送”按钮，可立即验证配置是否有效。
- `notify.py` 增加 `--config` 和 `--channel` 参数，支持单独测试指定渠道。
- `ServiceController` 新增 `/api/apcups/service/testNotify` 接口。

### 修复与改进

- `battery_check.py` 调用 `upsc` 时增加 `stdbuf -o0`，兼容该硬件上 `upsc` 输出后 segfault 的场景。
- 通知页增加提示说明：先填写 SMTP 发件信息，再启用下方渠道。

## 1.1.0 (2026-06-15)

### 正式发布

- 支持 APC Back-UPS BK650M2-CH USB 连接。
- 提供 Web UI：状态页、诊断页、设置页、通知页。
- 提供仪表盘小组件：第一行显示 UPS 状态，第二行显示电量。
- 支持通知：邮件、企业微信机器人、企业微信应用消息、短信（阿里云/自定义 HTTP）。
- 支持电量阈值通知：电池供电时电量降到设定百分比发送一次通知。
- 支持四种关机策略：不关机、UPS 低电量关机、电量降到指定百分比关机、电池供电 N 秒后关机。
- 使用 NUT (`usbhid-ups`) 作为底层驱动。

### 修复与改进

- 修复 `PasswordField` 在 OPNsense 26.1.9 上不可用的问题，改用 `TextField`。
- 修复 `install-dev.sh` 未设置 mvc/views/templates 目录权限导致 Web 500 错误的问题。
- 修复 `install-dev.sh` 未重启 lighttpd 导致新文件未生效的问题。
- 修复 `upsc` 输出后 segfault 导致 PHP `exec()` 捕获不到数据的问题，使用 `stdbuf -o0`。
- `ups.conf` 模板默认加入 `user = root`，解决 FreeBSD USB 权限问题。
- UI 全面汉化。

### 兼容性

- 目标系统：OPNsense 26.1.9-amd64 / FreeBSD 14.3-RELEASE-p14
- 依赖底层 `nut` 软件包。
- 请勿与 `os-nut` 插件同时启用。
