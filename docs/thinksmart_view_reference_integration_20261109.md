# Reference integration: guge2 & m0s4ik (2026-11-09)

This note records what was taken from the two community projects added under
`references/`, and what was deliberately not taken because the mainline 7.3
stack already solves it differently.

* [guge2/thinksmart-view-assistant](https://github.com/guge2/thinksmart-view-assistant)
* [m0s4ik/thinksmart-view-debian](https://github.com/m0s4ik/thinksmart-view-debian)
* [justhalfbit/thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image) (`d2e3239`, system layer `0.2.1`) & [justhalfbit/xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client) (`e7ec0de`, client `0.1.6`)

## Integrated

| Area | Reference finding | Change here |
|---|---|---|
| QDSP6 playback restart | `q6asm_dai_prepare()` does not reset `prtd->queue_ptr`; after `snd_pcm_prepare()` the application pointer starts at 0 again, so `q6asm_dai_ack()` computes a negative period count and playback never resumes after a stop | `kernel/patches/0908`: reset `queue_ptr` in `prepare()` and reset `port->dsp_buf` when the buffer is freed |
| QDSP6 hardware pointer | The DSP reports one period past the one it finished; the old `period_size - 1` value walked past `buffer_size` and made PipeWire's clock estimate jump on every lap | `kernel/patches/0908`: `hw_ptr % runtime->periods`, matching mainline |
| Battery-less poweroff | PM8953 `PON_TRIGGER_EN` (`0x880`) keeps `CBLPWR_N`/`PON1` asserted, so `poweroff` restarts the board after ~25 s when the DC supply stays plugged in | `kernel/patches/0909`: `qcom,pon-reset-off` clears both triggers in `drivers/power/reset/qcom-pon.c`, enabled in the CD-18781Y DTS |
| WirePlumber node properties | `api.alsa.disable-mmap` is a PCM-node property; setting it on the card does nothing. Q6ASM reports whole-period positions, so the quantum and headroom must be explicit and playback/capture should share `clock.name` | `overlay/etc/wireplumber/main.lua.d/99-tsv-alsa.lua`: node-level mmap/batch/period/headroom/quantum/clock properties |
| WirePlumber Bluetooth speaker isolation | Paired phones route hands-free calls (`HFP`/`HSP`) to the speaker/mic unless `hfphsp-backend = "none"`; idle suspension of `bluez_input.*` releases the transport while the phone still shows "playing" with no sound; `bluez_input.*` must never become the default capture source | `overlay/etc/wireplumber/bluetooth.lua.d/51-tsv-bluetooth.lua`: `bluez5.hfphsp-backend = "none"`, `session.suspend-timeout-seconds = 0`, `priority.session = 0`, `priority.driver = 0` |
| Phone A2DP channel auto-open (`ensure_audio`) | Phones (especially iPhones right after pairing) often connect control channels without opening A2DP `MediaTransport1`, playing on their own speaker or silently | `tsv/src/hardware/bluetooth.rs`: automatically trusts newly paired devices and calls `org.bluez.Device1.ConnectProfile("0000110a-0000-1000-8000-00805f9b34fb")` when a connected phone has no active transport |
| QCA9379 Wi-Fi power-save DHCP drop | `ath10k_sdio` drops DHCP replies on ~40% of boots when Ubuntu's default Wi-Fi power save (`3`) is active, delaying IPv4 by 1–3 minutes | `overlay/etc/NetworkManager/conf.d/zz-tsv-wifi-powersave-off.conf`: `wifi.powersave = 2` |
| ZRAM sysctl & coredump suppression | With `tsv-zram.service`, `vm.swappiness=100` and `vm.page-cluster=0` avoid page-cache eviction and swap read-ahead overhead; disabling core dumps prevents eMMC wear | `overlay/etc/sysctl.d/99-tsv-zram.conf` & `overlay/etc/systemd/coredump.conf.d/90-tsv-coredump.conf` |
| Battery-less RTC & fast NTP | The PM8953 RTC counter survives reboot and poweroff but resets to 1970 when the supply is removed; NTP has not run yet at early boot | `overlay/usr/local/bin/tsv-clock` + `tsv-clock-*.service`/`.timer` & `overlay/etc/systemd/timesyncd.conf.d/tsv-ntp.conf` |
| Adreno 506 GMEM hang | freedreno `layout_gmem()` can spin forever on WebKit render targets that cannot fit in the 136 KiB GMEM | `FD_MESA_DEBUG=sysmem` in `tsv-kiosk.service` only (not system-wide) |

## Already present in the 7.3 tree

These parts of guge2's `patch-q6asm.py` were already fixed upstream in 7.3, so no
new patch was needed:

* `q6asm_dai_trigger()` no longer changes `prtd->state` on `STOP`/`EOS`; the
  state is cleaned up by the next `prepare()`/`close()`.
* `q6asm_dai_prepare()` keeps `prtd->audio_client` on open/format errors, so
  `close()` owns the final free.
* `q6asm_unmap_memory_regions()` always releases the local buffer state (our
  `0903` patch additionally fixes the `port->buf[dir]` out-of-bounds read).

## Not integrated

| Reference item | Why not |
|---|---|
| PipeWire 1.0.5 `alsa-pcm` IRQ watchdog and `stop_threshold=boundary` patch | This image ships PipeWire 1.2.6 and keeps timer-based scheduling (it does not set `api.alsa.disable-tsched`), so the IRQ watchdog does not apply. The patch would have to be rebased to 1.2.6 and cross-built for arm64. |
| guge2's WebRTC APM (`AEC3`) PipeWire plugin patch | `tsv-voice` runs WebRTC APM inside its own process; it does not use PipeWire's `module-echo-cancel`. |
| guge2's `/etc/pipewire` echo-cancel configuration | Same reason: no PipeWire echo-cancel graph is used. Only the shared clock/quantum properties were kept. |
| m0s4ik's TAS5782M volume/standby driver changes | The mainline `snd-soc-tas5782m` driver (`0302`) already writes the DSP configuration once and keeps it across streams; there is no ~550 ms firmware reload between short sounds, and `S16_LE`/`S24_LE`/`S32_LE` are all accepted. |
| m0s4ik's Venus `hfi_parser.c` replacement | The 7.3 tree already has a working parser, and `0702`, `0703` and `0907` additionally fix B-frame EOS and `STREAMOFF` runtime-PM wake. |
| m0s4ik's userspace VCNL4200 `new_device` service | The sensor is declared in the device tree and initialized safely in the kernel (`0601`, `0602`, `0904`). |
| guge2's `qup-i2c-pinctrl-fix` unbind/rebind service | Kernel `0802` and the DTS sleep-pinmux lock in `0901` remove the root cause; no userspace workaround is needed. |
| m0s4ik's reduced Mesa package | A size/LLVM optimization, not a hardware fix; this image keeps the distro Mesa for WebKit2GTK. |

## Verification performed

* `0908` and `0909` checked with `git apply --check` against a tree containing the
  pre-existing patch series.
* `q6asm.o`, `q6asm-dai.o`, `qcom-pon.o` and the CD-18781Y DTB compile with
  `ARCH=arm64 LLVM=1`.
* `image/build-edl-image.sh` and `kernel/build.sh` pass `bash -n`; `tsv-clock`
  passes `python3 -m py_compile`.
* On-device validation still required for the PON triggers (poweroff, unplug,
  plug back in) and for the playback stop/restart path.