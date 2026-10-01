#!/bin/sh
# 在 postmarketOS 的 g1 USB gadget 上启用 functionfs adbd（与 NCM USB 网络共存）。
#
# 必须通过 systemd-run 脱离 SSH 会话运行（否则会话断开时 systemd 会杀掉
# 会话 cgroup 内的 adbd 和本脚本，导致 functionfs 关闭、gadget 断网锁死）：
#
#   scp polaris-adbd-setup.sh user@172.16.42.1:/tmp/
#   scp adbd user@172.16.42.1:/tmp/adbd        # 见 polaris-adbd-build.sh
#   ssh user@172.16.42.1
#   sudo systemd-run --unit=pmos-adbd --collect /bin/sh /tmp/polaris-adbd-setup.sh
#
# 日志：/tmp/adbd-setup.log
trap '' HUP
G=/sys/kernel/config/usb_gadget/g1
UDC=$(ls /sys/class/udc | head -1)
LOG=/tmp/adbd-setup.log
exec >>"$LOG" 2>&1
set -x
ADBD_PID=

# ---- 网络看门狗（独立后台）：UDC 空 >6s 强制恢复，ffs 绑不上就剔除 ffs ----
(
    trap '' HUP
    n=0
    while [ $n -lt 20 ]; do
        sleep 6
        n=$((n+1))
        if [ -z "$(cat "$G/UDC" 2>/dev/null)" ]; then
            echo "WD: UDC empty, rebind attempt $n"
            if echo "$UDC" > "$G/UDC" 2>/dev/null; then
                echo "WD: rebound OK (with ffs)"
                exit 0
            fi
            echo "WD: rebind failed, stripping ffs"
            rm -f "$G/configs/c.1/ffs.adb"
            rmdir "$G/functions/ffs.adb" 2>/dev/null
            if echo "$UDC" > "$G/UDC" 2>/dev/null; then
                echo "WD: ncm-only restored"
                exit 0
            fi
            echo "WD: restore FAILED"
        fi
    done
) &
WD_PID=$!

# ---- 不断网的准备工作 ----
# mkdir functions 在 UDC 绑定期间允许；但 symlink 不允许（见临界窗口）
mkdir -p "$G/functions/ffs.adb"
mkdir -p /dev/usb-ffs/adb
grep -q " /dev/usb-ffs/adb " /proc/mounts || mount -t functionfs adb /dev/usb-ffs/adb
echo "MNT_RC=$?"

# adbd 启动后立即向 ep0 写入 USB 描述符（ffs 进入 READY）
ADB_TRACE=all /tmp/adbd &
ADBD_PID=$!
sleep 2
kill -0 "$ADBD_PID" 2>/dev/null && echo "ADBD_UP pid=$ADBD_PID" || echo "ADBD_START_FAIL"

# ---- 临界窗口：unbind 后才能创建 symlink（configfs 绑定期间禁止修改配置）；
# symlink 目标相对 cwd 解析，必须 cd 到 c.1 里再 ln ----
echo "" > "$G/UDC"
rm -f "$G/configs/c.1/ffs.adb"
( cd "$G/configs/c.1" && ln -s ../../functions/ffs.adb ffs.adb )
echo "LN_RC=$?"
if echo "$UDC" > "$G/UDC"; then
    echo "SETUP_OK"
else
    echo "BIND_FAILED"
fi

# ---- adbd 守护 + UDC 守护 ----
while true; do
    sleep 3
    if ! kill -0 "$ADBD_PID" 2>/dev/null; then
        echo "GUARDIAN: adbd died, restart"
        ADB_TRACE=all /tmp/adbd &
        ADBD_PID=$!
        sleep 2
        kill -0 "$ADBD_PID" 2>/dev/null || echo "GUARDIAN: restart failed"
    fi
    if [ -z "$(cat "$G/UDC" 2>/dev/null)" ]; then
        echo "GUARDIAN: UDC unbound, rebind"
        echo "$UDC" > "$G/UDC" 2>/dev/null || {
            rm -f "$G/configs/c.1/ffs.adb"
            rmdir "$G/functions/ffs.adb" 2>/dev/null
            echo "$UDC" > "$G/UDC" 2>/dev/null
            echo "GUARDIAN: ncm-only fallback"
        }
    fi
done
