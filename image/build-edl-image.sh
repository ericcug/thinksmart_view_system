#!/bin/bash
# Build a clean, standalone EDL-flashable Ubuntu 24.04 + Mainline Linux 7.3.0-tsv
# system image for Lenovo ThinkSmart View (CD-18781Y) from scratch using mke2fs -d.
#
# Zero legacy Xiaozhi (hub/client/updater) and zero userspace hardware workarounds.
#
# Usage:
#   image/build-edl-image.sh [--with-v3 /path/to/tsv-voice] [--compress]
#
# Inputs:
#   flash/ubuntu-24.04-base-bootfs.tar.zst
#   flash/ubuntu-24.04-base-rootfs.tar.zst
#   flash/tsv-runtime-assets.tar.zst
#   kernel/build-7.3/ + kernel/stage/modules.tar
#   firmware/out/tas5782m_dsp_lenovo_cd-18781y.bin
#   overlay/
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BASE_BOOT=$ROOT/flash/ubuntu-24.04-base-bootfs.tar.zst
BASE_ROOT=$ROOT/flash/ubuntu-24.04-base-rootfs.tar.zst
TSV_ASSETS=$ROOT/flash/tsv-runtime-assets.tar.zst
OUT_IMG=${OUT_IMG:-$ROOT/flash/thinksmart-ubuntu-kernel73.img}
KBUILD=$ROOT/kernel/build-7.3
STAGE=$ROOT/kernel/stage
TAS_FW=$ROOT/firmware/out/tas5782m_dsp_lenovo_cd-18781y.bin
DEFAULT_V3=$ROOT/tsv/target/aarch64-unknown-linux-gnu/release/tsv-voice
V3_BIN=${V3_BIN:-}
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

if [ -z "$V3_BIN" ] && [ -f "$DEFAULT_V3" ]; then
	V3_BIN="$DEFAULT_V3"
fi

for f in "$BASE_BOOT" "$BASE_ROOT" "$KBUILD/arch/arm64/boot/Image.gz" \
         "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
         "$STAGE/modules.tar"; do
	[ -f "$f" ] || { echo "Missing required input: $f" >&2; exit 1; }
done

if [ ! -f "$TAS_FW" ]; then
	"$ROOT/firmware/fetch-tas5782m-tuning.sh" \
		"$ROOT/firmware/dl" "$ROOT/firmware/out" "$ROOT/firmware/out/manifest.tsv"
fi

VER=$(cat "$KBUILD/include/config/kernel.release")
WORK=$(mktemp -d /tmp/tsv-clean-build.XXXXXX)
cleanup() {
	sudo rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/boot" "$WORK/root"

echo "== 1. Unpacking clean Ubuntu 24.04 (noble) arm64 base bootfs & rootfs"
zstd -dc "$BASE_BOOT" | sudo tar -x --numeric-owner -p -C "$WORK/boot"
zstd -dc "$BASE_ROOT" | sudo tar -x --numeric-owner --xattrs --xattrs-include='*' --acls -p -C "$WORK/root"

B="$WORK/boot"
R="$WORK/root"
sudo rm -rf "$R/opt/tas5782m-test" "$R/etc/systemd/timesyncd.conf.d/thinksmart.conf" \
            "$R/etc/systemd/journald.conf.d/thinksmart.conf" \
            "$R/etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf"

echo "== 2. Installing Mainline Linux $VER kernel, DTB & modules (0 legacy kernels)"
sudo install -o 0 -g 0 -m 644 "$KBUILD/arch/arm64/boot/Image.gz" "$B/vmlinuz"
sudo install -o 0 -g 0 -m 644 "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
             "$B/apq8053-lenovo-cd-18781y.dtb"
sudo install -d -o 0 -g 0 "$B/dtbs/qcom"
sudo install -o 0 -g 0 -m 644 "$KBUILD/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
             "$B/dtbs/qcom/apq8053-lenovo-cd-18781y.dtb"
sudo install -o 0 -g 0 -m 644 "$KBUILD/System.map" "$B/System.map"
sudo install -o 0 -g 0 -m 644 "$KBUILD/.config" "$B/config"

sudo install -d -o 0 -g 0 "$R/lib/modules"
sudo tar -C "$R/lib/modules" -xf "$STAGE/modules.tar"
sudo chown -R 0:0 "$R/lib/modules/$VER"
sudo /usr/sbin/depmod -b "$R" "$VER"

echo "== 3. Installing Lenovo GPL TAS5782M DSP firmware (1523 register writes)"
sudo install -o 0 -g 0 -m 644 "$TAS_FW" "$R/lib/firmware/tas5782m_dsp_lenovo_cd-18781y.bin"
sudo install -o 0 -g 0 -m 644 "$TAS_FW" "$R/lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin"

echo "== 4. Applying clean TSV hardware & kiosk overlay"
sudo install -d -o 0 -g 0 \
	"$R/etc/modules-load.d" \
	"$R/etc/pam.d" \
	"$R/etc/systemd/system" \
	"$R/etc/systemd/system/graphical.target.wants" \
	"$R/etc/systemd/system/multi-user.target.wants" \
	"$R/etc/systemd/system/swap.target.wants" \
	"$R/etc/systemd/system/sysinit.target.wants" \
	"$R/etc/systemd/system/timers.target.wants" \
	"$R/etc/systemd/system.conf.d" \
	"$R/etc/tsv" \
	"$R/etc/udev/rules.d" \
	"$R/etc/wireplumber/main.lua.d" \
	"$R/usr/local/bin" \
	"$R/usr/share/alsa/ucm2/Lenovo/cd-18781y" \
	"$R/usr/share/alsa/ucm2/conf.d/cd-18781y"
sudo install -d -o 1000 -g 1000 "$R/home/ubuntu/.config/wireplumber/main.lua.d"

sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/modules-load.d/audio-cd18781y.conf" \
             "$R/etc/modules-load.d/audio-cd18781y.conf"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/pam.d/tsv-kiosk" \
             "$R/etc/pam.d/tsv-kiosk"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/tsv/kiosk.conf" \
             "$R/etc/tsv/kiosk.conf"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/systemd/system.conf.d/10-watchdog.conf" \
             "$R/etc/systemd/system.conf.d/10-watchdog.conf"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/udev/rules.d/70-tsv-vcnl4200.rules" \
             "$R/etc/udev/rules.d/70-tsv-vcnl4200.rules"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/udev/rules.d/99-tsv-touchscreen.rules" \
             "$R/etc/udev/rules.d/99-tsv-touchscreen.rules"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/wireplumber/main.lua.d/99-tsv-alsa.lua" \
             "$R/etc/wireplumber/main.lua.d/99-tsv-alsa.lua"
sudo install -o 1000 -g 1000 -m 644 "$ROOT/overlay/etc/wireplumber/main.lua.d/99-tsv-alsa.lua" \
             "$R/home/ubuntu/.config/wireplumber/main.lua.d/99-tsv-alsa.lua"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/usr/share/alsa/ucm2/Lenovo/cd-18781y/HiFi.conf" \
             "$R/usr/share/alsa/ucm2/Lenovo/cd-18781y/HiFi.conf"
sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/usr/share/alsa/ucm2/conf.d/cd-18781y/cd-18781y.conf" \
             "$R/usr/share/alsa/ucm2/conf.d/cd-18781y/cd-18781y.conf"

sudo install -o 0 -g 0 -m 755 "$ROOT/overlay/usr/local/bin/tsv-kiosk-session" \
             "$R/usr/local/bin/tsv-kiosk-session"
sudo install -o 0 -g 0 -m 755 "$ROOT/overlay/usr/local/bin/tsv-kiosk.py" \
             "$R/usr/local/bin/tsv-kiosk.py"
sudo install -o 0 -g 0 -m 755 "$ROOT/overlay/usr/local/bin/tsv-clock" \
             "$R/usr/local/bin/tsv-clock"

for unit in msm-firmware-loader.service adsp-start.service tas5782m-load.service \
            tsv-zram.service tsv-growroot.service tsv-ssh-hostkeys.service tsv-kiosk.service \
            tsv-clock-restore.service tsv-clock-save.service tsv-clock-save.timer; do
	sudo install -o 0 -g 0 -m 644 "$ROOT/overlay/etc/systemd/system/$unit" \
	             "$R/etc/systemd/system/$unit"
done

sudo ln -sfn /etc/systemd/system/msm-firmware-loader.service \
             "$R/etc/systemd/system/sysinit.target.wants/msm-firmware-loader.service"
sudo ln -sfn /etc/systemd/system/tsv-ssh-hostkeys.service \
             "$R/etc/systemd/system/sysinit.target.wants/tsv-ssh-hostkeys.service"
sudo ln -sfn /etc/systemd/system/adsp-start.service \
             "$R/etc/systemd/system/multi-user.target.wants/adsp-start.service"
sudo ln -sfn /etc/systemd/system/tas5782m-load.service \
             "$R/etc/systemd/system/multi-user.target.wants/tas5782m-load.service"
sudo ln -sfn /etc/systemd/system/tsv-growroot.service \
             "$R/etc/systemd/system/multi-user.target.wants/tsv-growroot.service"
sudo ln -sfn /etc/systemd/system/tsv-zram.service \
             "$R/etc/systemd/system/swap.target.wants/tsv-zram.service"
sudo ln -sfn /etc/systemd/system/tsv-kiosk.service \
             "$R/etc/systemd/system/graphical.target.wants/tsv-kiosk.service"
sudo ln -sfn /etc/systemd/system/tsv-clock-restore.service \
             "$R/etc/systemd/system/sysinit.target.wants/tsv-clock-restore.service"
sudo ln -sfn /etc/systemd/system/tsv-clock-save.timer \
             "$R/etc/systemd/system/timers.target.wants/tsv-clock-save.timer"

if [ -n "$V3_BIN" ]; then
	echo "== 5. Installing standalone V3 tsv-voice ($V3_BIN) & ONNX/C runtime assets"
	[ -f "$TSV_ASSETS" ] || { echo "Missing $TSV_ASSETS" >&2; exit 1; }
	zstd -dc "$TSV_ASSETS" | sudo tar -x --numeric-owner -p -C "$R"
	sudo install -o 0 -g 0 -m 755 "$V3_BIN" "$R/usr/local/bin/tsv-voice"
	if [ -f "$ROOT/tsv/deploy/edge-tts" ]; then
		sudo install -o 0 -g 0 -m 755 "$ROOT/tsv/deploy/edge-tts" "$R/usr/local/bin/edge-tts"
	fi
	sudo install -d -o 1000 -g 1000 "$R/var/cache/tsv/tts" "$R/var/lib/tsv"
	if [ -f "$ROOT/tsv/deploy/config.example.yaml" ]; then
		sudo install -o 1000 -g 1000 -m 644 "$ROOT/tsv/deploy/config.example.yaml" \
		             "$R/etc/tsv/config.yaml"
	fi
	if [ -f "$ROOT/tsv/deploy/secrets.example.yaml" ]; then
		sudo install -o 1000 -g 1000 -m 600 "$ROOT/tsv/deploy/secrets.example.yaml" \
		             "$R/etc/tsv/secrets.yaml"
	fi
	if [ -f "$ROOT/tsv/deploy/tsv-voice.service" ]; then
		sudo install -o 0 -g 0 -m 644 "$ROOT/tsv/deploy/tsv-voice.service" \
		             "$R/etc/systemd/system/tsv-voice.service"
		sudo ln -sfn /etc/systemd/system/tsv-voice.service \
		             "$R/etc/systemd/system/multi-user.target.wants/tsv-voice.service"
	fi
fi

echo "== 6. Assembling MBR disk image from scratch with mke2fs -d"
BOOT_UUID=35bca636-764e-4f53-b5e5-96eb774eb19e
ROOT_UUID=8b6cd6d2-cf64-4279-b1cc-426345d5b822
BOOT_START=2048
BOOT_SECTORS=509952
ROOT_START=512000

sudo /usr/sbin/getcap -r "$R/usr" 2>/dev/null | sed "s|^$R||" > "$WORK/caps.txt" || true

used_mb=$(sudo du -s --block-size=1M -x "$R" | cut -f1)
files=$(sudo find "$R" -xdev | wc -l)
root_mb=$(( used_mb * 115 / 100 + 200 ))
root_sectors=$(( root_mb * 2048 ))
inodes=$(( files * 2 > 150000 ? files * 2 : 150000 ))

rm -f "$OUT_IMG.tmp"
truncate -s $(( (ROOT_START + root_sectors) * 512 )) "$OUT_IMG.tmp"
/usr/sbin/sfdisk -q "$OUT_IMG.tmp" <<SF
label: dos
label-id: 0x37d1617d
unit: sectors
start=$BOOT_START, size=$BOOT_SECTORS, type=83
start=$ROOT_START, size=$root_sectors, type=83
SF

BOOT_FS="$OUT_IMG.tmp?offset=$((BOOT_START*512))"
ROOT_FS="$OUT_IMG.tmp?offset=$((ROOT_START*512))"

echo "   Creating pmOS_boot (ext2, 249 MiB)..."
sudo /usr/sbin/mke2fs -q -t ext2 -b 4096 -L pmOS_boot -U "$BOOT_UUID" \
	-E root_owner=0:0,offset=$((BOOT_START*512)) \
	-d "$B" "$OUT_IMG.tmp" $((BOOT_SECTORS/8))
sudo /usr/sbin/e2fsck -fn "$BOOT_FS" >/dev/null

echo "   Creating pmOS_root (ext4, content=${used_mb} MiB -> partition=${root_mb} MiB, inodes=${inodes})..."
sudo /usr/sbin/mke2fs -q -t ext4 -b 4096 -I 256 -N "$inodes" -L pmOS_root -U "$ROOT_UUID" \
	-O has_journal,ext_attr,resize_inode,dir_index,filetype,extent,64bit,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum,^orphan_file,^metadata_csum_seed \
	-E root_owner=0:0,offset=$((ROOT_START*512)) \
	-d "$R" "$OUT_IMG.tmp" $((root_sectors/8))

# Verify file capabilities (e.g. cap_net_raw on /usr/bin/ping) survived mke2fs -d
while read -r path cap; do
	[ -n "$path" ] || continue
	got=$(sudo /usr/sbin/debugfs -R "ea_get $path security.capability" "$ROOT_FS" 2>/dev/null | head -1)
	[ -n "$got" ] || { echo "ERROR: capability lost on $path ($cap)" >&2; exit 1; }
done < "$WORK/caps.txt"

sudo /usr/sbin/e2fsck -fn "$ROOT_FS" >/dev/null

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
echo "== Clean Standalone EDL Image Ready: $OUT_IMG"
