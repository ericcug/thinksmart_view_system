#!/bin/bash
# Live-deploy the 7.3.0-tsv kernel, DTB, modules, TAS5782M firmware, and
# system overlay to a running ThinkSmart View over SSH, keeping 6.19.5 as *.619.
#
#   kernel/install-to-device.sh            install + reboot
#   kernel/install-to-device.sh rollback   restore 6.19.5 + reboot
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
HOST=${HOST:-ubuntu@192.168.10.12}
OUT=$HERE/build-7.3
STAGE=$HERE/stage
TAS_FW=$ROOT/firmware/out/tas5782m_dsp_lenovo_cd-18781y.bin
DTB=apq8053-lenovo-cd-18781y.dtb

export SSHPASS=${SSHPASS:-}
SSH=(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o PreferredAuthentications=password -o PubkeyAuthentication=no "$HOST")
SCP=(sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o PreferredAuthentications=password -o PubkeyAuthentication=no)

if [[ ${1:-} == rollback ]]; then
	"${SSH[@]}" 'sudo bash -s' <<'EOF'
set -e
for f in vmlinuz apq8053-lenovo-cd-18781y.dtb initramfs System.map config; do
	[ -e "/boot/$f.619" ] || { echo "missing /boot/$f.619" >&2; exit 1; }
	cp -a "/boot/$f.619" "/boot/$f"
done
sync
echo "Restored 6.19.5 boot files"
EOF
	"${SSH[@]}" 'sudo nohup systemctl reboot >/dev/null 2>&1 &' || true
	exit 0
fi

[ -f "$TAS_FW" ] || "$ROOT/firmware/fetch-tas5782m-tuning.sh" \
	"$ROOT/firmware/dl" "$ROOT/firmware/out" "$ROOT/firmware/out/manifest.tsv"

VER=$(cat "$OUT/include/config/kernel.release")
echo "== Uploading kernel $VER, modules, firmware, and overlay to $HOST"
tar -C "$ROOT/overlay" -cf "$STAGE/overlay.tar" .
"${SCP[@]}" "$STAGE/modules.tar" "$STAGE/overlay.tar" "$TAS_FW" \
	"$OUT/arch/arm64/boot/Image.gz" \
	"$OUT/arch/arm64/boot/dts/qcom/$DTB" \
	"$OUT/.config" "$OUT/System.map" "$HOST:/tmp/"

echo "== Installing on device (keeping original 6.19.5 initramfs untouched)"
"${SSH[@]}" "sudo bash -s -- $VER" <<'EOF'
set -e
VER=$1
for f in vmlinuz apq8053-lenovo-cd-18781y.dtb initramfs System.map config; do
	[ -e "/boot/$f.619" ] || cp -a "/boot/$f" "/boot/$f.619"
done
tar -C /lib/modules -xf /tmp/modules.tar
chown -R 0:0 "/lib/modules/$VER"
depmod -a "$VER"

install -m 644 /tmp/tas5782m_dsp_lenovo_cd-18781y.bin /lib/firmware/tas5782m_dsp_lenovo_cd-18781y.bin
install -m 644 /tmp/tas5782m_dsp_lenovo_cd-18781y.bin /lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin

tar -C / -xf /tmp/overlay.tar
rm -f /etc/systemd/system/multi-user.target.wants/i2c1-pinmux-fix.service \
      /etc/systemd/system/multi-user.target.wants/qup-i2c-pinctrl-fix.service \
      /etc/systemd/system/multi-user.target.wants/pmos-audio-route.service \
      /etc/systemd/system/i2c1-pinmux-fix.service \
      /etc/systemd/system/qup-i2c-pinctrl-fix.service \
      /etc/systemd/system/pmos-audio-route.service \
      /usr/local/sbin/i2c1-pinmux-fix.sh \
      /usr/local/sbin/qup-i2c-pinctrl-fix.sh \
      /etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf \
      /etc/systemd/timesyncd.conf.d/thinksmart.conf \
      /etc/sysctl.d/99-swappiness.conf \
      /etc/sysctl.d/99-zram.conf

if [ -d /home/ubuntu ]; then
	install -d -o 1000 -g 1000 /home/ubuntu/.config/wireplumber/main.lua.d \
	                           /home/ubuntu/.config/wireplumber/bluetooth.lua.d
	install -o 1000 -g 1000 -m 644 /etc/wireplumber/main.lua.d/99-tsv-alsa.lua \
	                               /home/ubuntu/.config/wireplumber/main.lua.d/99-tsv-alsa.lua
	install -o 1000 -g 1000 -m 644 /etc/wireplumber/bluetooth.lua.d/51-tsv-bluetooth.lua \
	                               /home/ubuntu/.config/wireplumber/bluetooth.lua.d/51-tsv-bluetooth.lua
fi

systemctl daemon-reload
systemctl enable tas5782m-load.service tsv-zram.service tsv-clock-restore.service tsv-clock-save.timer || true

cp /tmp/Image.gz /boot/vmlinuz
cp /tmp/apq8053-lenovo-cd-18781y.dtb /boot/apq8053-lenovo-cd-18781y.dtb
cp /tmp/System.map /boot/System.map
cp /tmp/.config /boot/config
cp -a /boot/initramfs.619 /boot/initramfs
rm -f /tmp/modules.tar /tmp/overlay.tar /tmp/tas5782m_dsp_lenovo_cd-18781y.bin \
      /tmp/Image.gz /tmp/apq8053-lenovo-cd-18781y.dtb /tmp/System.map /tmp/.config
sync
echo "Installed $VER cleanly"
EOF

echo "== Rebooting device"
"${SSH[@]}" 'sudo nohup systemctl reboot >/dev/null 2>&1 &' || true
