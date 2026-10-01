# 在 postmarketOS 上运行 adbd（ADB over USB functionfs）

参考博客：《Linux usb 7. Linux 配置 ADBD》
（<https://www.cnblogs.com/pwl999/p/15675582.html>，configfs + functionfs 方案）

目标：在 postmarketOS 手机（xiaomi-polaris / Mi Mix2S，sdm845）上跑起 `adbd`，
让宿主机通过 `adb shell` 调试手机，**同时保留 pmOS 自带的 NCM USB 网络**
（`ssh user@172.16.42.1` 不受影响）。

已在 pmOS v26.06（systemd）+ Linux 7.1.0-rc1-sdm845 + 宿主机 adb 34.0.5 验证通过。

## 文件

| 文件 | 用途 |
| --- | --- |
| `polaris-adbd-build.sh` | 宿主机交叉编译 aarch64 静态 adbd |
| `adbd-linux-openssl3.patch` | adbd 源码补丁（OpenSSL 3 适配 + Makefile 链接修复） |
| `polaris-adbd-setup.sh` | 手机端 gadget 配置 + adbd 守护脚本 |
| `30-gpu-firmware.files` 等 | 本仓库原有 polaris 修复（与本功能无关） |

## 构建（宿主机）

```sh
./polaris-adbd-build.sh          # 产物 adbd-build/adbd-linux/adb/adbd
```

要点：

- adbd 用文章推荐的 [tonyho/adbd-linux](https://github.com/tonyho/adbd-linux)，
  上游要求 OpenSSL 1.0（直接访问 `RSA`/`BIGNUM` 内部结构），
  补丁改为 `RSA_set0_key`/`RSA_get0_key`/`BN_bn2bin` 等 1.1+/3.x API，
  配合宿主机交叉编译的 OpenSSL 3.3.2 静态库。
- 全静态链接（musl 的 pmOS 上无 glibc 运行时依赖问题）。
- `ALLOW_ADBD_NO_AUTH=1` + 非 Android property stub → 运行时 `auth_required=false`，
  `adb` 无需授权即可连接。

## 部署（手机端）

```sh
scp adbd user@172.16.42.1:/tmp/adbd
scp polaris-adbd-setup.sh user@172.16.42.1:/tmp/
ssh user@172.16.42.1
sudo systemd-run --unit=pmos-adbd --collect /bin/sh /tmp/polaris-adbd-setup.sh
```

## 验证（宿主机）

```sh
$ adb devices
postmarketOS    host
$ adb shell uname -a
Linux xiaomi-polaris ... aarch64 GNU/Linux
```

## 三个关键坑（调试过程记录）

1. **SSH 会话断开会杀死 adbd**：pmOS 用 systemd，SSH 断开时会回收整个 session
   cgroup，挂在会话下的 adbd/守护脚本全部被杀 → adbd 一死 functionfs 关闭 →
   整个 gadget 从宿主机消失 → USB 网络中断且无法远程恢复（锁死，只能重启）。
   **必须用 `systemd-run` 起独立 transient unit 运行。**
2. **configfs 绑定期间禁止创建函数 symlink**：`ln -s functions/ffs.adb configs/c.1/`
   在 UDC 已绑定时返回 ENOENT/EINVAL 失败（`mkdir functions/ffs.adb` 和挂载
   functionfs 则允许）。`ln` 必须放在 `echo "" > UDC` 与 `echo $UDC > UDC`
   的临界窗口内。
3. **configfs symlink 目标相对 cwd 解析**：`ln -s ../../functions/ffs.adb` 必须
   先 `cd` 到 `configs/c.1` 里执行，否则相对 shell 的家目录解析报 ENOENT。

脚本因此设计为：**独立网络看门狗先行**（UDC 空超过 6 秒强制重绑，ffs 绑不上
则自动剔除 ffs 只恢复 NCM 网络，保证任何失败都不会锁死设备）→ 不断网的准备
工作 → 最短临界窗口 → adbd/UDC 守护循环。日志在手机 `/tmp/adbd-setup.log`。

## 持久化建议

当前脚本与 adbd 均位于 `/tmp`，重启后失效。持久化可将二进制与脚本移至
`/usr/local`，并写一个开机自启的 systemd unit（`After=network.target`，
执行同款脚本）。
