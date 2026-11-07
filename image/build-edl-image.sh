#!/bin/bash
# Build an EDL-flashable Ubuntu 24.04 + Mainline Linux 7.3.0-tsv system image
# for Lenovo ThinkSmart View (CD-18781Y).
#
# Usage:
#   image/build-edl-image.sh [--with-v3 /path/to/tsv-voice] [--compress]
#
# Output:
#   flash/thinksmart-ubuntu-kernel73.img
#   flash/thinksmart-ubuntu-kernel73.img.sha256
#   (and .img.xz if --compress is passed)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SRC_IMG=${SRC_IMG:-$ROOT/flash/thinksmart-ubuntu-20261101.img}
OUT_IMG=${OUT_IMG:-$ROOT/flash/thinksmart-ubuntu-kernel73.img}
KBUILD=$ROOT/kernel/build-7.3
STAGE=$ROOT/kernel/stage
TAS_FW=$ROOT/firmware/out/tas5782m_dsp_lenovo_cd-18781y.bin
V3_BIN=""
COMPRESS=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--with-v3)
			V3_BIN="${2:?missing path to tsv-voice binary}"
			shift 2
			;;
		--compress)
			COMPRESS=1
			shift
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 2
			;;
	esac
done

[ -f "$SRC_IMG" ] || { echo "Missing base image: $SRC_IMG" >&2; exit 1; }
[ -f "$KBUILD/arch/arm64/boot/Image.gz" ] || { echo "Missing kernel Image.gz in $KBUILD (run kernel/build.sh first)" >&2; exit 1; }
[ -f "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" ] || { echo "Missing DTB" >&2; exit 1; }
[ -f "$STAGE/modules.tar" ] || { echo "Missing $STAGE/modules.tar" >&2; exit 1; }
if [ ! -f "$TAS_FW" ]; then
	"$ROOT/firmware/fetch-tas5782m-tuning.sh" \
		"$ROOT/firmware/dl" "$ROOT/firmware/out" "$ROOT/firmware/out/manifest.tsv"
fi

VER=$(cat "$KBUILD/include/config/kernel.release")
echo "== Building EDL system image with kernel $VER"
echo "   Base image : $SRC_IMG"
echo "   Output     : $OUT_IMG"

cp -f --sparse=always "$SRC_IMG" "$OUT_IMG.tmp"

LOOP=$(sudo /usr/sbin/losetup --find --show -P "$OUT_IMG.tmp")
MNT=$(mktemp -d /tmp/tsv-edl-mnt.XXXXXX)
cleanup() {
	sudo umount "$MNT/boot" 2>/dev/null || true
	sudo umount "$MNT/root" 2>/dev/null || true
	sudo /usr/sbin/losetup -d "$LOOP" 2>/dev/null || true
	rm -rf "$MNT"
}
trap cleanup EXIT

mkdir -p "$MNT/boot" "$MNT/root"
sudo mount "${LOOP}p1" "$MNT/boot"
sudo mount "${LOOP}p2" "$MNT/root"

echo "== 1. Updating /boot (pmOS_boot) with $VER kernel & DTB (preserving *.619 backup and original initramfs)"
for f in vmlinuz apq8053-lenovo-cd-18781y.dtb initramfs System.map config; do
	if [ -e "$MNT/boot/$f" ] && [ ! -e "$MNT/boot/$f.619" ]; then
		sudo cp -a "$MNT/boot/$f" "$MNT/boot/$f.619"
	fi
done
sudo cp "$KBUILD/arch/arm64/boot/Image.gz" "$MNT/boot/vmlinuz"
sudo cp "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
        "$MNT/boot/apq8053-lenovo-cd-18781y.dtb"
if [ -d "$MNT/boot/dtbs/qcom" ]; then
	sudo cp "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
	        "$MNT/boot/dtbs/qcom/apq8053-lenovo-cd-18781y.dtb"
fi
sudo cp "$KBUILD/System.map" "$MNT/boot/System.map"
sudo cp "$KBUILD/.config" "$MNT/boot/config"

echo "== 2. Installing /lib/modules/$VER and running depmod"
sudo rm -rf "$MNT/root/lib/modules/$VER"
sudo tar -C "$MNT/root/lib/modules" -xf "$STAGE/modules.tar"
sudo chown -R 0:0 "$MNT/root/lib/modules/$VER"
sudo /usr/sbin/depmod -b "$MNT/root" "$VER"

echo "== 3. Installing Lenovo GPL TAS5782M DSP firmware (1523 register writes)"
sudo install -m 644 "$TAS_FW" "$MNT/root/lib/firmware/tas5782m_dsp_lenovo_cd-18781y.bin"
sudo install -m 644 "$TAS_FW" "$MNT/root/lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin"

echo "== 4. Applying rootfs overlay (systemd units, watchdog, VCNL4200 udev rule & IIO daemons)"
sudo cp -a "$ROOT/overlay/." "$MNT/root/"
sudo chown -R 0:0 "$MNT/root/etc/modules-load.d/audio-cd18781y.conf" \
                   "$MNT/root/etc/systemd/system/tas5782m-load.service" \
                   "$MNT/root/etc/systemd/system/thinksmart-zram.service" \
                   "$MNT/root/etc/systemd/system.conf.d/10-watchdog.conf" \
                   "$MNT/root/etc/udev/rules.d/70-tsv-vcnl4200.rules" \
                   "$MNT/root/usr/local/bin/idle-blanker.py" \
                   "$MNT/root/usr/local/bin/screen-wake-daemon.py" \
                   "$MNT/root/usr/local/bin/vcnl4200-proximity-daemon.py"
sudo ln -sf /etc/systemd/system/tas5782m-load.service \
            "$MNT/root/etc/systemd/system/multi-user.target.wants/tas5782m-load.service"

# Remove legacy broken scripts that overwrote GPIO2/3 with func0 (0xC3) or disabled QUAT_MI2S_RX
sudo rm -f "$MNT/root/etc/systemd/system/multi-user.target.wants/i2c1-pinmux-fix.service" \
           "$MNT/root/etc/systemd/system/multi-user.target.wants/qup-i2c-pinctrl-fix.service" \
           "$MNT/root/etc/systemd/system/multi-user.target.wants/pmos-audio-route.service" \
           "$MNT/root/etc/systemd/system/i2c1-pinmux-fix.service" \
           "$MNT/root/etc/systemd/system/qup-i2c-pinctrl-fix.service" \
           "$MNT/root/etc/systemd/system/pmos-audio-route.service" \
           "$MNT/root/usr/local/sbin/i2c1-pinmux-fix.sh" \
           "$MNT/root/usr/local/sbin/qup-i2c-pinctrl-fix.sh"

if [ -n "$V3_BIN" ]; then
	echo "== 5. Installing V3 Rust binary ($V3_BIN) and disabling legacy Xiaozhi stack"
	sudo install -m 755 "$V3_BIN" "$MNT/root/usr/local/bin/tsv-voice"
	if [ -f "$ROOT/tsv/deploy/tsv-voice.service" ]; then
		sudo install -m 644 "$ROOT/tsv/deploy/tsv-voice.service" "$MNT/root/etc/systemd/system/tsv-voice.service"
		sudo ln -sf /etc/systemd/system/tsv-voice.service \
		            "$MNT/root/etc/systemd/system/multi-user.target.wants/tsv-voice.service"
	fi
	sudo rm -f "$MNT/root/etc/systemd/system/multi-user.target.wants/thinksmart-client.service" \
	           "$MNT/root/home/ubuntu/.config/systemd/user/default.target.wants/xiaozhi-hub.service"
fi

echo "== Unmounting & running e2fsck verification"
sync
sudo umount "$MNT/boot"
sudo umount "$MNT/root"
sudo /usr/sbin/e2fsck -fn "${LOOP}p1"
sudo /usr/sbin/e2fsck -fn "${LOOP}p2"
sudo /usr/sbin/losetup -d "$LOOP"
trap - EXIT
rm -rf "$MNT"

mv -f "$OUT_IMG.tmp" "$OUT_IMG"
sha256sum "$OUT_IMG" > "$OUT_IMG.sha256"
ls -lh "$OUT_IMG"
cat "$OUT_IMG.sha256"

if (( COMPRESS )); then
	echo "== Compressing $OUT_IMG.xz"
	xz -T4 -6 -k -f "$OUT_IMG"
	sha256sum "$OUT_IMG.xz" >> "$OUT_IMG.sha256"
	ls -lh "$OUT_IMG.xz"
fi
echo "== EDL Image Ready: $OUT_IMG"
