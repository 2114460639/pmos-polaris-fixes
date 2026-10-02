# 在 postmarketOS 上跑 adbd（ADB over USB functionfs）—— 打包版

参考博客：《Linux usb 7. Linux 配置 ADBD》
（<https://www.cnblogs.com/pwl999/p/15675582.html>，configfs + functionfs 方案）

目标：在 postmarketOS 手机（xiaomi-polaris / Mi Mix2S，sdm845）上跑起 `adbd`，
宿主机通过 `adb` 直连调试，**同时保留 pmOS 自带的 NCM USB 网络**
（`ssh user@172.16.42.1` 不受影响）。

已在 pmOS v26.06（systemd）+ Linux 7.1.0-rc1-sdm845 + 宿主机 adb 34.0.5 验证通过。
**2026-10-01 起从「/tmp 手动部署」升级为「pmaports 包 + systemd 开机自启」**，
本文档即为新方法记录。

## 现状：已固化为刷机包的一部分

| 项 | 位置 |
| --- | --- |
| pmaports 包（二进制 + 接线脚本 + service + preset） | `pmaports-console/device/testing/adbd-polaris/`（`adbd-polaris-1-r3`） |
| 挂进镜像 | `device-xiaomi-polaris`（`7-r9`）的 `depends` 加 `adbd-polaris` |
| 成品镜像 | `~/pmos-polaris-flash-console/images/`（开机即用，见其 README《ADB USB 直连》） |

包内文件装到设备的位置：

| 源文件 | 装到 | 作用 |
| --- | --- | --- |
| `adbd` | `/usr/bin/adbd` | 预编译 aarch64 静态 adbd（约 6 MB，已 strip） |
| `polaris-adbd-setup.sh` | `/usr/sbin/polaris-adbd-setup` | gadget 接线 + 网络看门狗 + adbd 守护循环 |
| `polaris-adbd.service` | `/usr/lib/systemd/system/` | 开机自启（`multi-user.target`） |
| `polaris-adbd.preset` | `system-preset/55-adbd-polaris.preset` | `enable polaris-adbd.service` |

> 权威版本在 pmaports 包目录 `adbd-polaris/`（经本仓库 canonical patch 落树）。

## 构建工具链（2026-10-03 已移除，见 git 历史）

adbd 二进制已固化进 `adbd-polaris` 包（canonical patch 含二进制），日常复现
**不需要重新构建**。历史构建工具已从仓库移除，需要时从 git 历史取回：

| 历史文件 | 用途 |
| --- | --- |
| `polaris-adbd-build.sh` | 宿主机交叉编译 aarch64 静态 adbd |
| `adbd-linux.patch` | adbd 源码补丁（OpenSSL 3 适配 + Makefile 链接修复 + **reboot 服务修复**） |
| `polaris-adbd-setup.sh` | 手机端 gadget 配置 + adbd 守护脚本（= 包内 `/usr/sbin/polaris-adbd-setup`） |
| `adbd-build/` | 构建工作目录（openssl 源码等，`.gitignore` 不入库） |

重建要点（原理记录）：

- adbd 用文章推荐的 [tonyho/adbd-linux](https://github.com/tonyho/adbd-linux)，
  上游要求 OpenSSL 1.0（直接访问 `RSA`/`BIGNUM` 内部结构），`adbd-linux.patch`
  改为 `RSA_set0_key`/`RSA_get0_key`/`BN_bn2bin` 等 1.1+/3.x API，
  配合宿主机交叉编译的 OpenSSL 3.3.2 静态库（官方源卡死时自动切 gh-proxy 镜像）。
- **reboot 修复**（同一补丁内）：上游 reboot 服务调用 `property_set("sys.powerctl", …)`，
  而 `ADB_NON_ANDROID` 构建的 `property_set` 是直接 `return 0` 的空桩 ——
  `adb reboot` 命令返回"成功"但设备不动，服务端 `pause()` 干等。
  补丁改为 `fork()+execl("/sbin/reboot", "reboot", <reason>)` 真正执行，
  失败回退 `systemctl reboot --reboot-argument <reason>`。
- 全静态链接（musl 的 pmOS 上无 glibc 运行时依赖问题）。
- `ALLOW_ADBD_NO_AUTH=1` + 非 Android property stub → 运行时 `auth_required=false`，
  `adb` 无需授权即可连接。

## 部署

### A. 随刷机包（主推，开机自启）

直接刷 `~/pmos-polaris-flash-console/images/` 的镜像即可，或在 console pmaports 树里：

```sh
pmbootstrap -c ~/.config/pmbootstrap_console.cfg checksum adbd-polaris
pmbootstrap -c ~/.config/pmbootstrap_console.cfg build adbd-polaris --arch aarch64
pmbootstrap -y -c ~/.config/pmbootstrap_console.cfg install --password password
```

### B. 手动部署到正在跑的系统（调试用）

```sh
# adbd 源：已装 adbd 的设备上提取（或 git 历史的构建产物 adbd-build/.../adbd）
scp other:/usr/bin/adbd                    user@172.16.42.1:/tmp/adbd-pkg
scp <pmaports>/adbd-polaris/polaris-adbd-setup.sh  user@172.16.42.1:/tmp/
scp <pmaports>/adbd-polaris/polaris-adbd.service   user@172.16.42.1:/tmp/
ssh user@172.16.42.1
sudo install -m755 /tmp/adbd-pkg      /usr/bin/adbd
sudo install -m755 /tmp/polaris-adbd-setup.sh /usr/sbin/polaris-adbd-setup
sudo install -m644 /tmp/polaris-adbd.service  /usr/lib/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now polaris-adbd
```

> **不要再用 `systemd-run --unit=… /tmp/polaris-adbd-setup.sh` 的老方式**：
> transient unit 重启即失、`/tmp` 重启即清，是 2026-10-01 前的临时调试手段。

## 验证（宿主机，全部实测通过）

```sh
$ adb devices
postmarketOS    host
$ adb shell uname -a
Linux xiaomi-polaris ... aarch64 GNU/Linux
```

开机自启链路：重启后 `systemctl is-active polaris-adbd` = `active`、
`is-enabled` = `enabled`，`adb devices` 无需人工干预重新出现。

### reboot 整合（2026-10-01 实测，均 10 秒进 fastboot）

```bash
sudo reboot bootloader            # SSH / 控制台
adb reboot bootloader             # PC 端（依赖上面的 reboot 修复）
adb shell reboot bootloader       # 进 shell 后
```

- 长命令 `sudo systemctl reboot --reboot-argument=bootloader` 同样有效。
- **唯一不行的是 `systemctl reboot bootloader`**（直接用 systemctl 名报
  `Too many arguments`）：systemd 261 只在 `reboot` 调用名（`/sbin/reboot` 软链）
  下把位置参数当 reboot argument。无需 wrapper 脚本。

## 五个关键坑（调试与打包过程记录）

1. **SSH 会话断开会杀死 adbd**：pmOS 用 systemd，SSH 断开时回收整个 session
   cgroup，挂在会话下的 adbd/守护脚本全部被杀 → adbd 一死 functionfs 关闭 →
   整个 gadget 从宿主机消失 → USB 网络中断且无法远程恢复（锁死，只能重启）。
   **必须由 system 单元托管**（`polaris-adbd.service`，跑在 system manager cgroup）。
2. **configfs 绑定期间禁止创建函数 symlink**：`ln -s functions/ffs.adb configs/c.1/`
   在 UDC 已绑定时返回 ENOENT/EINVAL 失败（`mkdir functions/ffs.adb` 和挂载
   functionfs 则允许）。`ln` 必须放在 `echo "" > UDC` 与 `echo $UDC > UDC`
   的临界窗口内。
3. **configfs symlink 目标相对 cwd 解析**：`ln -s ../../functions/ffs.adb` 必须
   先 `cd` 到 `configs/c.1` 里执行，否则相对 shell 的家目录解析报 ENOENT。
4. **systemd preset 会删掉包内的自启软链**：preset 只对**新安装的 unit** 生效，
   出厂 `99-default.preset` 是 `disable *`，首次安装时 `polaris-adbd.service`
   属新 unit，apk 刚放进去的 `multi-user.target.wants` 软链随即被删
   （症状：包装了但服务不自启）。解法：包内自带
   `55-adbd-polaris.preset` 写 `enable polaris-adbd.service`
   （preset 首个匹配生效，`55-` 排在 `99-` 前），与当时 firmware 包
   `50-polaris.preset` 同款（后者已随音频 UCM 重构删除）。
5. **`/tmp` 重启即清、transient unit 重启即失**：老部署方式（`/tmp/adbd` +
   `systemd-run`）重启后静默失效——脚本文件没了，unit 启动即退出且
   `--collect` 自动清理，连日志都看不到。这就是升级为 pmaports 包的直接原因。

脚本设计不变：**独立网络看门狗先行**（UDC 空超过 6 秒强制重绑，ffs 绑不上
则自动剔除 ffs 只恢复 NCM 网络，保证任何失败都不会锁死设备）→ 不断网的准备
工作（等 g1 最多 60 秒）→ 最短临界窗口 → adbd/UDC 守护循环。
日志：`journalctl -u polaris-adbd`（关键行 `SETUP_OK` / `ADBD_UP` / `WD:` / `GUARDIAN:`）。
