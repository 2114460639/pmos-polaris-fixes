# Xiaomi Mi MIX 2S (polaris) — postmarketOS 修复记录
- 设备：Xiaomi Mi MIX 2S（DT compatible: `xiaomi,polaris` / `qcom,sdm845`）
- 内核：`linux-postmarketos-qcom-sdm845` 7.1.0-rc1（sdm845-mainline/linux）
- 环境：pmbootstrap 3.11.1，channel `systemd-v26.06`，UI `phosh`
- 本仓库内容：各功能补丁（内核 dts/驱动 + firmware 包 + 用户态固化）、一键脚本 `build.sh`、完整补丁 `pmaports-xiaomi-polaris.patch`（28 个文件变更，可一步 `git apply`）、ADB 方案（`polaris-adbd-build.sh` + `polaris-adbd-setup.sh` + `adbd-linux.patch`，已固化为 pmaports 包 `adbd-polaris` + systemd 开机自启，见「一、7」）
- **一键构建**：`PROXY=http://127.0.0.1:7890 ./build.sh`（= 打补丁 + checksum + 构建三个包；`DO_INSTALL=1` 生成镜像、`DO_FLASH=1` 再刷机）
- 本仓库**不含二进制固件**：`wlanmdsp-01387.mbn` 属专有二进制，不宜再分发，需按「二、2」自备
- **验收状态：2026-09-27 全新刷机（fastboot 全量）验证通过** —— 屏幕/触摸正常、GPU 无错、WiFi 5G 866.7Mbps 满速、GUI 音频 + 浏览器网页 mic/扬声器均通过、录音正常、电池 99%。开箱即用达成。
- **摄像头补丁（2026-09-29 验证）**：IMX363 主摄已出图，`polaris-camera.patch` 见「一、3」与「四」。
- **系统语言 / 目录名（2026-09-30 固化）**：界面默认中文、默认文件夹名保持英文、内置中文字体，见「一、6」。
- **ADB 调试（2026-10-01 验证并固化）**：postmarketOS 上跑通 adbd（USB functionfs，与 NCM 网络共存），已打包为 `adbd-polaris` 包随刷机镜像开机自启；`adb devices`/`adb shell`/`adb reboot bootloader` 实测通过，见「一、7」与「二、3.7」。

## 〇、功能支持情况（2026-09-27 实测）

| 功能 | 支持情况 | 修复内容 |
| --- | --- | --- |
| Device 设备 | Xiaomi Mi Mix 2S | — |
| Codename 代号 | xiaomi-polaris | — |
| Category 类别 | testing | — |
| Architecture 架构 | aarch64 | — |
| Released 发布年份 | 2018 | — |
| USB Net USB 网络 | Y | — |
| ADB adb 调试 | Y | ✅ adbd over USB functionfs（与 NCM 网络共存），已打包 `adbd-polaris` 随镜像开机自启；`adb devices`/`shell`/`reboot bootloader` 验证通过（2026-10-01，见「一、7」） |
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
| Camera 摄像头 | P | ✅ IMX363 主摄已出图：i2c 0x1a、cam_vio(GPIO21) 1.8V 供电、4-lane、rotation=270；libcamera/v4l2 均验证通过（见 polaris-camera.patch，仅 dts）。遗留：软件 ISP 偏暗、偶有掉帧、开机后立刻测会长时间不出帧 |
| GPS | （未测试） | — |
| Mobile Data 移动数据 | Y | — |
| SMS 短信 | Y | — |
| Calls 通话 | P | — |
| Localization 本地化 | — | 界面默认中文（zh_CN.UTF-8）+ 默认文件夹名保持英文 + font-noto-cjk（2026-09-30 固化，见「一、6」） |
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

### 3. 摄像头（Sony IMX363 主摄——已修复，可出图）
症状：`camss` 平台驱动不 probe（dmesg `Unsupported bus type 2`）；IMX363 传感器注册失败（`failed to read chip id 363: -110`/`-6`）；libcamera `cam --list` 无相机。
根因（3 个，缺一不可）：
1. **I2C 地址错**：原补丁写 `reg = <0x10>`，实测 IMX363 在 **`0x1a`**（读 0x0016 得到 0x0363 芯片 ID）。probe 报 `-6`(NACK) 而非 `-110`(timeout) 是定位此问题的决定性信号。
2. **cam_vio 供电缺失**：量产 polaris 的 CAM_VIO 不是 `pm8998_lvs1`，而是 **`&tlmm 21` 控制的 1.8V 固定稳压器**（vin=pm8998_s4）。缺失时传感器 I2C 域无供电、模块静默不应答。
3. **lane 数不全**：必须 4-lane（sensor 侧 `data-lanes = <0 1 2 3>`，camss 侧 `clock-lanes = <7>`），并补齐 camss 的 `vdda-phy/pll/csi0-2` 供电。
修复（`polaris-camera.patch`，**仅 dts**）：新增 `cam_vio_rear`(tlmm21) 稳压器、sensor 改 `reg = <0x1a>`、`vif-supply = <&cam_vio_rear>`、4-lane + link-freq 636MHz、camss 供电与 endpoints。
**实测结果**：`imx363 16-001a` probe 成功（`pixel_rate: 508800000`，4 lanes），media 拓扑 `imx363 → msm_csiphy0 → msm_csid0 → msm_vfe0_rdi0` 全通，可出图（ABGR8888，满分辨率 **4032x3024**）。
**帧率**：满分辨率 4032x3024 **30fps**（实测帧间隔 30.36/29.12/30.43fps，每帧 48,771,072 B），1080p 同为 30.3fps；首帧延迟约 0.4s。偶有掉帧（间隔掉到 15/7.6fps）。
> 注意：**开机后不要立刻测**。系统刚启动时负载高（实测 load 2.11），此时首次调用 libcamera 可能几十秒不出帧，属正常现象，不是相机故障。

#### 补丁内容

**权威来源是本目录的 `polaris-camera.patch`（仅 dts，共 130 行）**。下方 dts 仅为阅读方便，若与 patch 不一致，以 patch 为准。

```dts
/* Camera: Sony IMX363 rear sensor (main) */
/ {
	cam_vio_rear: regulator-cam-vio-rear {
		compatible = "regulator-fixed";
		regulator-name = "cam_vio_rear";
		regulator-min-microvolt = <1800000>;
		regulator-max-microvolt = <1800000>;
		regulator-enable-ramp-delay = <135>;
		enable-active-high;
		gpio = <&tlmm 21 GPIO_ACTIVE_HIGH>;
		vin-supply = <&vreg_s4a_1p8>;
	};

	cam_vdig_rear: regulator-cam-vdig-rear {
		compatible = "regulator-fixed";
		regulator-name = "cam_vdig_rear";
		regulator-min-microvolt = <1050000>;
		regulator-max-microvolt = <1050000>;
		regulator-enable-ramp-delay = <135>;
		enable-active-high;
		gpio = <&pm8998_gpios 11 GPIO_ACTIVE_HIGH>;
		pinctrl-names = "default";
		pinctrl-0 = <&pm8998_gpio11_default>;
	};
};

&camss {
	vdda-phy-supply = <&vreg_l1a_0p875>;
	vdda-pll-supply = <&vreg_l26a_1p2>;
	vdda-csi0-supply = <&vreg_l1a_0p875>;
	vdda-csi1-supply = <&vreg_l1a_0p875>;
	vdda-csi2-supply = <&vreg_l1a_0p875>;

	status = "okay";
	ports {
		port@0 {
			camss_csi0_ep: endpoint {
				remote-endpoint = <&imx363_ep>;
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
			};
		};
	};
};

&cci {
	status = "okay";
};

&cci_i2c0 {
	clock-frequency = <400000>;
	imx363: camera-sensor@1a {
		compatible = "sony,imx363";
		reset-gpios = <&tlmm 80 GPIO_ACTIVE_LOW>;
		reg = <0x1a>;
		status = "okay";

		vana-supply = <&vreg_bob>;
		vdig-supply = <&cam_vdig_rear>;
		vif-supply = <&cam_vio_rear>;

		clocks = <&clock_camcc CAM_CC_MCLK0_CLK>;
		clock-names = "xvclk";
		pinctrl-names = "default";
		pinctrl-0 = <&cam0_default &cam_mclk0_default>;
		clock-frequency = <24000000>;

		orientation = <1>;
		rotation = <270>;

		port {
			imx363_ep: endpoint {
				remote-endpoint = <&camss_csi0_ep>;
				data-lanes = <0 1 2 3>;
				link-frequencies = /bits/ 64 <636000000>;
			};
		};
	};
};

&tlmm {
	cam0_default: cam0-default-state {
		rst {
			pins = "gpio80";
			function = "gpio";
			drive-strength = <2>;
			bias-disable;
		};
	};
	cam_mclk0_default: cam-mclk0-default-state {
		pins = "gpio13";
		function = "cam_mclk";
		drive-strength = <2>;
		bias-disable;
	};
};
```

要点：
- 主摄拓扑（来自 LineageOS `polaris-camera-sensor-mtp.dtsi` 核对）：cci-master0 / csiphy0 / MCLK0=tlmm13 / RESET=tlmm80 / VANA=bob（tlmm87 hog 使能）/ vdig=pm8998 GPIO11（1.05V）/ **vif=cam_vio_rear（tlmm21 控制 1.8V，vin=pm8998_s4）** / **i2c 地址 0x1a**。
- **I2C 地址必须是 0x1a**（不是 beryllium 那套 0x10）：写错时报 `-6`(NACK)，与供电缺失的 `-110`(timeout) 可区分。
- `link-frequencies` 必须给 636000000（imx363.c 的 24MHz 时钟配置），否则 probe 报 "Link frequency not supported"。
- `camss` endpoint 必须带 `data-lanes` + `clock-lanes = <7>`，否则 bus_type 解析成非 CSI2 报 `Unsupported bus type 2`。**sensor 与 camss 两侧 lane 数必须一致且为 4-lane**。
- `imx363.c` **不需要任何修改**：曾试过改 `imx363_power_on()` 时序（先 `clk_prepare_enable`(MCLK) 再释放 reset），A/B 对照证明**上游原版时序即可正常出图**（1080p 30.3fps、满分辨率 30fps），故该改动已删除，补丁只保留 dts。
- `rotation = <270>`：与同款 IMX363 的 beryllium / sargo / oneplus 后摄一致。写 `<90>` 会让画面上下+左右同时翻转 180°。
- MCLK 必须显式 pinctrl（gpio13 `cam_mclk`），否则 MCLK 时钟到不了引脚、传感器不响应。

> **调试提醒**：不要在用 libcamera 之前手动 `media-ctl -V` 改链路格式。相邻 pad 的 mbus code 不一致会让 `media_pipeline_start()` 返回 `-EPIPE`(-32)（dmesg "Failed to start media pipeline: -32"），或启动成功但 0 帧。恢复方式：`sudo modprobe -r imx363 && sudo modprobe imx363`，或在干净状态下直接 `cam -c1 --capture=N --file=/tmp/x.raw`。

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

### 6. 系统语言与默认目录名（已固化，非内核补丁）
- **界面默认中文**：`pmbootstrap config locale zh_CN.UTF-8` → 构建时由 pmbootstrap 的 `setup_locale()` 写入 `/etc/locale.conf`（同时生成 `/etc/profile.d/10locale-pmos.sh`）。中文翻译包由 `postmarketos-base-ui` 依赖的 `lang` 元包自动拉全，无需手动装。
- **默认文件夹保持英文**：`xdg-user-dirs` 会在首次登录时按语言把 `~/Desktop` 等改名为「桌面/文档/下载」。修复：在 `device-xiaomi-polaris` 包里投放**用户级** `/etc/skel/.config/user-dirs.conf`（`enabled=False`）和 `user-dirs.dirs`（英文路径）。用用户级而非系统级的原因：`/etc/xdg/user-dirs.conf` 属 `xdg-user-dirs` 包、不能被别的包覆盖，而用户级 `~/.config/user-dirs.conf` 可以覆盖它（已实测）。
- **中文字体**：`device-xiaomi-polaris` 的 `depends` 增加 `font-noto-cjk`。
- 以上三处改的是 `device/testing/device-xiaomi-polaris/`（`pkgrel` 0→1），已包含在 `pmaports-xiaomi-polaris.patch` 中。

### 7. ADB 调试（adbd over USB functionfs——已跑通并固化进刷机包，纯用户态，无内核补丁）
背景：参考博客园《Linux usb 7. Linux 配置 ADBD》（<https://www.cnblogs.com/pwl999/p/15675582.html>）的 configfs + functionfs 方案，在 pmOS 上跑 `adbd`，让宿主机用 `adb shell` 调试手机，**同时保留 pmOS 自带的 NCM USB 网络**（`ssh user@172.16.42.1` 不受影响）。

前提（pmOS 默认即满足，无需改内核）：
- `CONFIG_USB_CONFIGFS_F_FS=y`（functionfs），有可用 UDC（本机 `a600000.usb`）
- 现有 `g1` gadget 在跑 NCM 网络（pmOS 开机自动配置）

方案（2026-10-01 在 pmOS v26.06 + 7.1.0-rc1-sdm845 + 宿主机 adb 34.0.5 实测通过）：
1. **adbd**：文章推荐的 [tonyho/adbd-linux](https://github.com/tonyho/adbd-linux) 交叉编译为 **aarch64 全静态二进制**。`adbd-linux.patch` 包含三处源码修改：上游只兼容 OpenSSL 1.0（直接摸 `RSA`/`BIGNUM` 内部结构）→ 改为 `RSA_set0_key`/`RSA_get0_key`/`BN_bn2bin` 等 1.1+/3.x API，配宿主机自编的 OpenSSL 3.3.2 静态库（官方源卡死自动切 gh-proxy 镜像）；Makefile 静态链接修复；**reboot 服务修复**（`property_set` 是空桩，`adb reboot` 原本无效 → 改 `fork()+execl("/sbin/reboot", …)`）。构建脚本 `polaris-adbd-build.sh` 一键完成（含浅克隆/代理回退/断点防半成品）。
2. **gadget**：把 `ffs.adb` function 加进现有 `g1` 的 `configs/c.1`（与 `ncm.usb0` 并列），挂载 functionfs `/dev/usb-ffs/adb`，启动 adbd（其 usb_ffs 线程会立即向 ep0 写入 USB 描述符），再绑定 UDC。
3. **运行方式（2026-10-01 升级：打包 + systemd 开机自启）**：固化为 pmaports 包 `adbd-polaris-1-r3`
   （`pmaports-console/device/testing/adbd-polaris/`，由 `device-xiaomi-polaris-7-r9` 挂依赖进镜像），
   systemd 单元 `polaris-adbd.service` 开机自启。脚本内含网络看门狗（UDC 掉线 6 秒内强制重绑，
   ffs 绑不上自动剔除只恢复 NCM）+ adbd 守护循环，任何失败都不会把设备锁死。
   日志 `journalctl -u polaris-adbd`。**旧的 `/tmp` + `systemd-run` 手动方式已废弃**
   （重启即失），详见 `polaris-adbd-README.md`。

验证结果（含开机自启，全部真机实测）：
```bash
$ adb devices
postmarketOS    host
$ adb shell uname -a
Linux xiaomi-polaris 7.1.0-rc1-sdm845 ... aarch64 GNU/Linux
# 重启后无需任何人工干预：service active/enabled、adb devices 自动重新出现
```
`ALLOW_ADBD_NO_AUTH` + 非 Android property stub → 运行时无需授权，`adb` 直连。

**`reboot bootloader` 整合（实测 10 秒进 fastboot，无需 wrapper）**：
`sudo reboot bootloader`、`adb reboot bootloader`、`adb shell reboot bootloader`
三种写法开箱即用；长命令 `systemctl reboot --reboot-argument=bootloader` 同样有效。
唯一不行的是 `systemctl reboot bootloader`（直接用 systemctl 名报 `Too many arguments`）——
systemd 261 只在 `reboot` 调用名（`/sbin/reboot` 软链）下把位置参数当 reboot argument。

## 二、从零复现（逐条执行）

### 0. 前置（版本锁定）

本仓库的验证环境如下。**版本不同会导致补丁 hunk 冲突或构建结果差异**，建议先对齐。

| 项目 | 值 |
|---|---|
| pmbootstrap | 3.11.1 |
| pmaports 分支 | `v26.06` |
| pmaports commit | `368093c7a882637ee00d32932fb0dafd24cfc4d4` |
| postmarketOS | v26.06（aarch64） |

```bash
export PATH="$HOME/.local/bin:$PATH"
pmbootstrap --version                      # 3.11.1

# 锁定 pmaports 版本（建议）
cd ~/.local/var/pmbootstrap/cache_git/pmaports
git checkout 368093c7a882637ee00d32932fb0dafd24cfc4d4

# 代理：内核源码来自 gitlab.com、上游包索引也常需要。
# 按自己环境改成可用地址，或 export 后用 build.sh。
export PROXY=http://127.0.0.1:7890         # 例：本地 clash/v2ray 端口
```

### 1. 初始化（只需一次）
```bash
pmbootstrap init
# vendor: xiaomi / device: polaris / UI: phosh / systemd: yes
```

### 2. 应用补丁（一步到位）

`pmaports-xiaomi-polaris.patch` 已包含**全部 28 个文件变更**：4 个 APKBUILD / 文件列表的修改 + 17 个内核补丁 + 6 个 firmware 包文件（3 个 service、preset、pa、文件列表）+ 2 个 device 包的 user-dirs 配置。
另有 1 个二进制固件不在 diff 内，需自行准备（见下）。

```bash
cd ~/.local/var/pmbootstrap/cache_git/pmaports
git apply /path/to/pmos-polaris-fixes/pmaports-xiaomi-polaris.patch
git status --short
```

#### 二进制固件 `wlanmdsp-01387.mbn`（需自备）

`firmware-xiaomi-polaris` 包在 `source=` 里引用一个专有固件。本仓库不再分发它，必须自备，否则 `checksum` / 构建会以 sha512 不匹配而失败。

| 项 | 值 |
|---|---|
| 文件名 | `wlanmdsp-01387.mbn` |
| 放置位置 | `device/testing/firmware-xiaomi-polaris/` |
| 大小 | 3,725,044 字节 |
| sha512 | `15538bfe95a00979c7cf23fe9f014afd31f9b82224e3057cebe46fb50863ce3cb7b4bc7359acd55cd40385352452e78c4a761cb2ba15f9ee6078778a6c7a0b64` |

它是 **WCN3990 WiFi 固件**（装到 `lib/firmware/ath10k/WCN3990/hw1.0/wlanmdsp.mbn`）的较新版本，取自小米 ROM 版本号含 `01387` 的固件。上游 `firmware-xiaomi-polaris`（commit `d88ffb2`，即本仓库 pin 的版本）只带旧版 `wlanmdsp.mbn`（3,645,892 字节，sha512 `ca4701b96ca155512b029d6b7e995f2607f2f9672229a9e0de688426358d04ed827fd45c9e8bcec2b08307c9db8bee24c48285d1c0d283463bb6a828e7d02eb8`），两者不同。

获取途径（任选其一）：
1. **从原厂 ROM 提取（推荐）**：下载小米 MIX 2S 版本号含 `01387` 的原厂 fastboot ROM，解包后在 vendor / 固件分区镜像里找到 WCN3990 的 `wlanmdsp.mbn`（可用 `payload-dumper-go`、`imgextractor`，或直接在 Linux 上挂载 `vendor.img`），重命名并核对上表 sha512。
2. **从其它 WCN3990 机型取**：sha512 与上表一致即与本机完全相同；版本不一致通常也能工作，但行为可能与本机有差异。

> **拿不到也没关系（不影响主要功能）**：本机诊断记录显示，5GHz 满速的决定性修复是那 3 个内核补丁（`polaris-wifi-vht-cap-80` / `-highest-780` / `-host-cap-skip-quirk`），此固件只是同期加入的**版本更新**。要跳过它，改两处即可：
> - `device/testing/firmware-xiaomi-polaris/APKBUILD`：删掉 `source=` 中的 `wlanmdsp-01387.mbn`，并删掉 `package()` 中对应的 `install -Dm644 "$srcdir/wlanmdsp-01387.mbn" ...` 那一行
> - 重新执行 `pmbootstrap checksum firmware-xiaomi-polaris`（`sha512sums` 会自动重算）

> **推荐用一键脚本**，等价于「打补丁 + checksum + 构建三个包」（二进制固件需按上表自备）：
> ```bash
> PROXY=http://127.0.0.1:7890 ./build.sh                 # 只构建
> DO_INSTALL=1 PROXY=... ./build.sh                      # 再生成镜像
> DO_FLASH=1   DO_INSTALL=1 PROXY=... ./build.sh         # 再刷进手机
> ```
>
> 下面第 3 / 3.5 / 3.6 节的内核补丁与 firmware 文件**都已包含在上述补丁里**，这几节保留作为根因与排查记录，无需再手动执行。

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
# 内核源码工作区（sdm845-mainline）里改 dts + imx363.c
# （本仓库 polaris-camera.patch 即由此工作区生成）
cd /tmp/linux
git diff arch/arm64/boot/dts/qcom/sdm845-xiaomi-polaris.dts \
         drivers/media/i2c/imx363.c > /tmp/polaris-camera.patch
cp /tmp/polaris-camera.patch \
  ~/.local/var/pmbootstrap/cache_git/pmaports/device/community/linux-postmarketos-qcom-sdm845/
# APKBUILD source= 列表追加一行（在 polaris-slim-ngd-msgdbg2.patch 之后）
#     polaris-camera.patch
# 构建必须带代理，否则 Update package index 卡 0%
export http_proxy="$PROXY" https_proxy="$PROXY"
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

### 3.7 ADB（adbd，纯用户态，无内核补丁）
```bash
# ① 宿主机交叉编译 adbd（Debian：apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make perl curl git）
./polaris-adbd-build.sh                        # 产出 adbd-build/adbd-linux/adb/adbd（aarch64 静态）
#    openssl 源官方卡死会自动切 gh-proxy 镜像；需要代理时 export http(s)_proxy=...

# ② 主路径：打进 console 刷机包（开机自启，见 ~/pmos-polaris-flash-console）
cp adbd-build/adbd-linux/adb/adbd  ~/pmaports-console/device/testing/adbd-polaris/adbd
aarch64-linux-gnu-strip --strip-all ~/pmaports-console/device/testing/adbd-polaris/adbd
#    源码有改动时同步 polaris-adbd-setup.sh / polaris-adbd.service 后：
pmbootstrap -c ~/.config/pmbootstrap_console.cfg checksum adbd-polaris
pmbootstrap -c ~/.config/pmbootstrap_console.cfg build adbd-polaris --arch aarch64
pmbootstrap -y -c ~/.config/pmbootstrap_console.cfg install --password password
#    产物镜像：~/pmos-polaris-flash-console/images/（刷入即带 adbd）

# ③ 调试路径：手动装到正在跑的系统（= 包内同款文件与 service）
sshpass -p password scp adbd-build/adbd-linux/adb/adbd user@172.16.42.1:/tmp/adbd-pkg
sshpass -p password scp polaris-adbd-setup.sh           user@172.16.42.1:/tmp/
sshpass -p password scp <pmaports>/polaris-adbd.service user@172.16.42.1:/tmp/
sshpass -p password ssh user@172.16.42.1 '
  sudo install -m755 /tmp/adbd-pkg /usr/bin/adbd &&
  sudo install -m755 /tmp/polaris-adbd-setup.sh /usr/sbin/polaris-adbd-setup &&
  sudo install -m644 /tmp/polaris-adbd.service /usr/lib/systemd/system/ &&
  sudo systemctl daemon-reload && sudo systemctl enable --now polaris-adbd'
#    日志：journalctl -u polaris-adbd（关注 SETUP_OK / ADBD_UP / WD / GUARDIAN）
#    勿再用 systemd-run + /tmp 的旧方式：重启即失

# ④ 宿主机验证
adb devices && adb shell uname -a              # 期望：postmarketOS 设备 + 内核信息
adb reboot bootloader                          # 10 秒进 fastboot（本次修复后可用）

# 卸载/停止
ssh user@172.16.42.1 'sudo systemctl disable --now polaris-adbd'
```
> 内核要求仅一条：`CONFIG_USB_CONFIGFS_F_FS=y`（pmOS 内核默认已开，`zcat /proc/config.gz | grep F_FS` 可查）。

### 4. 构建（其余）
```bash
pmbootstrap checksum firmware-xiaomi-polaris
pmbootstrap build --force firmware-xiaomi-polaris           # 很快
```

### 5. 安装与刷机
```bash
# 中文界面靠这条（写 /etc/locale.conf；默认文件夹名保持英文由 device 包的 skel 配置保证）
pmbootstrap config locale zh_CN.UTF-8

pmbootstrap install --password password
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
ls /sys/bus/i2c/devices/16-001a/driver 2>/dev/null         # 期望：指向 imx363（注意是 0x1a）
sudo dmesg | grep -i imx363                                # 期望：probe 成功、"4 lanes"
ls /dev/video* | wc -l                                     # camss 绑定后 9 个节点
sudo dmesg | grep -iE "Failed to start media pipeline"     # 期望：无输出
# libcamera 出图（用户实际路径，重启后勿先手动 media-ctl 改格式）
export XDG_RUNTIME_DIR=/run/user/$(id -u user)
cam --list                                                 # 期望：列出 IMX363 相机
cam -c1 --capture=12 --file=/tmp/cam_check.raw             # 期望：12 帧全成功、~30fps
ls -l /tmp/cam_check.raw                                   # 期望：N × 48771072 字节（4024x3024 ABGR8888）
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
| camss `Unsupported bus type 2` | endpoint 缺 `data-lanes`，bus_type 解析失败 | 补 `data-lanes = <0 1 2 3>` + `clock-lanes = <7>` |
| imx363 probe `-6`（CCI NACK） | I2C 地址写错（沿用 beryllium 的 0x10），实际是 **0x1a** | dts 改 `reg = <0x1a>` |
| imx363 probe `-110`（CCI timeout） | 传感器无供电（CAM_VIO 缺失）→ 模块静默不应答 | 新增 `cam_vio_rear`（tlmm21 控制 1.8V，vin=s4） |
| 管线 probe 成功但 `cam` 0 帧 / `Failed to start media pipeline: -32` | 手动 `media-ctl -V` 改了链路 mbus 格式，与 libcamera 期望状态冲突（相邻 pad 不一致 → `-EPIPE`） | 别手动改格式；`modprobe -r imx363 && modprobe imx363` 或在干净状态直接用 `cam -c1 --capture=N` |
| `media-ctl -V ... Invalid argument (22)` | 实体名未加引号（含空格的名字更必须加） | 写 `-V '"imx363 16-001a":0 [fmt:...]'`；且一条失败会中止后续所有 `-V`，改为逐条设 |
| `no soundcards found` / `/dev/snd/` 只有 timer | polaris DTS 缺音频节点（上游补丁不含音频），驱动无设备可 probe | 移植 `&sound` + WCD9340 + tas2559 节点（抄 beryllium） |
| GUI 显示 Dummy Output / 无声 | WirePlumber 启动早于声卡注册，没枚举到 ALSA 卡 0 | PA 启动时 `module-alsa-sink` 显式加载 hw:0,0 为默认 sink |
| 播放走 MM1 异常 | MM1 DAI 怪异行为 | 输出改 MM3（hw:0,2）、输入 MM2（hw:0,1） |
| 开机路由不自动生效 | apk 升级时 systemd preset 删掉包内 symlink（is-enabled=disabled） | 用 `50-polaris.preset`（preset 机制重建 symlink） |
| 音频无声音但驱动 probe 正常 | ADSP 固件路径不匹配（缺 `qcom/sdm845/adsp.mbn`） | 固件路径补丁补 adsp |
| 5GHz 连不上（reason 18 / 弹密码错） | VHT cap 报 0x738139fa（80+80 + EXT-NSS=01 非法组合）被路由 qcawifi 拒 | `polaris-wifi-vht-cap-80.patch` 清位 → 0x3381f9b2 |
| 能连 5G 但只有 144.4Mbps（n 模式） | RX/TX Highest = 0，VHT 协商失败（小米 15 是 780） | `polaris-wifi-vht-highest-780.patch` 设 Highest=780 |
| 内核补丁编译了但设备行为没变 | `flash_kernel` 只刷 boot 分区，rootfs 里 `/usr/lib/modules/` 的模块是旧的 | 升级内核 apk（`apk add --force-overwrite`）让模块也更新 |
| 7.1-rc1 编译报宏未定义 | `vht_cap_info` 改名 `cap`、`IEEE80211_VHT_CAP_*` 宏移除 | 用裸 hex（0xc0000000 / 0x8）+ 新字段名 |
| SSH 一断 adbd/gadget 全没了，USB 网络锁死只能重启 | pmOS 用 systemd，会话断开时回收整个 session cgroup，挂在会话下的 adbd/脚本被一起杀 → adbd 死 → functionfs 关闭 → gadget 从宿主机消失 | 用 system 单元托管（`polaris-adbd.service`，跑在 system manager cgroup，不受会话影响）+ 网络看门狗兜底 |
| configfs 里 `ln -s functions/ffs.adb configs/c.1/` 失败（ENOENT） | ①UDC 绑定期间禁止创建函数 symlink；②configfs symlink 目标**相对 cwd 解析**，在家目录执行必然失败 | 先 `echo "" > UDC` 解绑，`cd configs/c.1` 后再 ln，最后重新 bind |
| `adb devices` 空、宿主机只有 NCM 接口（bInterfaceClass 02/0a） | ffs symlink 没进 `configs/c.1`（绑定期 ln 失败），枚举里根本没有 adb 接口（缺 class ff） | 看 `journalctl -u polaris-adbd` 的 `LN_RC`；按上一行修好后重跑 |
| adbd 崩溃后宿主机 adb 掉线 | ffs ep0 关闭导致 function 失效 | 脚本守护循环自动重启 adbd 并重绑 UDC |
| 包装了但 `polaris-adbd.service` 不自启 | systemd preset 只对**新安装的 unit** 生效，出厂 `99-default.preset` 是 `disable *`，首次安装时把 apk 刚放进 wants 的软链删了 | 包内自带 `55-adbd-polaris.preset` 写 `enable polaris-adbd.service`（preset 首个匹配生效），与 firmware 包 `50-polaris.preset` 同款 |
| 旧部署方式（`/tmp/adbd` + `systemd-run`）重启后静默失效 | `/tmp` 重启即清、transient unit 重启即失，脚本文件没了 unit 启动即退出且 `--collect` 自动清理，连日志都看不到 | 升级为 pmaports 包：`/usr/bin/adbd` + `/usr/sbin/polaris-adbd-setup` + 常驻 systemd 单元 |
| `adb reboot` 命令返回成功但设备不动 | adbd 的 reboot 服务调 `property_set("sys.powerctl",…)`，`ADB_NON_ANDROID` 构建里它是直接 `return 0` 的空桩，服务端还 `pause()` 干等 | `adbd-linux.patch` 改为 `fork()+execl("/sbin/reboot", "reboot", <reason>)`，失败回退 `systemctl reboot --reboot-argument`（`adbd-polaris-1-r3`） |
| `systemctl reboot bootloader` 报 `Too many arguments` | systemd 261 只在 `reboot` 调用名（`/sbin/reboot` 软链）下把位置参数当 reboot argument，`systemctl` 名下不接受 | 用 `reboot bootloader`（三种写法均实测 10 秒进 fastboot），或长命令 `systemctl reboot --reboot-argument=bootloader` |

## 四、摄像头结论与遗留问题

**已修复**（补丁 `polaris-camera.patch`，2026-09-29 实测）：
- 三个根因：I2C 地址 0x10→**0x1a**、**CAM_VIO 缺失**（tlmm21 控制 1.8V）、lane 数不全（补成 **4-lane** + camss `vdda-*` 供电）。
- `imx363 16-001a` probe 成功，`pixel_rate: 508800000`、`4 lanes`；media 链路 `imx363 → msm_csiphy0 → msm_csid0 → msm_vfe0_rdi0`。
- **v4l2 直采**：`v4l2-ctl --stream-mmap --stream-count=1` 得 15,240,960 字节（1 帧 pRAA SRGGB10P），解码后为真实场景（欠焦光斑，10-bit mean≈390/1023）。
- **libcamera（用户实际路径）**：重启后不做任何手动配置，`cam -c1 --capture=12 --file=/tmp/x.raw` 12 帧全成功、稳定 ~30fps，输出 ABGR8888 4024x3024（每帧 48,771,072 字节）。

**已知遗留（不影响出图）**：
- libcamera 软件 ISP（无硬件 ISP 参与）输出偏暗，需自动曝光/后处理；日志有 `eglCreateImageKHR fail → fallback to upload`（仅警告）。
- 缺 imx363 静态属性 / IPA 调参文件（仅 WARN）。
- 首帧后偶有不来帧，重试即可；根因未定（怀疑与手动 media-ctl 残留状态有关，重启后消失）。
- 副摄（IMX376）/前摄未启用。

**已排除的错误假设**（勿再走回头路）：
- ~~i2c 地址 0x10~~（beryllium 是 0x10，polaris 是 0x1a）。
- ~~vif = pm8998_lvs1~~（polaris 是 tlmm21 控制的独立 1.8V 稳压器）。
- ~~tlmm 102（CUSTOM0）是缺失的使能信号~~（未配置也能出图）。
- ~~2-lane~~（必须 4-lane）。

除副摄/前摄外，本仓库涉及的功能已全部验收通过（见顶部"验收状态"）。
