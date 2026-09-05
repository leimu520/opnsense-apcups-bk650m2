# APC BK650M2 OPNsense 插件项目记忆

## 项目定位

- 项目名：`os-apcups-bk650m2`
- 目标系统：OPNsense 26.1.9-amd64 / FreeBSD 14.3-RELEASE-p14
- 目标硬件：x86 架构 6 网口主板
- 目标 UPS：APC Back-UPS BK650M2-CH
- 连接方式：USB
- 底层驱动：Network UPS Tools，`usbhid-ups`
- 插件目标：替代 `os-nut` 的 Web 配置和状态展示逻辑，专门服务 BK650M2。

## 当前已确认的原插件问题

用户当前测试基于原 `os-nut` 插件。排查过程确认：

1. USB 已识别 UPS：
   ```text
   ugen0.2: <Uninterruptible Power Supply American Power Conversion>
   ```

2. 原插件生成了 NUT 配置：
   ```conf
   [BK650M2]
   driver=usbhid-ups
   vendorid=051d
   productid=0002
   ```

3. 但原配置缺少关键参数：
   ```conf
   port=auto
   ```

4. 因为缺少 `port=auto`，`service nut start` 失败：
   ```text
   Error: you must specify a port name in ups.conf or in '-x port=...' argument.
   Driver failed to start (exit status=1)
   ```

5. 与此同时，`nut_upsmon` 已经在运行：
   ```text
   nut_upsmon is running as pid ...
   ```

6. 由于 `upsmon` 在监控 `BK650M2`，但 `nut/upsd` 没启动成功，所以 CLI 不断广播：
   ```text
   UPS BK650M2 is unavailable
   ```

7. 手动补上 `port=auto` 后，NUT 成功连接 UPS：
   ```text
   Connected to UPS [BK650M2]: usbhid-ups-BK650M2
   Found 1 UPS defined in ups.conf
   ```

8. `upsc BK650M2@localhost` 可读取完整 UPS 数据：
   ```text
   battery.charge: 100
   battery.runtime: 2417
   device.model: BK650M2-CH
   device.serial: 9B20xxxxxxxx
   input.voltage: 224.0
   ups.load: 9
   ups.status: OL DISCHRG
   ```

9. 当前环境中 `upsc` 在输出数据后会出现：
   ```text
   Segmentation fault
   ```
   但因为数据已经完整输出，状态读取仍可用。新插件的状态脚本已兼容这种情况：只要输出里包含 `ups.status` 或 `battery.charge`，就判定为已连接，并在 message 中提示 `upsc` 非 0 退出。

## 新插件是否能解决

能解决当前已确认的核心问题。

新插件模板会生成：

```conf
[BK650M2]
    driver = usbhid-ups
    port = auto
    desc = "APC Back-UPS BK650M2"
    vendorid = 051d
    override.battery.charge.low = 20
    override.battery.runtime.low = 180
```

因此不会复现原 `os-nut` 缺少 `port=auto` 导致 `nut` 服务无法启动的问题。

但注意：

- 新插件不重新实现 USB 驱动。
- 新插件依赖底层 `nut` 软件包。
- 新插件不依赖 `os-nut` 插件本身。
- 不应与 `os-nut` 同时启用，因为两者都会写 `/usr/local/etc/nut/*`。

## 新插件功能列表

### Web UI

- 菜单入口：`Services -> APC UPS BK650M2`
- 状态页：
  - 连接状态
  - UPS 状态
  - 剩余电量
  - 预计供电时间
  - UPS 负载
  - 输入电压
  - 型号
  - 序列号
  - 状态消息
- 设置页：
  - 启用/禁用
  - UPS 名称，默认 `BK650M2`
  - 驱动，默认 `usbhid-ups`
  - 端口，默认 `auto`
  - 描述
  - monitor 用户名/密码
  - USB VendorID，默认 `051d`（APC；其他 USB HID 品牌可改）
  - UPS Server 开关 + 客户端用户名/密码

### UPS Server（网络服务）

- 开关开启后 `upsd.conf` 渲染 `LISTEN 0.0.0.0 3493` + `LISTEN :: 3493`（全接口），关闭时仅渲染本机回环 `127.0.0.1` / `::1`。
- 注意：不能同时渲染 `::` 与 `::1`，FreeBSD 上重复绑定会导致 upsd 启动失败、本地监控跟着挂。
- `upsd.users` 额外渲染一个 `upsmon slave` 权限的客户端账号；`serverPassword` 为空时不渲染该账号（防止空密码配置导致 upsd 异常）。
- 客户端配置：`MONITOR ups名@防火墙IP 1 客户端账号 客户端密码 slave`；防火墙本机保持 master，负责最终断电。
- 需要用户自行在防火墙放行 LAN → 本机 TCP 3493。
- 群晖 DSM：UPS 类型选 "NUT server"；Proxmox：`nut-client`；Windows：WinNUT。
- 诊断页：
  - `upsc BK650M2@localhost`
  - `service nut status`
  - `service nut_upsmon status`
  - `usbconfig`
  - NUT 配置文件列表
  - `ups.conf`
  - `upsmon.conf` 中的 `MONITOR` 行
  - 最近系统日志中的 NUT/UPS/unavailable 相关内容

### API / configd

- `/api/apcups/service/status`
- `/api/apcups/service/diagnostics`
- `/api/apcups/service/reload`
- `/api/apcups/service/restart`
- `/api/apcups/service/testNotify`（测试单个通知渠道）
- `configctl apcupsbk650m2 status BK650M2@localhost`
- `configctl apcupsbk650m2 diagnostics BK650M2@localhost`
- `configctl apcupsbk650m2 restart`
- `configctl apcupsbk650m2 force-restart`
- `configctl apcupsbk650m2 reset-usb`

### 安装支持

- 开发版安装脚本：
  - `install-dev.sh`
- 开发版卸载脚本：
  - `uninstall-dev.sh`
- 安装说明：
  - `INSTALL.md`

当前还没有在本机生成正式 `.txz` 包，因为正式 OPNsense 插件包需要在 FreeBSD/OPNsense ports/tools 构建环境中生成。当前源码目录已经按 OPNsense plugins tree 结构准备，可放入：

```text
/usr/plugins/sysutils/apcups-bk650m2
```

然后构建为：

```text
os-apcups-bk650m2-2.0.2.txz
```

### NUT 配置模板

插件生成以下文件：

- `/etc/rc.conf.d/nut`
- `/etc/rc.conf.d/nut_upsmon`
- `/usr/local/etc/nut/nut.conf`
- `/usr/local/etc/nut/ups.conf`
- `/usr/local/etc/nut/upsd.conf`
- `/usr/local/etc/nut/upsd.users`
- `/usr/local/etc/nut/upsmon.conf`
- `/usr/local/etc/nut/upssched.conf`
- `/etc/cron.d/apcups-bk650m2`

### 自动恢复

为缓解 APC BK650M2 在部分硬件上运行一段时间后 USB 通信中断、且普通 `service nut restart` 无法恢复的问题：

1. `service.sh restart` 改为软重启：停止 `nut_upsmon`、`nut`/`upsd` 后重新启动，尽量保留正在运行的 UPS 驱动，避免 FreeBSD 内核 HID 驱动抢占 USB 设备后 NUT 无法再次认领。
2. `service.sh force-restart` 为深度重启：停止 `nut_upsmon`、`nut`/`upsd` 后，使用 `upsdrvctl stop` 停止驱动并 `pkill` 清理残留进程，再重新启动。
3. `service.sh reset-usb` 在深度重启基础上，对检测到的 APC USB 设备执行 `usbconfig -d ugenX.Y reset`。
4. `watchdog.sh` 每 1 分钟执行一次 `upsc` 探测（带运行锁，恢复序列跨 cron 周期时防止并发）：
   - 连续 3 次探测失败（约 2-3 分钟）则触发恢复，顺序为：`reset-usb`（USB 重置，实证 7/7 成功，且含完整 NUT 重启）→ `restart`（软重启）→ `force-restart`（深度重启）。
   - 实证表明 BK650M2 固件死锁后普通重启全部无效，只有 USB 总线重置有效，故 USB 重置放第一位，软/深重启仅作后备。
   - 恢复动作不受宽限期影响（越快修好越好），但**通知全部遵守掉线通知宽限期**并与 upssched 共享"本次掉线已告警"标志：告警只在掉线持续超过宽限期且 upssched 尚未告警时发送；恢复通知只在确实为本次掉线发过告警时发送；宽限期内自愈的掉线完全静默。watchdog 恢复时会一并清理标志与掉线起点文件。
   - 探测到电池供电（ups.status 含 OB）时顺带执行 `battery_check.py`：电量阈值通知与按百分比关机需要周期性检查，仅靠 upssched 的 ONBATT 定时器（只触发一次）不生效。
5. `ups.conf` 默认启用 `pollonly`、`pollinterval = 15`、`waitbeforereconnect = 30`、`maxretry = 3`、`retrydelay = 5`，降低中断传输导致掉线的概率，并让驱动在意外 USB 错误后等待 UPS 固件恢复。
6. `upsd.conf` 增加 `MAXAGE 60`，避免 upsd 在 15 秒轮询间隔下误判数据过期。
7. `upsmon.conf` 将 `DEADTIME` 从 15 调整为 45，避免 pollinterval 变大后出现“data stale”误报。
8. watchdog 检测更宽容：对 `upsc` 连续重试 3 次并兼容 segfault、连续失败阈值提高到 3 次、告警通知有 15 分钟冷却期。
9. `status.php` 增加重试，减少网页瞬时的“已断开”误报。
10. 如仍出现启动时 `Can't claim USB device`、`No matching HID UPS found` 或权限问题，可尝试在 `/boot/loader.conf` 中加入 USB quirk（需重启），例如 BK650M2-CH（productid 0x0002）：
   ```
   usb_quirk_load="YES"
   hw.usb.quirk.0="0x051d 0x0002 0 0xffff UQ_HID_IGNORE"
   ```

### 连接状态通知

除原有的市电/电池/低电量通知外，新增 UPS 连接状态变化通知：

- `COMMBAD`：UPS 通信中断告警。
- `COMMOK`：UPS 通信恢复通知。
- `NOCOMM`：长时间无法与 UPS 通信告警。

以上掉线类通知（含 watchdog 恢复通知）由通知页的"启用掉线通知"开关统一控制，写入 `notify.conf` 的 `comm_alert_enabled` 字段；关闭后系统日志仍照常记录，仅停止推送。

掉线通知带防抖：`upssched.conf` 中 COMMBAD 与 NOCOMM 都通过 `START-TIMER` 延迟"掉线通知宽限期"（默认 120 秒）后触发，COMMOK 通过 `CANCEL-TIMER` 取消两个定时器，短暂闪断自愈不打扰。定时器到点发送前还会复核一次 UPS 是否仍然断连（watchdog 重启 upsmon 的恢复不会产生 COMMOK，定时器可能在修复后才到点）。COMMBAD/NOCOMM/watchdog 三条告警路径共享标志文件 `apcups_comm_alert_sent`（每 2 小时窗口内每 1 小时新鲜度校验，防止 watchdog 重启 upsmon 后无 COMMOK 导致标志卡死漏报），保证一次掉线最多一组"告警+恢复"通知。宽限期取值渲染在 `upssched.conf` 定时器与 `notify.conf` 的 `comm_alert_grace` 字段，watchdog 从后者读取同一配置。

实现方式：

- `upsmon.conf` 为 `COMMOK`、`COMMBAD`、`NOCOMM` 配置 `NOTIFYFLAG ... EXEC`。
- `upssched.conf` 通过 `AT COMMBAD/COMMOK/NOCOMM * EXECUTE ...` 触发脚本。
- `upssched-cmd.sh` 调用 `notify.py` 发送消息，COMMBAD/NOCOMM 告警共用 `/var/db/nut/apcups_comm_alert_sent` 避免一次掉线重复推送；watchdog（`watchdog.sh`）告警前检查同一标志、发送后写入，恢复时清理。

### 关机联动

支持三种策略：

- 禁用自动关机
- 仅低电量时关机
- 市电断开后延迟 N 秒关机

实现方式：

- `upsmon.conf` 配置 `SHUTDOWNCMD`
- `upssched.conf` 配置 `ONBATT`/`ONLINE`/`LOWBATT`
- `upssched-cmd.sh` 调用：
  ```sh
  /usr/local/sbin/upsmon -c fsd
  ```

## 关键代码文件

- 插件 Makefile：
  - `sysutils/apcups-bk650m2/Makefile`
- 模型：
  - `src/opnsense/mvc/app/models/OPNsense/ApcUps/ApcUps.php`
  - `src/opnsense/mvc/app/models/OPNsense/ApcUps/ApcUps.xml`
- 菜单：
  - `src/opnsense/mvc/app/models/OPNsense/ApcUps/Menu/Menu.xml`
- ACL：
  - `src/opnsense/mvc/app/models/OPNsense/ApcUps/ACL/ACL.xml`
- 控制器：
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/IndexController.php`
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/Api/SettingsController.php`
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/Api/ServiceController.php`
- 表单：
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/forms/settings.xml`
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/forms/notification.xml`
- 页面：
  - `src/opnsense/mvc/app/views/OPNsense/ApcUps/index.volt`
- 通知表单：
  - `src/opnsense/mvc/app/controllers/OPNsense/ApcUps/forms/notification.xml`
- configd actions：
  - `src/opnsense/service/conf/actions.d/actions_apcupsbk650m2.conf`
- 后端脚本：
  - `src/opnsense/scripts/apcupsbk650m2/status.php`
  - `src/opnsense/scripts/apcupsbk650m2/diagnostics.php`
  - `src/opnsense/scripts/apcupsbk650m2/service.sh`
  - `src/opnsense/scripts/apcupsbk650m2/upssched-cmd.sh`
  - `src/opnsense/scripts/apcupsbk650m2/notify.py`
  - `src/opnsense/scripts/apcupsbk650m2/battery_check.py`
  - `src/opnsense/scripts/apcupsbk650m2/watchdog.sh`
- NUT 模板：
  - `src/opnsense/service/templates/OPNsense/ApcUps/+TARGETS`
  - `src/opnsense/service/templates/OPNsense/ApcUps/nut`
  - `src/opnsense/service/templates/OPNsense/ApcUps/nut_upsmon`
  - `src/opnsense/service/templates/OPNsense/ApcUps/nut.conf`
  - `src/opnsense/service/templates/OPNsense/ApcUps/ups.conf`
  - `src/opnsense/service/templates/OPNsense/ApcUps/upsd.conf`
  - `src/opnsense/service/templates/OPNsense/ApcUps/upsd.users`
  - `src/opnsense/service/templates/OPNsense/ApcUps/upsmon.conf`
  - `src/opnsense/service/templates/OPNsense/ApcUps/upssched.conf`
- `src/opnsense/service/templates/OPNsense/ApcUps/notify.conf`

## 开发规范

1. 不直接在 PHP 控制器中执行任意 shell 命令。
   - Web/API 调用 `configd`。
   - `configd` 调用固定脚本。

2. 不依赖 `os-nut`。
   - 只依赖底层 `nut` 软件包。
   - 插件自身生成所需 NUT 配置。

3. 不与 `os-nut` 同时启用。
   - 两者都会写 `/usr/local/etc/nut/*`。

4. UPS 名称统一使用：
   ```text
   BK650M2
   ```

5. BK650M2 USB 默认配置必须包含：
   ```conf
   driver = usbhid-ups
   port = auto
   vendorid = 051d
   ```
   vendorid 已参数化（模型 `general.vendorId`），默认仍为 APC 的 051d。

6. 状态读取必须兼容 `upsc` 输出后 segfault。
   - 不要只看 exit code。
   - 应先解析输出。
   - 如果存在 `ups.status` 或 `battery.charge`，按已连接处理。

7. 所有排查信息都应能从 Web 诊断页或 `configctl apcupsbk650m2 diagnostics BK650M2@localhost` 读取。

8. 关机策略要保守。
   - 默认不应过早关机。
   - 默认可使用低电量阈值和延迟关机。

9. 修改 NUT 模板后需要执行：
   ```sh
   configctl template reload OPNsense/ApcUps
   configctl apcupsbk650m2 restart
   ```

10. 修改 actions 后需要执行：
    ```sh
    service configd restart
    ```

10a. `notify.conf` 是 JSON 文件：所有写入它的模型文本字段（通知页 16 个字段）已加掩码
    `/^[^"\\]*$/u`，新增字段若也写入 JSON 必须同样加掩码，否则值含引号/反斜杠会让
    notify.py 解析失败、全部通知静默失效。`general.description` 写入 ups.conf 的
    `desc = "..."`，同理已加掩码。

11. 修改菜单或 ACL 后可能需要清缓存：
    ```sh
    rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json
    ```

## 当前推荐 CLI 排查命令

```sh
usbconfig
cat /usr/local/etc/nut/ups.conf
service nut status
service nut_upsmon status
service nut start
upsc -l
upsc BK650M2@localhost
grep -n "MONITOR" /usr/local/etc/nut/upsmon.conf
clog /var/log/system/latest.log | grep -Ei "nut|ups|usbhid|BK650M2|unavailable" | tail -n 100
```

如果广播刷屏，可先停掉监控：

```sh
service nut_upsmon stop
```

修好 `nut` 后再启动：

```sh
service nut_upsmon start
```
