#!/usr/bin/env bash
# ============================================================
#  一键构建 xiaomi-polaris（小米 MIX 2S）postmarketOS 镜像
#  本仓库 README「二、从零复现」的脚本化版本
#
#  用法：
#    ./build.sh                              打补丁 + 构建三个包
#    WITH_CAMERA=1 ./build.sh                带摄像头（IMX363 主摄；默认跟随 patch 基线 = 关）
#    DO_INSTALL=1 ./build.sh                 额外生成 rootfs 镜像
#    DO_FLASH=1   ./build.sh                 再刷进手机（需先进 fastboot）
#    PROXY=http://127.0.0.1:7890 ./build.sh  指定代理
#
#  前置：先执行过 pmbootstrap init
#        （vendor: xiaomi / device: polaris / UI: phosh / systemd: yes）
#
#  验证环境：pmbootstrap 3.11.1 · pmaports v26.06 @ 368093c7
# ============================================================
set -euo pipefail

# pmbootstrap 检测到 CI=true 时会给每条命令加 900 秒无输出超时，
# 长构建（appstream 下载、内核）容易被误杀 —— 非交互环境一律关掉。
unset CI || true

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PMAPORTS="${PMAPORTS:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}"
PMBOOTSTRAP="${PMBOOTSTRAP:-pmbootstrap}"
PROXY="${PROXY:-}"
PINNED_COMMIT="368093c7a882637ee00d32932fb0dafd24cfc4d4"

PATCH="$HERE/pmaports-xiaomi-polaris.patch"
LINUX_PKG="linux-postmarketos-qcom-sdm845"
FW_PKG="firmware-xiaomi-polaris"
DEV_PKG="device-xiaomi-polaris"
FW_DIR="$PMAPORTS/device/testing/$FW_PKG"

info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. 环境检查 ----------
command -v "$PMBOOTSTRAP" >/dev/null 2>&1 || die "找不到 pmbootstrap，请先安装并执行 pmbootstrap init"
[ -d "$PMAPORTS" ] || die "找不到 pmaports 检出目录：$PMAPORTS（请先执行 pmbootstrap init）"
[ -f "$PATCH" ]    || die "缺少补丁：$PATCH"

if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
    info "使用代理：$PROXY"
else
    warn "未设置 PROXY，若下载内核源码/包索引卡住，请用 PROXY=... 重跑"
fi

CUR="$(git -C "$PMAPORTS" rev-parse HEAD)"
if [ "$CUR" = "$PINNED_COMMIT" ]; then
    info "pmaports 版本匹配：$CUR"
else
    warn "pmaports 当前版本：$CUR"
    warn "本仓库验证版本：$PINNED_COMMIT（v26.06 分支）"
    warn "版本不同可能导致补丁 hunk 冲突或结果差异"
fi

# ---------- 1. 应用补丁 ----------
if git -C "$PMAPORTS" apply --check "$PATCH" 2>/dev/null; then
    info "应用补丁 pmaports-xiaomi-polaris.patch"
    git -C "$PMAPORTS" apply "$PATCH"
elif git -C "$PMAPORTS" apply --check -R "$PATCH" 2>/dev/null; then
    info "补丁已应用过，跳过"
elif [ -f "$FW_DIR/Polaris-HiFi.conf" ]; then
    # 1.5 摄像头开关调整过 source=（或文件增删）后，-R 精确校验不再通过；
    # 以 firmware 包的标志性新增文件判断补丁已应用，继续即可。
    info "补丁已应用过（摄像头开关已调整），跳过 apply"
else
    die "补丁无法应用（与上游冲突）。请按 README「二、从零复现」手动处理"
fi

# ---------- 1.5 摄像头开关（显式 WITH_CAMERA=0/1 才动树，默认完全跳过） ----------
# build.sh 是最终构建产物，不应影响更新过程：不设置 WITH_CAMERA 时本块
# 一个字符都不改（树保持 patch 基线或上次显式切换的状态）。两个方向幂等：
#   WITH_CAMERA=0  只从 source= 摘 camera 补丁 + 挂 camera-disabled（补丁文件保留）
#   WITH_CAMERA=1  只从 source= 摘 camera-disabled + 挂 polaris-camera.patch（IMX363 主摄）
if [ -n "${WITH_CAMERA:-}" ]; then
KDIR="$PMAPORTS/device/community/linux-postmarketos-qcom-sdm845"
if [ "$WITH_CAMERA" = 0 ]; then
    if [ -f "$KDIR/polaris-camera.patch" ] || grep -q '^[[:space:]]*polaris-camera\.patch$' "$KDIR/APKBUILD" 2>/dev/null; then
        info "WITH_CAMERA=0: 从 source= 移除 polaris-camera.patch（摄像头关闭；文件保留为启用素材）"
        sed -i '/^[[:space:]]*polaris-camera\.patch[[:space:]]*$/d' "$KDIR/APKBUILD"
    fi
    if [ -f "$HERE/polaris-camera-disabled.patch" ]; then
        if ! grep -q '^[[:space:]]*polaris-camera-disabled\.patch$' "$KDIR/APKBUILD" 2>/dev/null; then
            cp "$HERE/polaris-camera-disabled.patch" "$KDIR/"
            # 插到 polaris-firmware-path.patch 之后（audio 补丁接在其 EOF 上，顺序要保持）
            sed -i 's|^\([[:space:]]*\)polaris-firmware-path\.patch$|\1polaris-firmware-path.patch\n\1polaris-camera-disabled.patch|' "$KDIR/APKBUILD"
        fi
    else
        warn "缺少 $HERE/polaris-camera-disabled.patch，仅移除 camera 补丁（设备树不显式关闭）"
    fi
else
    KDIR="$PMAPORTS/device/community/linux-postmarketos-qcom-sdm845"
    if grep -q '^[[:space:]]*polaris-camera-disabled\.patch$' "$KDIR/APKBUILD" 2>/dev/null; then
        info "WITH_CAMERA=1: 从 source= 移除 polaris-camera-disabled.patch（文件保留）"
        sed -i '/^[[:space:]]*polaris-camera-disabled\.patch[[:space:]]*$/d' "$KDIR/APKBUILD"
    fi
    if [ -f "$HERE/polaris-camera.patch" ] && ! grep -q '^[[:space:]]*polaris-camera\.patch$' "$KDIR/APKBUILD" 2>/dev/null; then
        info "WITH_CAMERA=1: 启用 polaris-camera.patch（IMX363 主摄）"
        cp "$HERE/polaris-camera.patch" "$KDIR/"
        # 插到 polaris-firmware-path.patch 之后（与 camera-disabled 原位置一致，
        # audio 补丁的 EOF 上下文依赖此顺序）
        sed -i 's|^\([[:space:]]*\)polaris-firmware-path\.patch$|\1polaris-firmware-path.patch\n\1polaris-camera.patch|' "$KDIR/APKBUILD"
    fi
fi
fi   # WITH_CAMERA 显式设置才走到这里；未设置则整块跳过

# ---------- 2. 本地仓库版本冲突预检 ----------
# 两套 pmaports 树（console 版 / 本仓库版）共用 packages 仓库时，本地已存在
# 的【更高版本】同名包会在索引里压过本仓库刚构建的包（踩过的坑：console 的
# device r10 压住本仓库的 r1、linux r25 压住 r24 → 装进去的是别人的内容）。
# 这里检查三个目标包：本地已有 apk 若比本仓库构建的版本高，直接报错。
PKGDIR="$HOME/.local/var/pmbootstrap/packages/v26.06/aarch64"
if [ -d "$PKGDIR" ]; then
    for p in "$LINUX_PKG" "$FW_PKG" "$DEV_PKG"; do
        apkb="$(find "$PMAPORTS/device" -maxdepth 3 -path "*/$p/APKBUILD" 2>/dev/null | head -1)"
        [ -n "$apkb" ] || continue
        v="$(sed -n 's/^pkgver=//p' "$apkb" | head -1)"
        r="$(sed -n 's/^pkgrel=//p' "$apkb" | head -1)"
        ours="$p-$v-r$r.apk"
        highest="$(ls "$PKGDIR" 2>/dev/null | grep -E "^$p-[0-9]" | sort -V | tail -1)"
        if [ -n "$highest" ] && [ "$highest" != "$ours" ] && \
           [ "$(printf '%s\n%s\n' "$ours" "$highest" | sort -V | tail -1)" = "$highest" ]; then
            die "本地仓库存在更高版本 $highest（本仓库将构建 $ours），会被静默顶替。
     处理（任选）：删除该 apk 后重建；或 bump 本仓库 $p 的 pkgrel；
     或为两套树配置独立 work 目录（pmbootstrap -w/--work 或 cfg 的 work=）"
        fi
    done
    info "本地仓库版本预检通过（无高版本顶替）"
fi

# ---------- 3. 校验 + 构建 ----------
info "checksum 三个包"
for p in "$LINUX_PKG" "$FW_PKG" "$DEV_PKG"; do
    "$PMBOOTSTRAP" checksum "$p"
done

info "构建 $LINUX_PKG（内核，最慢，约 10~30 分钟）"
"$PMBOOTSTRAP" build "$LINUX_PKG" --force

info "构建 $FW_PKG"
"$PMBOOTSTRAP" build "$FW_PKG" --force

info "构建 $DEV_PKG"
"$PMBOOTSTRAP" build "$DEV_PKG" --force

info "构建完成，产物：~/.local/var/pmbootstrap/packages/v26.06/aarch64/"

# ---------- 4. 可选：生成镜像 ----------
if [ "${DO_INSTALL:-0}" = 1 ]; then
    # 中文界面靠这条（写 /etc/locale.conf；默认目录名保持英文靠 device 包里的
    # /etc/skel/.config/user-dirs.conf enabled=False）
    info "设置系统语言为 zh_CN.UTF-8"
    "$PMBOOTSTRAP" config locale zh_CN.UTF-8

    info "生成 rootfs 镜像"
    "$PMBOOTSTRAP" install --password "${PASSWORD:-password}"

    info "镜像已生成，刷机（需手机先进入 fastboot）："
    echo "    $PMBOOTSTRAP flasher flash_kernel"
    echo "    $PMBOOTSTRAP flasher flash_rootfs --partition userdata"
fi

# ---------- 5. 可选：直接刷机 ----------
if [ "${DO_FLASH:-0}" = 1 ]; then
    info "刷入 boot（内核 + 设备树）"
    "$PMBOOTSTRAP" flasher flash_kernel
    info "刷入 rootfs -> userdata（会清空手机数据）"
    "$PMBOOTSTRAP" flasher flash_rootfs --partition userdata
fi

info "全部完成"