#!/bin/bash
# Read-only post-boot verification for the 7.3 kernel on the TSV.
set -uo pipefail
export SSHPASS=${SSHPASS:-}
HOST=${HOST:-ubuntu@192.168.10.12}
sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no "$HOST" 'bash -s' <<'EOF'
echo "== kernel =="
uname -r; cat /proc/cmdline
echo; echo "== boot files =="
ls -l /boot/vmlinuz /boot/apq8053-lenovo-cd-18781y.dtb /boot/initramfs | cat
echo; echo "== modules dirs =="
ls /lib/modules
echo; echo "== critical modules loaded =="
for m in snd_soc_tas5782m panel-lenovo-cd-18781y-hx83100a himax_hx83112b ath10k_sdio vcnl4000 bmc150_accel venus_core qcom_camss s5kc505a; do
  printf "%-24s %s\n" "$m" "$(lsmod | awk -v m="$m" '$1==m{print "loaded"}' | head -1)"
done
echo; echo "== display =="
cat /sys/class/drm/card0-DSI-1/status 2>/dev/null
cat /sys/class/backlight/*/brightness 2>/dev/null
echo; echo "== input devices =="
grep -H "" /sys/class/input/input*/name 2>/dev/null | sed 's|/sys/class/input/||'
echo; echo "== alsa =="
aplay -l 2>/dev/null | head -12
echo; echo "== iio =="
for d in /sys/bus/iio/devices/iio:device*; do echo -n "$d: "; cat "$d/name" 2>/dev/null; done
echo; echo "== video =="
for v in /sys/class/video4linux/video*; do echo -n "$(basename $v): "; cat "$v/name" 2>/dev/null; done
echo; echo "== wifi =="
ip -br addr show wlan0 2>/dev/null; iw dev 2>/dev/null | grep -E "ssid|channel" | head -4
echo; echo "== usb gadget =="
ip -br addr show usb0 2>/dev/null || echo "no usb0"
echo; echo "== cpufreq =="
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
echo; echo "== watchdog =="
ls -l /dev/watchdog* 2>/dev/null
echo; echo "== dmesg: errors/warnings =="
dmesg --level=err,warn 2>/dev/null | tail -40
echo; echo "== dmesg: key probes =="
dmesg | grep -iE "tas5782m|{{SECRET_cx3pnsyi}}|hx831|vcnl|bma|ath10k|venus|qcom-camss|s5kc505a|watchdog" | tail -30
echo; echo "== thermal =="
cat /sys/class/thermal/thermal_zone*/type 2>/dev/null | tr "\n" " "; echo
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null
EOF