# Xiaomi Mi MIX 2S (polaris) — postmarketOS 补丁提交说明（精简基线）

> 本文档是 `pmos-polaris-fixes` 仓库的**提交说明**，反映 2026-10-03 补丁精简后的最终基线。
> 完整排查历史（看门狗速率测定、WiFi 三设备关联对比、音频四层演进、亮度取证等约 800 行）
> 保存在 git 历史：`git show 8c17618:README.md`。

- 设备：Xiaomi Mi MIX 2S（DT compatible: `xiaomi,polaris` / `qcom,sdm845`，2018，aarch64，testing）
- 内核：`linux-postmarketos-qcom-sdm845` 7.1-rc1（sdm845-mainline/linux fork）
- 环境：pmbootstrap 3.11.1 · pmaports v26.06 @ `368093c7` · UI phosh · systemd
- 完整补丁：`pmaports-xiaomi-polaris.patch`（**34 个文件变更**，一步 `git apply`，含 adbd 预编译二进制的 git binary patch）
- 一键构建：`PROXY=http://127.0.0.1:7890 ./build.sh`（详见「二、从零复现」）
- 二进制固件不随仓库分发：`wlanmdsp-01387.mbn` 需自备（见「二、2」）

## 〇、基线版本与验收（2026-10-03，r52 全量刷机验收全绿）

| 包 | 版本 |
| --- | --- |
| linux-postmarketos-qcom-sdm845 | **7.1_rc1-r52** |
| device-xiaomi-polaris | **7-r16** |
| firmware-xiaomi-polaris | **1-r17** |
| adbd-polaris | **1-r3** |

验收项：显示/GUI（greetd+phoc）、GPU 固件 dmesg 0 错（单拷贝+相对软链）、WiFi 扫描
（`kconfig debug 0`，精简后无回归）、音频 UCM 默认通路（Speaker/Mic）、电池 99%、
ADB（主机识别 `postmarketOS`）、亮度救援、hang 三件套、zh_CN locale + 英文目录名、
摄像头 disabled（当前变体）、watchdog 10s。**dmesg error 总数与精简前逐条一致（零新增）。**

## 一、功能支持情况（实测）

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| Screen 屏幕 / Touch 触控 | P | ✅ 开机黑屏修复（nt35596s prepare_prev_first），触摸正常 |
| Wifi Wi-Fi | P | ✅ 5GHz 满速 AC 866.7Mbps（VHT cap 0x3381f9b2 + Highest 780，iperf3 ≈650Mbps） |
| Audio 音频 | P | ✅ 无声卡→全自动：DTS 音频节点 + ALSA UCM 一层，GUI 与浏览器 mic/扬声器通过 |
| Battery 电池 | P | ✅ 电量计 DTS 启用，实时电量正常 |
| 3D GPU | Y | ✅ a630_zap 单拷贝 + DT 派生路径相对软链，dmesg 0 错 |
| ADB 调试 | Y | ✅ adbd over USB functionfs（与 NCM 网络共存），开机自启（见 `polaris-adbd-README.md`） |
| Camera 摄像头 | P | IMX363 可出图（`polaris-camera.patch`），**当前基线为关闭变体**（见「二、4」）；遗留：软件 ISP 偏暗、偶有掉帧 |
| Localization 本地化 | — | 界面默认中文 + 文件夹名英文 + font-noto-cjk |
| USB Net / Flashing / FDE | Y | — |
| Calls / GPS / NFC / USB-OTG | —/N | 未测或不适用 |

状态码：**Y** 完全可用 · **P** 部分可用 · **N** 不可用 · **-** 不适用/未测

## 二、从零复现（逐条执行）

### 1. 环境

```bash
pmbootstrap init
# vendor: xiaomi / device: polaris / UI: phosh / systemd: yes
```

### 2. 二进制固件 `wlanmdsp-01387.mbn`（需自备）

`firmware-xiaomi-polaris` 的 `source=` 引用此专有固件，不自备则 checksum/构建失败。

| 项 | 值 |
| --- | --- |
| 文件名 / 位置 | `wlanmdsp-01387.mbn` → `device/testing/firmware-xiaomi-polaris/` |
| 大小 | 3,725,044 字节 |
| sha512 | `15538bfe95a00979c7cf23fe9f014afd31f9b82224e3057cebe46fb50863ce3cb7b4bc7359acd55cd40385352452e78c4a761cb2ba15f9ee6078778a6c7a0b64` |

它是 WCN3990 WiFi 固件的较新版本（取自小米 ROM `01387`）。获取：从 MIX 2S 原厂
fastboot ROM 解包提取（`payload-dumper-go` / 挂载 `vendor.img`），或从其它 WCN3990
机型取（sha512 一致即相同）。

> 拿不到也不影响主要功能（5GHz 决定性修复是 2 个内核补丁）：从 firmware APKBUILD 删
> `source=` 里该行与 `package()` 对应 `install` 行，重跑 `pmbootstrap checksum firmware-xiaomi-polaris`。

### 3. 应用补丁

```bash
# 推荐：一键（= 打补丁 + checksum + 构建三个包）
PROXY=http://127.0.0.1:7890 ./build.sh
DO_INSTALL=1 PROXY=... ./build.sh           # 再生成镜像
DO_INSTALL=1 DO_FLASH=1 PROXY=... ./build.sh # 再刷机（手机先进 fastboot）

# 或手动一步到位：
cd ~/.local/var/pmbootstrap/cache_git/pmaports
git apply /path/to/pmos-polaris-fixes/pmaports-xiaomi-polaris.patch
git status --short
```

### 4. 摄像头开关（WITH_CAMERA，两方向幂等、默认跟随 patch 基线）

当前 patch 基线 = **设备树关闭摄像头**（`source=` 挂 `polaris-camera-disabled.patch`）。

```bash
WITH_CAMERA=1 ./build.sh   # 启用 IMX363 主摄（摘 disabled、挂 polaris-camera.patch）
WITH_CAMERA=0 ./build.sh   # 关闭摄像头（显式，与基线一致）
./build.sh                 # 不设置 = 完全不动摄像头相关 source
```

切换只改 `source=` 行（补丁文件双向保留为素材），终态可过 `git apply --check -R` 树=patch 校验。

### 5. 构建 / 镜像 / 刷机

- 构建产物：`~/.local/var/pmbootstrap/packages/v26.06/aarch64/`
- `DO_INSTALL=1`：先 `pmbootstrap config locale zh_CN.UTF-8`，再 `pmbootstrap install --password password`
- 刷机：`./flash.sh`（刷 boot + userdata，**清空数据**；手机先物理进 fastboot：关机后音量下+电源）
- 重刷后清 host key：`ssh-keygen -R 172.16.42.1`；SSH：`sshpass -p password ssh user@172.16.42.1`

> **坑**：`pmbootstrap flasher flash_kernel` 只刷 boot，内核模块在 rootfs
> `/usr/lib/modules/` —— 升级内核必须重出镜像或 `apk add --force-overwrite`。

## 三、补丁提交说明（2026-10-03 精简）

### 3.1 变更摘要

- 内核 `source=` **13 → 10 个补丁**：合并 3 组同文件/强依赖补丁，消除跨补丁上下文耦合
- kernel config **关闭 5 个调试开关**（ATH10K_DEBUG 等），真机 `kconfig debug 1 → 0`
- 删除孤儿调试补丁、已合并的旧补丁、废弃用户态文件与 adbd 构建工具链
- `build.sh`：补 `WITH_CAMERA=1` 启用块（原只有摘除方向）、grep 支持 tab 缩进、
  补丁状态三分支检测（开关调整后不再误报冲突）、默认不设 `WITH_CAMERA` 不动树
- canonical patch 重导出（34 文件，独立克隆 `git apply --check` PASS）

### 3.2 精简后内核补丁集（`source=` 10 个 + camera 素材 1 个）

| 补丁 | 作用 |
| --- | --- |
| `nt35596s-prepare-prev-first.patch` | 显示：panel `prepare_prev_first = true`，修开机黑屏（DCS Init -22） |
| `polaris-battery-fg.patch` | DTS 启用 pmi8998_charger/fg + monitored-battery，修电量恒 0% |
| `polaris-wifi-vht.patch` | **[合并]** ath10k mac.c：VHT cap 清非法位→0x3381f9b2（修 reason 18 拒连）+ RX/TX Highest=780（修 144Mbps 回退） |
| `polaris-wifi-host-cap-skip-quirk.patch` | DTS `qcom,snoc-host-cap-skip-quirk`，跳过 host capability QMI（否则 WiFi 初始化中止） |
| `polaris-firmware-path.patch` | DTS 固件路径对齐实际布局（cdsp/ipa/mss/venus/bt/zap） |
| `polaris-camera-disabled.patch` | DTS 显式关闭 &camss/&cci（当前基线变体，`WITH_CAMERA=0`） |
| `polaris-audio.patch` | DTS 音频：&sound（db845c 兼容）+ WCD9340 + TAS2559/60 + adsp 固件 |
| `polaris-slim-chmap.patch` | ASoC `snd_soc_dai_set_channel_map`，ADSP 不再拒 SET_PARAM（num_channels） |
| `polaris-q6afe-ealready.patch` | **[合并]** q6afe 错误码透传 `-result->status`（前置）+ DAI `ADSP_EALREADY` 视为已启动 |
| `polaris-slim-ngd-defactchan.patch` | **[合并]** DEF_ACT_CHAN 超时降级继续 + wbuf 编码 `data_fmt` |
| （素材）`polaris-camera.patch` | IMX363 主摄 DTS，不进默认 source，`WITH_CAMERA=1` 时挂入 |

### 3.3 合并详情与等价性验证

| 组 | 原补丁 | 合并理由 |
| --- | --- | --- |
| wifi-vht | `vht-highest-780` + `vht-cap-80` | 改同一文件同一位置（mac.c 5031/5033），后者的上下文行含前者的新增行 —— 正是历史踩坑（改一处必须同步另一处）的耦合源 |
| q6afe | `q6afe-errno` + `q6afe-dai-ealready` | errno 透传是 EALREADY 检测的**硬依赖**：不透传则上层永远收 -EINVAL，`rc == -ADSP_EALREADY` 分支永不触发 |
| slim-ngd | `defactchan` + `defactchan-enc` | 同一文件（qcom-ngd-ctrl.c）两处改动（1020/1059 行） |

验证方法：从内核 tarball 提取干净文件 → 按原顺序 apply 旧补丁组 → `diff` 生成合并补丁 →
新链 apply 后与旧链**逐字节 `cmp` IDENTICAL**（4 个文件全过）→ 干净树全链 dry-run 通过。

### 3.4 kernel config 关闭的 5 个调试开关

| 开关 | 关闭原因 |
| --- | --- |
| `CONFIG_ATH10K_DEBUG` | WiFi 驱动编译期调试分支，真机 `kconfig debug 1 → 0` 实测生效 |
| `CONFIG_FW_LOADER_DEBUG` | 固件加载器冗余调试输出（固件链已稳定 0 错） |
| `CONFIG_CIFS_DEBUG` | CIFS 调试日志（设备不使用 CIFS） |
| `CONFIG_PNP_DEBUG_MESSAGES` | PNP 调试消息（arm64 DT 平台无 PNP） |
| `CONFIG_ACPI_DEBUG` | ACPI 调试消息（设备走设备树） |

保留 `DYNAMIC_DEBUG`、`DEBUG_FS`（按需开关、零常开开销）。

### 3.5 删除的文件

- **pmaports 树**：孤儿调试补丁 `polaris-watchdog-bark` / `polaris-ramoops` /
  `a6xx-recover-force-gmu-off`；被合并的 5 个旧补丁；4 个音频诊断探针
  （`soc-pcm-debug`、`slim-ngd-rxdebug/tiddebug/msgdbg2`，2026-10-01 已出 source）
- **本仓库**：旧四层音频文件（`50-polaris.preset`、`polaris-pulse-*.pa/service`、
  `polaris-*-routing.service`）、被合并的旧补丁副本与调试探针（共 15 个）、
  `30-gpu-firmware.files`、adbd 构建工具链（`polaris-adbd-build.sh`、`adbd-linux.patch`、
  `polaris-adbd-setup.sh` 根副本、`adbd-build/`）—— 均可从 git 历史取回

## 四、各功能修复速览（根因 → 修法）

- **显示**：`nt35596s_panel_add()` 在 DSI 上电前发 DCS → `prepare_prev_first = true`（2 行）
- **GPU**：DT 拼出 `qcom/sdm845/Xiaomi/polaris/a630_zap.mbn` 与实际布局不符 →
  firmware 包**单拷贝**装 `polaris/` + `Xiaomi/polaris/` 建**相对软链**（mkinitfs 保留软链，
  initramfs 实测 40+ 软链，固件加载器走 VFS 解析）
- **WiFi**：三阶段（host cap QMI 拒绝→quirk；VHT cap 非法组合被路由拒→清位 0x3381f9b2；
  Highest=0 只协商到 n→设 780）+ `wlanmdsp-01387` 版本更新
- **音频**：上游 polaris 无音频 DTS → `polaris-audio.patch` 补节点；用户态从「四层兜底」
  精简为**一条 ALSA UCM**（`polaris-ucm-card.conf` + `Polaris-HiFi.conf`，PA
  `module-alsa-card` 本就 `use_ucm=yes`，配置就位即接管）。UCM 坑：mic 增益控件必须
  `name='ADC1 Volume'`（裸 `ADC1` 报 ENOENT）；Syntax 4 verb 至少一个 `SectionDevice`
- **电池**：DTS 未覆盖 pmi8998 节点（dtsi 默认 disabled）→ 显式 okay + simple-battery 引用
- **亮度救援**：systemd-backlight 恢复历史 1% 亮度 → `polaris-backlight-rescue` 开机抬到 40%
- **稳定性三件套**：sysctl 自动 panic（`panic_on_rcu_stall=1`、`panic_on_oops=1`、
  `kernel.panic=120`）+ PID1 喂硬件看门狗（`RuntimeWatchdogSec=10`）+ 30s CPU 快照日志
- **XDG 目录**：`enabled=False` 的 user-dirs.conf 使目录永不创建 → device 包
  `post-install` **与** `post-upgrade` 双脚本（chroot 复用走升级路径，只写 install 不生效）
- **ADB**：adbd over functionfs 与 NCM 共存，systemd 托管，详见 `polaris-adbd-README.md`

## 五、踩坑速查

| 坑 | 解法 |
| --- | --- |
| `sudo -S` + heredoc 把文件写空（stdin 被当密码吃掉） | `echo pw \| sudo -S -v` 预授权，文件写 /tmp 再 `sudo install` |
| apk `install=` 脚本只写 `.post-install`，chroot 复用走升级路径不执行 | `install="$pkgname.post-install $pkgname.post-upgrade"` 双文件 |
| 两套 pmaports 树共用 packages，高版本 apk 静默顶替 | bump pkgrel 或独立 workdir；`build.sh` 内置版本预检 |
| `CI=true` 令 pmbootstrap 900s 无输出杀命令 | `unset CI`（build.sh 已内置） |
| 补丁上下文耦合：改一个 `+` 行要同步相邻补丁的上下文行 | 同文件改动合并成一个补丁 |
| `pmbootstrap chroot <suffix>` 把后缀当命令（exit 127） | `pmbootstrap chroot -s <suffix> -- cmd` 或 `-r` |
| `pmbootstrap install` 卡在 getpass 交互 | `pmbootstrap install --password <pw>` |
| `dmesg_restrict=1` 时 `dmesg \| grep -c` 空输入假阴性 0 | `sudo dmesg` 重验 |
| `flash_kernel` 只刷 boot，模块留在旧 rootfs | 重出镜像或 `apk add --force-overwrite` |
| MTP/实验把 USB 弄死（adb/fastboot/ssh 全无） | 物理长按电源 → 音量下+电源进 fastboot 重刷 |
| 构建后 buildroot 被 zap，无法离线验证补丁 | 从 `cache_distfiles` 的 tarball 提取目标文件 dry-run |
| keep-loop/旧路由 service 污染音频真机测试 | `systemctl stop` 后再测 |

## 六、本仓库文件索引

| 文件 | 用途 |
| --- | --- |
| `pmaports-xiaomi-polaris.patch` | 34 文件完整补丁（唯一权威，一步 `git apply`） |
| `build.sh` | 一键构建（最终交付物：打补丁 + checksum + 构建 + 可选出镜像/刷机） |
| `*.patch`（11 个） | 补丁分发副本，与 canonical patch 内内容逐字节一致，供单独查看/引用 |
| `polaris-adbd-README.md` | ADB（adbd）方案专文档（部署、验证、五个关键坑） |
| `.gitignore` | 忽略 `adbd-build/`、`adbd-bin/` 构建残留 |

> 本仓库不含二进制固件；`wlanmdsp-01387.mbn` 见「二、2」。
> 完整历史文档：`git show 8c17618:README.md`。
