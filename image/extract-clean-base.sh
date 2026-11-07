#!/bin/bash
# Extract a 100% clean Ubuntu 24.04 (noble) arm64 base rootfs, bootfs, and
# standalone tsv-voice ONNX/C runtime assets, permanently stripping out all
# legacy Xiaozhi (hub/client/uv) and userspace workaround scripts/services.
#
# Output:
#   flash/ubuntu-24.04-base-bootfs.tar.zst
#   flash/ubuntu-24.04-base-rootfs.tar.zst
#   flash/tsv-runtime-assets.tar.zst
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SRC_IMG=${1:-$ROOT/flash/thinksmart-ubuntu-20261101.img}
OUT_DIR=$ROOT/flash

[ -f "$SRC_IMG" ] || { echo "Missing source image: $SRC_IMG" >&2; exit 1; }

LOOP=$(sudo /usr/sbin/losetup --find --show -P -r "$SRC_IMG")
MNT=$(mktemp -d /tmp/tsv-clean-extract.XXXXXX)
STAGE=$(mktemp -d /tmp/tsv-clean-stage.XXXXXX)
cleanup() {
	sudo umount "$MNT/boot" 2>/dev/null || true
	sudo umount "$MNT/root" 2>/dev/null || true
	sudo /usr/sbin/losetup -d "$LOOP" 2>/dev/null || true
	sudo rm -rf "$MNT" "$STAGE"
}
trap cleanup EXIT

mkdir -p "$MNT/boot" "$MNT/root" "$STAGE/boot" "$STAGE/root" "$STAGE/assets"
sudo mount -o ro "${LOOP}p1" "$MNT/boot"
sudo mount -o ro "${LOOP}p2" "$MNT/root"

echo "== 1. Extracting standalone tsv-voice runtime assets (libonnxruntime, libsherpa-onnx, libwebrtc_apm, ONNX models)"
sudo install -d -o 1000 -g 1000 \
	"$STAGE/assets/opt/tsv/lib" \
	"$STAGE/assets/opt/tsv/models/kws-zh" \
	"$STAGE/assets/opt/tsv/models/asr" \
	"$STAGE/assets/opt/tsv/models/vad"

sudo cp -L "$MNT/root/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/.venv/lib/python3.10/site-packages/sherpa_onnx/lib/libonnxruntime.so" \
           "$STAGE/assets/opt/tsv/lib/libonnxruntime.so"
sudo cp -L "$MNT/root/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/.venv/lib/python3.10/site-packages/sherpa_onnx/lib/libsherpa-onnx-c-api.so" \
           "$STAGE/assets/opt/tsv/lib/libsherpa-onnx-c-api.so"
sudo cp -L "$MNT/root/opt/thinksmart/client/0.1.0/thinksmart_client/webrtc_apm/linux/arm64/libwebrtc_apm.so" \
           "$STAGE/assets/opt/tsv/lib/libwebrtc_apm.so"
sudo cp -a "$MNT/root/opt/thinksmart/client/0.1.0/models/kws-zh/." \
           "$STAGE/assets/opt/tsv/models/kws-zh/"
sudo cp -a "$MNT/root/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/models/sherpa-onnx-x-asr-zipformer-transducer-zh-en-punct-int8-2026-06-03/." \
           "$STAGE/assets/opt/tsv/models/asr/"
sudo cp -L "$MNT/root/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/models/snakers4_silero-vad/src/silero_vad/data/silero_vad.onnx" \
           "$STAGE/assets/opt/tsv/models/vad/silero_vad.onnx"
sudo chown -R 1000:1000 "$STAGE/assets/opt/tsv"
sudo tar --numeric-owner -C "$STAGE/assets" -cf - . | zstd -T0 -6 -f -o "$OUT_DIR/tsv-runtime-assets.tar.zst"
ls -lh "$OUT_DIR/tsv-runtime-assets.tar.zst"

echo "== 2. Extracting clean bootfs skeleton (initramfs + extlinux.conf only)"
sudo install -d -o 0 -g 0 "$STAGE/boot/extlinux" "$STAGE/boot/dtbs/qcom"
sudo cp -a "$MNT/boot/initramfs" "$STAGE/boot/initramfs"
sudo cp -a "$MNT/boot/extlinux/extlinux.conf" "$STAGE/boot/extlinux/extlinux.conf"
sudo tar --numeric-owner -C "$STAGE/boot" -cf - . | zstd -T0 -6 -f -o "$OUT_DIR/ubuntu-24.04-base-bootfs.tar.zst"
ls -lh "$OUT_DIR/ubuntu-24.04-base-bootfs.tar.zst"

echo "== 3. Copying and purging rootfs (removing all Xiaozhi, justhalfbit workarounds, and 6.19.5 artifacts)"
sudo cp -a "$MNT/root/." "$STAGE/root/"
R="$STAGE/root"

# Remove Xiaozhi Hub, Xiaozhi Client, Updater, uv Python toolchains (~1.1 GB)
sudo rm -rf "$R/home/ubuntu/xiaozhi-hub-server" \
            "$R/home/ubuntu/xiaozhi-workspace" \
            "$R/home/ubuntu/.local/bin/uv" \
            "$R/home/ubuntu/.local/bin/uvx" \
            "$R/home/ubuntu/.local/share/uv" \
            "$R/home/ubuntu/.local/share/thinksmart-kiosk" \
            "$R/home/ubuntu/.cache/thinksmart-kiosk" \
            "$R/opt/thinksmart" \
            "$R/opt/tas5782m-test" \
            "$R/var/lib/thinksmart-update"

# Remove all legacy userspace workaround scripts, binaries, and welcome portal
sudo rm -rf "$R/usr/local/bin/"* \
            "$R/usr/local/sbin/"* \
            "$R/usr/local/share/thinksmart-kiosk" \
            "$R/etc/thinksmart-kiosk.conf" \
            "$R/etc/pam.d/thinksmart-kiosk" \
            "$R/etc/systemd/coredump.conf.d/90-thinksmart-kiosk.conf"

# Remove all legacy systemd system & user units and wants links
sudo rm -f "$R/etc/systemd/system/thinksmart-"* \
           "$R/etc/systemd/system/display-guard.service" \
           "$R/etc/systemd/system/screen-wake.service" \
           "$R/etc/systemd/system/venus-firmware-fix.service" \
           "$R/etc/systemd/system/i2c1-pinmux-fix.service" \
           "$R/etc/systemd/system/qup-i2c-pinctrl-fix.service" \
           "$R/etc/systemd/system/pmos-audio-route.service" \
           "$R/etc/systemd/system/multi-user.target.wants/thinksmart-"* \
           "$R/etc/systemd/system/multi-user.target.wants/display-guard.service" \
           "$R/etc/systemd/system/multi-user.target.wants/screen-wake.service" \
           "$R/etc/systemd/system/multi-user.target.wants/i2c1-pinmux-fix.service" \
           "$R/etc/systemd/system/multi-user.target.wants/qup-i2c-pinctrl-fix.service" \
           "$R/etc/systemd/system/multi-user.target.wants/pmos-audio-route.service" \
           "$R/etc/systemd/system/graphical.target.wants/thinksmart-kiosk.service" \
           "$R/etc/systemd/system/sysinit.target.wants/thinksmart-ssh-hostkeys.service" \
           "$R/etc/systemd/system/sysinit.target.wants/venus-firmware-fix.service" \
           "$R/etc/systemd/system/timers.target.wants/thinksmart-update-check.timer" \
           "$R/etc/systemd/system/swap.target.wants/thinksmart-zram.service"

sudo rm -rf "$R/home/ubuntu/.config/systemd" \
            "$R/home/ubuntu/.config/wireplumber" \
            "$R/etc/wireplumber/main.lua.d/99-cd18781y-alsa.lua" \
            "$R/etc/xdg/systemd/user/idle-blanker.service" \
            "$R/etc/xdg/systemd/user/vcnl4200-proximity-daemon.service" \
            "$R/etc/xdg/systemd/user/graphical-session.target.wants/idle-blanker.service" \
            "$R/etc/xdg/systemd/user/default.target.wants/vcnl4200-proximity-daemon.service" \
            "$R/usr/share/alsa/ucm2/Qualcomm/cd-18781y"

# Remove legacy workaround sudoers rules
sudo rm -f "$R/etc/sudoers.d/i2c-prox" \
           "$R/etc/sudoers.d/idle-blanker" \
           "$R/etc/sudoers.d/proximity" \
           "$R/etc/sudoers.d/user" \
           "$R/etc/udev/rules.d/99-vp5-touchscreen-input.rules"

# Remove old 6.19.5 kernel modules and old 3044-byte TAS5782M blob
sudo rm -rf "$R/lib/modules/"* \
            "$R/lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin" \
            "$R/lib/firmware/tas5782m_dsp_lenovo_cd-18781y.bin"

# Remove stray root-level debug artifacts
sudo rm -f "$R/tracing_on" "$R/set_ftrace_filter" "$R/current_tracer" "$R/\$bl" "$R/trace"

echo "== Clean rootfs disk usage:"
sudo du -sh "$R" "$R/usr" "$R/home" "$R/opt" "$R/var" "$R/etc"

sudo tar --numeric-owner --xattrs --xattrs-include='*' --acls -C "$R" -cf - . | zstd -T0 -6 -f -o "$OUT_DIR/ubuntu-24.04-base-rootfs.tar.zst"
ls -lh "$OUT_DIR/ubuntu-24.04-base-rootfs.tar.zst"
echo "== Clean base archives extracted successfully!"
