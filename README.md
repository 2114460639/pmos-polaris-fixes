# Xiaomi Mi MIX 2S (polaris) — postmarketOS 修复记录
- 设备：Xiaomi Mi MIX 2S（DT compatible: `xiaomi,polaris` / `qcom,sdm845`）
- 内核：`linux-postmarketos-qcom-sdm845` 7.1.0-rc1（sdm845-mainline/linux）
- 环境：pmbootstrap 3.11.1，channel `systemd-v26.06`，UI `phosh`
- 本仓库内容：`pmaports-xiaomi-polaris.patch` —— 改动 pmaports 的 4 个文件
- **验收状态：2026-09-27 全新刷机（fastboot 全量）验证通过** —— 屏幕/触摸正常、GPU 无错、WiFi 5G 866.7Mbps 满速、GUI 音频 + 浏览器网页 mic/扬声器均通过、录音正常、电池 99%。开箱即用达成。

## 〇、功能支持情况（2026-09-27 实测）

| 功能 | 支持情况 | 修复内容 |
| --- | --- | --- |
| Device 设备 | Xiaomi Mi Mix 2S | — |
| Codename 代号 | xiaomi-polaris | — |
| Category 类别 | testing | — |
| Architecture 架构 | aarch64 | — |
| Released 发布年份 | 2018 | — |
| USB Net USB 网络 | Y | — |
| Flashing 刷机 | Y | — |
| Touch 触控 | P | 全新刷机后触摸正常工作 |
| Screen 屏幕 | P | ✅ 修复开机黑屏（nt35596s prepare_prev_first 补丁），显示正常正常工作 |
| Wifi Wi-Fi | P | ✅ 5GHz 满速 AC 866.7Mbps（VHT cap 0x3381f9b2 + Highest 780 补丁）iperf3测速650Mbps左右 |
| FDE 全盘加密 | Y | — |
| Battery 电池 | P | ✅ 电量计修复（polaris-battery-fg 补丁），实时电量正常 |
| 3D 3D 图形 | Y | ✅ GPU 固件 a630_zap 路径修复（dmesg 无 zap/gpu 错误） |
| IMU 惯性测量单元 | （未测试） | — |
| Audio 音频 | P | ✅ 无声卡→全自动（DTS 音频节点 + PA/路由固化），GUI+浏览器 mic/扬声器验收通过 |
| Bluetooth 蓝牙 | Y | — |
| Camera 摄像头 | N | 🔧 进行中：IMX363 主摄（CCI i2c 0x10 无 ACK，tlmm102 待验证） |
| GPS | （未测试） | — |
| Mobile Data 移动数据 | Y | — |
| SMS 短信 | Y | — |
| Calls 通话 | P | — |
| USB-OTG USB OTG | N | — |
| NFC | （未测试） | — |
| HDMI/DP | - | — |

状态码：**Y** = 完全可用（Yes, fully implemented）· **P** = 部分可用（Partially implemented）· **N** = 不可用（Not working yet）· **-** = 设备无此功能（Not applicable）· 空 = 未测试（Untested）

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

### 3. 摄像头（Sony IMX363 主摄——进行中）
症状：`camss` 平台驱动不 probe（dmesg `Unsupported bus type 2`）；IMX363 传感器注册失败（`failed to read chip id 363: -110`）；libcamera `cam --list` 无相机。
修复（`polaris-camera.patch`）：在 `sdm845-xiaomi-polaris.dts` 追加摄像头节点 + 使能 camss/cci + MCLK pinctrl。当前状态：**camss 已绑定并注册 `/dev/video0-8`**；IMX363 probe 仍卡在 CCI i2c 对 0x10 无 ACK（-110），电源/时钟/地址已逐项对齐 LineageOS，剩余疑点 tlmm 102（CUSTOM0）待验证。

#### 补丁内容（dts 手动追加，或直接应用本目录 `polaris-camera.patch`）
```dts
/* Camera: Sony IMX363 rear sensor (main) */
/ {
        cam_vdig_rear: regulator-cam-vdig-rear {
                compatible = "regulator-fixed";
                regulator-name = "cam_vdig_rear";
                regulator-min-microvolt = <1050000>;
                regulator-max-microvolt = <1050000>;
                regulator-enable-ramp-delay = <135>;
                enable-active-high;
                gpio = <&pm8998_gpios 11 GPIO_ACTIVE_HIGH>;
        };
};
&camss {
        status = "okay";
        ports {
                port@0 {
                        camss_csi0_ep: endpoint {
                                remote-endpoint = <&imx363_ep>;
                                data-lanes = <1 2>;
                        };
                };
        };
};
&cci {
        status = "okay";
};
&cci_i2c0 {
        imx363: camera-sensor@10 {
                compatible = "sony,imx363";
                reset-gpios = <&tlmm 80 GPIO_ACTIVE_LOW>;
                reg = <0x10>;
                vana-supply = <&vreg_bob>;
                vdig-supply = <&cam_vdig_rear>;
                vif-supply = <&vreg_lvs1a_1p8>;
                pinctrl-names = "default";
                pinctrl-0 = <&cam_mclk0_default>;
                clocks = <&clock_camcc CAM_CC_MCLK0_CLK>;
                clock-frequency = <24000000>;
                port {
                        imx363_ep: endpoint {
                                remote-endpoint = <&camss_csi0_ep>;
                                data-lanes = <1 2>;
                                link-frequencies = /bits/ 64 <636000000>;
                        };
                };
        };
};
&tlmm {
        cam_mclk0_default: cam-mclk0-default-state {
                pins = "gpio13";
                function = "cam_mclk";
                drive-strength = <2>;
                bias-disable;
        };
        cam_vana_en: cam-vana-en-state {
                gpio-hog;
                gpios = <87 0>;
                output-high;
        };
};
```
要点：
- 主摄拓扑（来自 LineageOS `polaris-camera-sensor-mtp.dtsi` 核对）：cci-master0 / csiphy0 / MCLK0=tlmm13 / RESET=tlmm80 / VANA=tlmm87（bob 供电）/ vdig=pm8998 GPIO11（1.05V，vin=pm8998_s3）/ vif=pm8998_lvs1 / i2c 地址 0x10（与 mainline 小米 8 beryllium 同款 IMX363 一致）。
- `link-frequencies` 必须给 636000000（imx363.c 的 `link_freq_menu_items_24`），否则 probe 报 "Link frequency not supported"。
- `camss` endpoint 必须带 `data-lanes`，否则 bus_type 解析成非 CSI2 报 `Unsupported bus type 2`。
- MCLK 必须显式 pinctrl（gpio13 `cam_mclk`），否则 MCLK 时钟到不了引脚、传感器不响应。

### 4. 音频（无声卡 → GUI 无声 → 全自动——已修复，firmware 包 r15 收官）
症状：
- 命令行 `aplay -l` → `no soundcards found`，`/dev/snd/` 只有 timer
- GUI 设置：Output = **Dummy Output**、Input = **No Input Devices**（WirePlumber 没枚举到 ALSA 卡 0，声卡注册晚于 WirePlumber 启动）
- 内核 config 全齐（`SND_SOC_SDM845=m`、`SND_SOC_WCD934X=m`、`SND_SOC_TFA98XX=m`、`SND_SOC_TFA989X=m`），但 `dmesg` 无音频日志

根因：
- 2022 年 polaris 进上游内核的补丁**明确不含音频**，polaris DTS 一直没有音频节点 → 驱动虽编译但无设备可 probe → 无声卡
- polaris DTS 已 include `sdm845-wcd9340.dtsi`（codec 骨架在），但缺 `&sound` / `&wcd9340` / `&tas2559` 定制节点
- ADSP 固件路径不匹配：mainline 音频（q6afe）走 ADSP，设备只有 `qcom/sdm845/polaris/adsp.mbn`，缺默认路径 `qcom/sdm845/adsp.mbn`

修复（参照 OnePlus 6 / DB845c / Pixel 3 / beryllium——同 TAS2559 功放）：
- 内核侧（`polaris-audio.patch` 进 `linux-postmarketos-qcom-sdm845` 的 `source=`）：DTS 补 `&sound` + WCD9340 codec + TFA98xx 功放节点
- 用户态固化（`firmware-xiaomi-polaris` 包内，pkgrel 递增至 r15，APKBUILD source= 20-24 行，5 个文件）：
  - `polaris-speaker-routing.service`：等 `/dev/snd/controlC0` 出现后 `amixer` 打开 `QUAT_MI2S_RX -> TAS2559` 播放路由
  - `polaris-mic-routing.service`：等声卡后打开 `AMIC -> ADC -> DEC -> AIF1_CAP -> SLIM TX0` 录音路由
  - `polaris-pulse-setup.service`：**pactl 兜底**——等声卡 + 确认路由 on 后，pactl 加载 `module-alsa-sink device=hw:0,0 sink_name=polaris_spk`，再 `suspend-sink 1/0` 强制 sink 重新初始化，最后设默认/音量/不静音（`Restart=on-failure` 可重试）
  - `polaris-pulse-default.pa`：随 PA 启动自动加载的配置片段，**安装到 `/etc/pulse/default.pa.d/50-polaris.pa`**（load-module module-alsa-sink + set-default-sink polaris_spk）
  - `50-polaris.preset`：`enable polaris-mic-routing.service` / `enable polaris-speaker-routing.service`（解决 apk 升级时 systemd preset 删掉包内 symlink、开机不自动跑的问题）
- 输出避开 MM1（MM1 DAI 怪异行为）：播放走 **MM3（hw:0,2）**、录音走 **MM2（hw:0,1）**

验收（r15）：GUI 播放/录音/开机声全自动，重启后全部自动生效，开箱即用。

### 5. WiFi（5GHz：不能连 → 144.4Mbps（n 模式）→ 866.7Mbps 满速 AC——已修复）
三阶段症状与根因（决定性证据：三台设备关联请求对比）：
| 设备 | VHT 能力 | MCS Map | RX/TX Highest | 结果 |
|---|---|---|---|---|
| 小米 15 | 0x3381f9b2 | 0xfffa | 780（0x030c） | ✅ 接受 |
| XiaomiCommun | 0x3381f9b2 | 0xfffa | 780（0x030c） | ✅ 接受 |
| polaris（本机） | **0x738139fa** | 0xfffa | **0（0x0000）** | ❌ 拒绝（reason 18） |

- **① 5GHz 连不上**：路由 `SEND ASSOC RSP reason=18`（GUI 弹密码错）。根因：驱动把 VHT cap 报成 `0x738139fa`，含 **80+80MHz + EXT-NSS=01 非法组合**，被路由器 qcawifi 以 `Invalid supported ch width and ext nss combination` 拒绝。修复：**`polaris-wifi-vht-cap-80.patch`** —— VHT cap 清掉 EXT_BANDWIDTH（0xc0000000）和 SUPP_80_80MHZ（0x8）→ `0x3381f9b2`（纯 80MHz 合法值）。
- **② 能连但 144.4Mbps（n 模式）**：路由器接受关联（80ms authenticated→associated），但协商出 `144.4 MBit/s MCS 15 short GI`（HT40 双流），VHT 协商失败。根因：**RX/TX Highest = 0**（小米 15 是 780）。修复：**`polaris-wifi-vht-highest-780.patch`** —— mac.c 把 `tx_highest = cpu_to_le16(780)`。
- **③ 866.7Mbps 满速**：`866.7 MBit/s VHT-MCS 9 80MHz short GI VHT-NSS 2` = 2x2 80MHz VHT 理论上限，连 `Xiaomi_AX6000_5G`（5180MHz，-38dBm）。
- 另有 **`polaris-wifi-host-cap-skip-quirk.patch`**（跳过 host capability 覆盖的 quirk，不碰驱动行为）——用户仓库 `pmos-polaris-fixes` 自带，与上述补丁一起生效。

> 诊断期还试过 `polaris-wifi-vht-mcs-0-11.patch`（MCS 0-9→0-11），后经三设备对比确认 **MCS 声明不是差异**（三台 MCS Map 都是 0xfffa），该补丁非最终必需——以 APKBUILD source= 实际收录为准。

## 二、从零复现（逐条执行）

### 0. 前置
```bash
export PATH="$HOME/.local/bin:$PATH"
pmbootstrap --version          # 3.11.1
# 需要访问 GitHub 时设代理（按自己环境修改）

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

### 3. 摄像头补丁
```bash
# 内核源码工作区（sdm845-mainline）里改 dts
cd /tmp/linux/arch/arm64/boot/dts/qcom
# 按"一、3"的手动内容追加到 sdm845-xiaomi-polaris.dts（或用本目录 polaris-camera.patch）
# 生成补丁并拷入包目录
cd /tmp/linux
git diff arch/arm64/boot/dts/qcom/sdm845-xiaomi-polaris.dts > /tmp/polaris-camera.patch
cp /tmp/polaris-camera.patch \
  ~/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-qcom-sdm845/
# APKBUILD source= 列表追加一行（在 polaris-slim-ngd-msgdbg2.patch 之后）
#     polaris-camera.patch
# 构建必须带代理，否则 Update package index 卡 0%
export http_proxy=http://192.168.1.10:7899 https_proxy=http://192.168.1.10:7899
cd ~/.local/var/pmbootstrap/cache_git/pmaports
pmbootstrap checksum linux-postmarketos-qcom-sdm845 && pmbootstrap build linux-postmarketos-qcom-sdm845 --force
```
> 小参数修改不递增 `pkgrel`：`build --force` 覆盖同名 apk 再强制安装即生效；重大突破/修改才递增。

### 3.5 音频修复（firmware 包，已收官）
```bash
# firmware-xiaomi-polaris 包目录（device/testing/firmware-xiaomi-polaris/）内新增：
cd ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/firmware-xiaomi-polaris
# ① polaris-pulse-default.pa —— PA 启动自动加载 hw:0,0 为默认 sink
cat > polaris-pulse-default.pa <<'EOF'
# Polaris ALSA sink as default output (loaded at every PulseAudio start)
load-module module-alsa-sink device=hw:0,0 sink_name=polaris_spk rate=48000
set-default-sink polaris_spk
set-sink-volume polaris_spk 100%
set-sink-mute polaris_spk 0
EOF
# ② polaris-speaker-routing.service —— 等声卡后开 QUAT_MI2S_RX -> TAS2559 播放路由
# ③ polaris-mic-routing.service —— 等声卡后开 AMIC -> SLIM TX0 录音路由
# ④ 50-polaris.preset —— systemd preset 固化（防 apk 升级删 symlink）
cat > 50-polaris.preset <<'EOF'
enable polaris-mic-routing.service
enable polaris-speaker-routing.service
EOF
# ⑤ APKBUILD：source= 加入上述 4 个文件，pkgrel 递增（最终 r15）
# 内核侧：polaris-audio.patch（DTS &sound + wcd9340 + tas2559）已进 linux 包 source=
pmbootstrap checksum firmware-xiaomi-polaris && pmbootstrap build --force firmware-xiaomi-polaris
# 升级：scp apk -> sudo apk add --force-overwrite -> reboot（同摄像头流程）
```
> 路由服务要点：`Type=oneshot`，`After=sound.target`，`ExecStart` 先轮询等待 `/dev/snd/controlC0` 出现（最多 100 次 × 0.2s），再 `amixer -c 0 sset` 打开对应 mixer 路由（播放 QUAT_MI2S_RX 通路、录音 AMIC->SLIM TX0 通路）。
> `polaris-pulse-setup.service` 是 pactl 兜底（等 pactl 就绪后 load-module + suspend-sink 1/0 强制重初始化 + set-default），`polaris-pulse-default.pa` 装到 `/etc/pulse/default.pa.d/50-polaris.pa` 随 PA 启动加载——两者并存双保险。

### 3.6 WiFi 修复（5GHz 满速 AC，已收官）
```bash
# 补丁文件进内核包目录（device/community/linux-postmarketos-qcom-sdm845/）：
#   polaris-wifi-vht-cap-80.patch         VHT cap 清非法组合（0x738139fa → 0x3381f9b2）
#   polaris-wifi-vht-highest-780.patch    RX/TX Highest = 780（0x030c）
#   polaris-wifi-host-cap-skip-quirk.patch 跳过 host capability 覆盖 quirk
# APKBUILD source= 追加 3 个补丁名，pkgrel 递增
# 关键实现细节（7.1-rc1 字段改名）：
#   vht-cap-80：mac.c 里 `band->vht_cap.vht_cap_info` 已改名为 `band->vht_cap.cap`，
#   IEEE80211_VHT_CAP_* 宏在 7.1-rc1 已移除 → 用裸 hex：`cap &= ~0xc0000000; cap &= ~0x00000008;`
#   vht-highest-780：`band->vht_cap.vht_mcs.tx_highest = cpu_to_le16(780);`
# 构建 + 升级同摄像头流程（pmbootstrap build --force + scp apk + apk add --force-overwrite + reboot）
```
> **必踩坑**：`pmbootstrap flasher flash_kernel` 只刷 boot 分区（zImage+initrd），**内核模块在 rootfs `/usr/lib/modules/` 不会更新**——补丁编译进模块后必须升级内核 apk（`sudo apk add --force-overwrite`）让模块也更新，否则设备一直跑旧 ath10k 模块（表现为 `iw phy` 的 VHT cap 还是旧值）。

### 4. 构建（其余）
```bash
pmbootstrap checksum firmware-xiaomi-polaris
pmbootstrap build --force firmware-xiaomi-polaris           # 很快
```

### 5. 安装与刷机
```bash
pmbootstrap install
pmbootstrap flasher flash_kernel
pmbootstrap flasher flash_rootfs --partition userdata
```
> 摄像头迭代期用 SSH 升级内核即可（不用整机重刷）：
```bash
APK=$(ls -t ~/.local/var/pmbootstrap/packages/v26.06/aarch64/linux-postmarketos-qcom-sdm845-*.apk | head -1)
sshpass -p password scp "$APK" user@172.16.42.1:/tmp/
sshpass -p password ssh user@172.16.42.1 "sudo apk add --force-overwrite /tmp/$(basename $APK) 2>&1 | tail -3"
sshpass -p password ssh user@172.16.42.1 "sudo reboot"
sleep 90
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
# 摄像头
sudo mount -t debugfs none /sys/kernel/debug
sudo grep -E 'gpio13 ' /sys/kernel/debug/gpio              # 期望：func1 cam_mclk
ls /sys/bus/i2c/devices/16-0010/driver 2>/dev/null         # 期望：指向 imx363
ls /dev/video* | wc -l                                     # camss 绑定后 9 个节点
export XDG_RUNTIME_DIR=/run/user/$(id -u user)
cam --list                                                 # 期望：列出 IMX363 相机
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
| pmbootstrap 下载卡 `Update package index 0%` | 未导出代理，chroot 内 apk 拉不到网络 | 构建前 `export http_proxy/http_proxy` |
| python `str.replace` 改 dts 静默失败 | 缩进不匹配（tab/空格、12/16 空格） | 用"按行遍历插入"自动复制缩进，改后必须 `grep` 验证 |
| dts 改了但手机不生效 | `git diff` 生成的 patch 没拷进包目录 / checksum 没重跑 | patch 拷入后 `pmbootstrap checksum` 再 build；用 `/sys/firmware/devicetree/base/...` 核对实际 DTB |
| scp 通配符拖 19 个历史 apk 卡死 | 文件名带版本号累积 | `APK=$(ls -t ... | head -1)` 只取最新 |
| imx363 `no link frequencies in firmware` | endpoint 缺 `link-frequencies` | 补 `/bits/ 64 <636000000>` |
| camss `Unsupported bus type 2` | endpoint 缺 `data-lanes`，bus_type 解析失败 | 补 `data-lanes = <1 2>` |
| imx363 probe `-110`（CCI timeout） | 详见"四、当前卡点" | 逐项核对电源/时钟/地址 |
| `no soundcards found` / `/dev/snd/` 只有 timer | polaris DTS 缺音频节点（上游补丁不含音频），驱动无设备可 probe | 移植 `&sound` + WCD9340 + tas2559 节点（抄 beryllium） |
| GUI 显示 Dummy Output / 无声 | WirePlumber 启动早于声卡注册，没枚举到 ALSA 卡 0 | PA 启动时 `module-alsa-sink` 显式加载 hw:0,0 为默认 sink |
| 播放走 MM1 异常 | MM1 DAI 怪异行为 | 输出改 MM3（hw:0,2）、输入 MM2（hw:0,1） |
| 开机路由不自动生效 | apk 升级时 systemd preset 删掉包内 symlink（is-enabled=disabled） | 用 `50-polaris.preset`（preset 机制重建 symlink） |
| 音频无声音但驱动 probe 正常 | ADSP 固件路径不匹配（缺 `qcom/sdm845/adsp.mbn`） | 固件路径补丁补 adsp |
| 5GHz 连不上（reason 18 / 弹密码错） | VHT cap 报 0x738139fa（80+80 + EXT-NSS=01 非法组合）被路由 qcawifi 拒 | `polaris-wifi-vht-cap-80.patch` 清位 → 0x3381f9b2 |
| 能连 5G 但只有 144.4Mbps（n 模式） | RX/TX Highest = 0，VHT 协商失败（小米 15 是 780） | `polaris-wifi-vht-highest-780.patch` 设 Highest=780 |
| 内核补丁编译了但设备行为没变 | `flash_kernel` 只刷 boot 分区，rootfs 里 `/usr/lib/modules/` 的模块是旧的 | 升级内核 apk（`apk add --force-overwrite`）让模块也更新 |
| 7.1-rc1 编译报宏未定义 | `vht_cap_info` 改名 `cap`、`IEEE80211_VHT_CAP_*` 宏移除 | 用裸 hex（0xc0000000 / 0x8）+ 新字段名 |

## 四、当前卡点（摄像头 IMX363 未点亮）
- 现象：`imx363 16-0010: Error reading reg 0x0016: -110`；`i2cdetect -y -r 16` 0x10 无 ACK（且全总线无设备响应）。
- 已排除/已对齐：
  - i2c 地址 0x10 —— 与 mainline 小米 8（beryllium-common.dtsi）同款 IMX363 一致；
  - MCLK —— gpio13 已复用 `cam_mclk`（debugfs func1），`cam_cc_mclk0_clk` 24MHz 配置成功；
  - 电源 —— vana=bob / vdig=pm8998 GPIO11(1.05V) / vif=lvs1，与 LineageOS `polaris-camera-sensor-mtp.dtsi` 的 `cam_vana-supply/cam_vdig-supply/cam_vio-supply` 完全一致；
  - CCI 引脚 —— pinmux 已复用 `cci_i2c`（gpio17-20）。
- 待验证：**tlmm 102（CUSTOM0）** —— LineageOS 主摄 `gpios = <&tlmm 13 0>, <&tlmm 80 0>, <&tlmm 87 0>, <&tlmm 102 0>`，`gpio-custom1 = <3>`，且 `polaris-p0-pinctrl.dtsi` 的 `cam_sensor_rear_active` 把 gpio80/87/102 配为一组（注释 "RESET, AVDD LDO"）。当前 polaris.dts 未配置 tlmm 102（手机端显示 `in low func0`），可能是传感器缺失的使能信号，待补 `gpio-hog` 或 pinctrl 验证。
- 已知未做：副摄（IMX376）/前摄未启用；IMX363 主摄仍在排障（见上）。除摄像头外其余功能已全量验收通过（见仓库顶部"验收状态"）。
