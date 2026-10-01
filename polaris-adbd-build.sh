#!/bin/sh
# 宿主机（Debian/Ubuntu）交叉编译 aarch64 静态 adbd，用于 postmarketOS 手机。
# 依赖：sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make perl curl ca-certificates git
# 如需代理：export http_proxy=http://<host>:<port> https_proxy=$http_proxy
#           （git 克隆可用 GIT_CONFIG_* 注入，curl 走上面的环境变量）
#
# 产物：adbd-build/adbd-linux/adb/adbd （ELF aarch64 静态链接，可直接在 musl 的 pmOS 上运行）
set -e

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$PWD/adbd-build}
OPENSSL_VER=3.3.2
PREFIX=$WORK/openssl-aarch64
mkdir -p "$WORK"
cd "$WORK"

# 1. adbd 源码（tonyho/adbd-linux，文章《Linux usb 7. 配置 ADBD》推荐实现）
#    github 偶发 HTTP/2 流中断/代理不可用：强制 HTTP/1.1 并重试，失败可关代理再试
if [ ! -d adbd-linux/.git ]; then
    rm -rf adbd-linux
    cloned=
    for _try in 1 2 3; do
        if git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/tonyho/adbd-linux.git ||
           git -c http.version=HTTP/1.1 -c http.proxy= -c https.proxy= \
               clone --depth 1 https://github.com/tonyho/adbd-linux.git; then
            cloned=1
            break
        fi
        sleep 2
    done
    [ -n "$cloned" ] || { echo "clone adbd-linux failed" >&2; exit 1; }
fi
cd adbd-linux
git checkout -- . 2>/dev/null || true
# 合并补丁：OpenSSL 1.0 -> 1.1+/3.x API、Makefile 静态链接修复、
# 以及 reboot 服务修复（property_set 是空桩，改为 fork+execl /sbin/reboot，
# 见 polaris-adbd-README.md）
git apply "$REPO_DIR/adbd-linux.patch"
cd "$WORK"

# 2. OpenSSL 3 静态库（aarch64）——adbd 上游只兼容 OpenSSL 1.0，补丁已改为 1.1+/3.x API
if [ ! -f "$PREFIX/lib/libcrypto.a" ]; then
    if [ ! -f openssl-$OPENSSL_VER.tar.gz ]; then
        # 先下到 .part 再改名，避免中断的半成品被当成完整包。
        # github releases 直连经常卡死（实测 0 字节超时）：官方失败后自动
        # 切 gh-proxy 镜像（2026-10-01 实测镜像秒下）。
        url_base=https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz
        for url in "$url_base" "https://gh-proxy.com/$url_base"; do
            echo "downloading openssl from $url"
            if curl -fL --http1.1 --connect-timeout 15 --retry 3 --retry-all-errors \
                -o openssl-$OPENSSL_VER.tar.gz.part "$url"; then
                break
            fi
        done
        [ -s openssl-$OPENSSL_VER.tar.gz.part ] || {
            echo "openssl download failed" >&2; exit 1; }
        mv openssl-$OPENSSL_VER.tar.gz.part openssl-$OPENSSL_VER.tar.gz
    fi
    rm -rf openssl-$OPENSSL_VER
    tar xzf openssl-$OPENSSL_VER.tar.gz
    cd openssl-$OPENSSL_VER
    ./Configure linux-aarch64 --cross-compile-prefix=aarch64-linux-gnu- \
        no-shared no-tests no-apps --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
    make -j"$(nproc)" build_libs
    make install_dev
    cd "$WORK"
fi

# 3. libcap 头文件桩：aarch64 交叉环境没有 sys/capability.h，
#    adbd include 了它但 ADB_NON_ANDROID 构建下不用其中任何符号
mkdir -p xinc/sys
cat > xinc/sys/capability.h <<'EOF'
/* Stub for libcap's <sys/capability.h>: adbd includes it but uses nothing
 * from it when built with ADB_NON_ANDROID. */
#ifndef _STUB_SYS_CAPABILITY_H
#define _STUB_SYS_CAPABILITY_H
#include <linux/capability.h>
#endif
EOF

# 4. 交叉编译配置（adbd 的 include.mk 会 -include 顶层 config.mk）
#    注意：不能用命令行传带空格的 OPT_CFLAGS，会被 make 按空格拆词。
cat > adbd-linux/config.mk <<EOF
CC = aarch64-linux-gnu-gcc
CXX = aarch64-linux-gnu-g++
AR = aarch64-linux-gnu-ar
RANLIB = aarch64-linux-gnu-ranlib
OPT_CFLAGS = -O2 -g -I$WORK/xinc -I$PREFIX/include
OPT_CXXFLAGS = -O2 -g -I$WORK/xinc -I$PREFIX/include
LFLAGS = -static -L$PREFIX/lib
EOF

# 5. 编译 adbd（先静态库，再 adb/adbd；xdg-adbd 需要 glib 不编译）
cd adbd-linux
make libcutils/libcutils.a base/libbase.a libcrypto_utils/libcrypto_utils.a
make -C adb adbd

ls -la adb/adbd
echo "OK: $(pwd)/adb/adbd"
