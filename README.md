# Xiaomi Mi MIX 2S (polaris) — postmarketOS 修复记录

- 设备：Xiaomi Mi MIX 2S（DT compatible: `xiaomi,polaris` / `qcom,sdm845`）
- 内核：`linux-postmarketos-qcom-sdm845` 7.1.0-rc1（sdm845-mainline/linux）
- 环境：pmbootstrap 3.11.1，channel `systemd-v26.06`，UI `phosh`
- 本仓库内容：`pmaports-xiaomi-polaris.patch` —— 改动 pmaports 的 4 个文件

## 一、修的是什么

### 1. 开机黑屏（能 SSH、屏幕全黑）

症状：SSH 可登录但屏幕无显示，`dmesg` 里面板初始化失败：

```
failed to send DCS Init 1st Code: -22
```

原因：`panel-novatek-nt35596s.c` 在 DSI host 上电之前就发送了 DCS 初始化命令。

修复（`nt35596s-prepare-prev-first.patch`）：在 `nt35596s_panel_add()` 中 `drm_panel_init()` 之后加一行

```c
pinfo->base.prepare_prev_first = true;
```

并把该补丁文件加进 `linux-postmarketos-qcom-sdm845` 的 `source=`。

### 2. GPU 固件早期加载失败（zap shader）

症状：`dmesg` 早期（约 1.2s）出现

```
adreno 5000000.gpu: [drm:adreno_zap_shader_load] *ERROR* Unable to load qcom/sdm845/Xiaomi/polaris/a630_zap.mbn
msm_dpu ae01000.display-controller: [drm:adreno_load_gpu] *ERROR* gpu hw init failed: -2
```

原因：adreno / msm_dpu 是**内建驱动**，在 rootfs 挂载前初始化 GPU；内核请求的是按设备树拼出的路径 `qcom/sdm845/Xiaomi/polaris/`，而上游固件包只安装 `qcom/sdm845/polaris/`。

修复（改 `firmware-xiaomi-polaris`）：`package()` 中额外把 `a630_zap.mbn` 装到 `qcom/sdm845/Xiaomi/polaris/`，并把该路径加进 `30-gpu-firmware.files`（initramfs 清单），`pkgrel` 0→1。

> 固件必须进 initramfs：rootfs 里的文件要挂载后才可见，而 GPU 初始化更早。符号链接不可靠，必须真实复制文件。

## 二、从零复现（逐条执行）

### 0. 前置

```bash
export PATH="$HOME/.local/bin:$PATH"
pmbootstrap --version          # 3.11.1

# 需要访问 GitHub 时设代理（按自己环境修改）
export http_proxy=http://192.168.1.17:7890
export https_proxy=http://192.168.1.17:7890
```

### 1. 初始化（只需一次）

```bash
pmbootstrap init
# vendor: xiaomi / device: polaris / UI: phosh / systemd: yes
```

### 2. 应用补丁

```bash
cd ~/.local/var/pmbootstrap/cache_git/pmaports
git apply /path/to/pmaports-xiaomi-polaris.patch
git status --short
```

若出现 hunk 冲突（上游改过 `pkgrel` / `source=`），手动改这几处：

- `device/community/linux-postmarketos-qcom-sdm845/APKBUILD`：`source=` 中加入 `nt35596s-prepare-prev-first.patch`，并把补丁文件放入同目录
- `device/testing/firmware-xiaomi-polaris/APKBUILD`：`package()` 末尾加，并把 `pkgrel` +1

```sh
install -Dm644 lib/firmware/qcom/sdm845/polaris/a630_zap.mbn \
    "$pkgdir/lib/firmware/qcom/sdm845/Xiaomi/polaris/a630_zap.mbn"
```

- `device/testing/firmware-xiaomi-polaris/30-gpu-firmware.files` 追加一行

```
/lib/firmware/qcom/sdm845/Xiaomi/polaris/a630_zap.mbn
```

### 3. 预置固件 tarball（关键）

chroot 内的 busybox wget 通过 HTTP 代理拉 HTTPS 会返回 502，必须在宿主机下载好、按 abuild 期望的文件名放进 distfiles：

```bash
curl -L --fail --retry 3 -o /tmp/firmware-xiaomi-polaris.tar.gz \
  https://github.com/MollySophia/firmware-xiaomi-polaris/archive/d88ffb2ee182d07567bf280fc4a8493f975ae977.tar.gz

sha512sum /tmp/firmware-xiaomi-polaris.tar.gz
# 期望 49140fbdf15dbf181e1c35788970b45be78c3959222c455133495ee8ad4c6d76581926dfc2eb1ca32f2cdd6390d9fe05c2c497929cd9e3286591bfe8b5ff54eb

sudo mv /tmp/firmware-xiaomi-polaris.tar.gz \
  ~/.local/var/pmbootstrap/cache_distfiles/firmware-xiaomi-polaris.tar.gz
sudo chmod 644 ~/.local/var/pmbootstrap/cache_distfiles/firmware-xiaomi-polaris.tar.gz
```

`cache_distfiles` 属 `root:abuild`，必须用 sudo 写入；文件名不能改（abuild 按 `source=` 里 `::` 左边的名字找文件）。

### 4. 构建

```bash
cd ~/.local/var/pmbootstrap/cache_git/pmaports

pmbootstrap checksum linux-postmarketos-qcom-sdm845
pmbootstrap build --force linux-postmarketos-qcom-sdm845    # 首次约 5 小时

pmbootstrap checksum firmware-xiaomi-polaris
pmbootstrap build --force firmware-xiaomi-polaris           # 很快
```

### 5. 安装与刷机

```bash
pmbootstrap install
pmbootstrap flasher flash_kernel
pmbootstrap flasher flash_rootfs --partition userdata
```

### 6. 重启后验证

```bash
ssh wxs@172.16.42.1

# 重刷 rootfs 会丢 sudo 白名单，先补回来
echo 'wxs ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/99-wxs-nopasswd
sudo chmod 440 /etc/sudoers.d/99-wxs-nopasswd

sudo dmesg | grep -iE "zap|gpu hw"        # 期望：无输出
sudo dmesg | grep -iE "adreno|msm_dpu" | head -20
ls -l /lib/firmware/qcom/sdm845/Xiaomi/polaris/a630_zap.mbn   # 14256 字节，普通文件
```

### 7. 收尾

```bash
pmbootstrap shutdown
```

## 三、踩过的坑

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `wget: server returned error: HTTP/1.1 502` | chroot 内 busybox wget 不支持经 HTTP 代理做 HTTPS CONNECT | 宿主机 curl 预置 distfiles |
| 写 cache_distfiles 报 `Permission denied` | 该目录被 pmbootstrap 改为 `root:abuild` | 用 `sudo mv` |
| 改动不生效 | 本地包与上游版本号相同，apk 选了上游未修改的包 | bump `pkgrel` |
| 重刷 rootfs 后 sudo 失效 | 白名单不在包里 | 重写 `/etc/sudoers.d/99-wxs-nopasswd` |
| 固件放 rootfs 无效 | 内建驱动在 rootfs 挂载前初始化 | 必须进 initramfs 的 `.files` 清单 |
| 手工拷固件到 `Xiaomi/polaris/` | 重启即忘，不是持久修复 | 已由固件包接管 |
