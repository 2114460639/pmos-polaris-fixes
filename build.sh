#!/usr/bin/env bash
# ============================================================
#  一键构建 xiaomi-polaris（小米 MIX 2S）postmarketOS 镜像
#  本仓库 README「二、从零复现」的脚本化版本
#
#  用法：
#    ./build.sh                              打补丁 + 构建三个包
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
else
    die "补丁无法应用（与上游冲突）。请按 README「二、从零复现」手动处理"
fi

# ---------- 2. 检查二进制固件 ----------
# wlanmdsp-01387.mbn（WCN3990 WiFi 固件，取自小米 ROM 01387）属专有二进制，
# 本仓库不再分发，需自行获取（方法见 README「二、2」）。
FW_BLOB="$FW_DIR/wlanmdsp-01387.mbn"
if [ -f "$FW_BLOB" ]; then
    info "固件已就位：$FW_BLOB"
else
    warn "缺少 $FW_BLOB"
    warn "获取方法见 README「二、2」；若拿不到，可从 firmware APKBUILD 删掉该 source 与 install 行"
    warn "（5GHz 的决定性修复是 3 个内核补丁，此固件只是版本更新）"
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