# 安装方式

当前项目包含两种安装路线：

1. 开发版直接安装：适合现在在你的 OPNsense 上快速测试。
2. 正式 `.txz` 包：需要 OPNsense/FreeBSD 构建环境生成 `os-apcups-bk650m2-2.1.0.txz`。

## 开发版直接安装

把整个 `opnsense-apcups-bk650m2` 文件夹传到 OPNsense，例如：

```sh
/root/opnsense-apcups-bk650m2
```

然后在 OPNsense CLI 里执行：

```sh
cd /root/opnsense-apcups-bk650m2
sh install-dev.sh
```

安装后打开：

```text
https://<opnsense-host>/ui/apcups/
```

诊断命令：

```sh
configctl apcupsbk650m2 diagnostics BK650M2@localhost
```

卸载开发版：

```sh
cd /root/opnsense-apcups-bk650m2
sh uninstall-dev.sh
```

## 正式包构建

正式插件包不能在 Windows 目录里直接生成，需要在 OPNsense/FreeBSD 的插件构建环境中构建。

目标包名：

```text
os-apcups-bk650m2-2.1.0.txz
```

源码目录应放到 OPNsense plugins tree：

```text
/usr/plugins/sysutils/apcups-bk650m2
```

构建环境准备好后，按 OPNsense tools/plugins 的标准流程构建。当前插件目录已经按这个结构准备：

```text
sysutils/apcups-bk650m2/Makefile
sysutils/apcups-bk650m2/pkg-descr
sysutils/apcups-bk650m2/src/opnsense/...
```

## 注意

- 正式安装前建议停用或卸载 `os-nut`。
- 本插件不依赖 `os-nut`，但依赖底层 `nut` 软件包。
- 不要让 `os-nut` 和本插件同时管理 `/usr/local/etc/nut/*`。
