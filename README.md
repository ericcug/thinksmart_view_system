# Lenovo ThinkSmart View (`CD-18781Y`) — Mainline Linux 7.3 Kernel, Ubuntu 24.04 System Overlay & EDL Image Builder

A standalone, production-hardened **Mainline Linux 7.3 (`7.3.0-tsv`)** kernel patchset, **Ubuntu 24.04 (`noble` arm64)** system overlay, and **Qualcomm EDL (`9008`) from-scratch image builder** for the **Lenovo ThinkSmart View (`CD-18781Y` / `lenovo-cd-18781y`)**.

Our core engineering philosophy is:
> **"Eliminate fragile userspace workarounds (`devmem`, I2C unbind/rebind scripts, raw I2C polling daemons, and ALSA loopback hacks) by fixing hardware lifecycle, clock, and power-management bugs at the root in the Linux kernel drivers and Device Tree."**

---

## 1. Current Solution Overview (Architecture & System Stack)

Instead of patching a bloated legacy disk image in-place, this project builds a **100% clean, reproducible MBR disk image (`pmOS_boot` + `pmOS_root`) from scratch** using `sfdisk` and `mke2fs -d`:

1. **Kernel Layer (`7.3.0-tsv`, `msm8953-mainline`)**:
   * **43 ordered kernel patches** (`0001`–`0909`) providing complete mainline support for APQ8053-Lite at **1.80 GHz**, dual-variant displays/touchscreens (Boe/Himax `HX83100A` & Boyi/FocalTech `FT8201`), TI `TAS5782M` 10W DSP speaker amplifier, hardware-synced 2.4 MHz stereo DMICs (`DMIC1` + `DMIC2`), Vishay `VCNL4200` IIO active-force proximity/ALS sensor, Bosch `BMA253` accelerometer, Samsung `S5KC505A` 5MP camera, Qualcomm `Venus` V4L2 codec, `QCA9379` Wi-Fi/Bluetooth, `DWC3` USB peripheral networking, and battery-less PM8953 power-off retention.
2. **System & Audio Layer (Ubuntu 24.04 arm64 + Native PipeWire/WirePlumber)**:
   * **Zero legacy Python/daemon bloat**: All legacy workaround services (`i2c1-pinmux-fix`, `qup-i2c-pinctrl-fix`, `pmos-audio-route`, `vcnl4200-proximity-daemon`, `idle-blanker`, `screen-wake`) are completely removed.
   * **Direct PipeWire + ALSA UCM2 routing**: `HiFi.conf` and `99-tsv-alsa.lua` bind `MultiMedia1 -> QUAT_MI2S_RX` (48 kHz S16LE stereo playback with `Speaker Amp Digital Playback Volume = 207`) and `MultiMedia2 <- TERT_MI2S_TX` (48 kHz S16LE stereo DMIC capture, period 960, `pause-on-idle = false`), with full BlueZ 5 / WirePlumber A2DP Sink & AVRCP support.
3. **Display & Kiosk Session Layer (`weston` + `WebKit2GTK`)**:
   * **`tsv-kiosk`**: Minimal Wayland `weston` (`kiosk-shell.so`, rotated 90°) + fullscreen `WebKit2GTK` (`tsv-kiosk.py`) session on `tty1` configured via `/etc/tsv/kiosk.conf`, with pinch-zoom suppression, automatic crash recovery, and Adreno 506 `FD_MESA_DEBUG=sysmem` GMEM hang protection.

---

## 2. Hardware Support Matrix (Mainline Linux `7.3.0-tsv`)

| Subsystem | Hardware / Spec | Linux 7.3 Status | Kernel Driver & System Fix Summary |
| :--- | :--- | :--- | :--- |
| **SoC / CPU / Thermal** | Qualcomm APQ8053-Lite (8× Cortex-A53) | ✅ **Full 1.80 GHz** | Fixed `cpr4pd` APM 850 mV threshold comparison (`>=`), unlocking `652 MHz – 1804.8 MHz` (+46% over 6.19's 1.23 GHz cap); 75°C / 85°C / 100°C thermal trip policy |
| **Hardware Watchdog** | APSS Watchdog (`qcom-wdt`) | ✅ **Active** | Kernel `qcom-wdt` + systemd (`RuntimeWatchdogSec=30s`, `RebootWatchdogSec=2min`) for automatic hard-hang recovery |
| **Display & Backlight** | 8" 800×1280 MIPI DSI + PMI8950 WLED | ✅ **Dual-Variant Auto** | Preserves `lk2nd` `lenovo,cd-18781y-panel` placeholder for runtime **Boe/Himax (`HX83100A`)** & **Boyi/FocalTech (`FT8201`)** selection; fixed DPU atomic `encoder_mask` vblank error |
| **Touchscreen** | Himax `HX83100A` (`2-0048`) / FocalTech `FT8201` (`2-0038`) | ✅ **Dual-Variant + Blank Wake** | Both panel drivers retain bias supplies and deasserted reset during display blanking (`unprepare`) with `wakeup-source` enabled |
| **Speaker Amplifier** | TI `TAS5782M` (10W Class-D + DSP) | ✅ **Stock Acoustic Tuning** | Mainline `snd-soc-tas5782m` + `apq8016_sbc` `QUAT_MI2S` `spkr_iomux` fix + Lenovo GPL 1523-register EQ/DRC firmware + `i2c-qup` clock readiness wait |
| **Dual Digital Mics** | `DMIC1` + `DMIC2` (`msm8916-wcd-digital`) | ✅ **2.4 MHz Synced Stereo** | Per-decimator (`DEC1`/`DEC2`) DMIC clock divider locked at `2.4 MHz`; fixed `q6asm` unmap OOB & stale `port->buf` lockup; measured cross-domain drift is only **-22.9 ppm** |
| **Proximity & Ambient Light** | Vishay `VCNL4200` (`i2c-0 @ 0x51`) | ✅ **Safe Active-Force IIO** | Kernel `vcnl4000` initializes to **Active-Force single-shot, 1 pulse, 50 mA, 9T (`864 µs`)** and returns 16-bit integer counts; 0 IR pulses when screen is on |
| **Accelerometer** | Bosch `BMA253` (`iio:device0`) | ✅ **With Mount Matrix** | Device Tree `mount-matrix` (`-1, 0, 0; 0, -1, 0; 0, 0, 1`) for tap-wake and orientation |
| **Front Camera** | Samsung `S5KC505A` (5MP, `CCI 0x37` + `CAMSS`) | ✅ **RAW10 @ 30 fps** | Reverse-engineered `s5kc505a` V4L2 subdev driver supporting `2608×1960` / `1304×980` 30 fps capture + `GPIO 87` privacy shutter switch |
| **Hardware Video Codec** | Qualcomm `Venus` (`video6` / `video7`) | ✅ **B-Frame Dec & Enc** | Fixed H.264/HEVC B-frame EOS delivery, NV12 chroma slack (+4K), and `STREAMOFF` runtime PM wake to prevent AXI bus lockup |
| **Wi-Fi & Bluetooth** | Qualcomm `QCA9379` (SDIO + UART) | ✅ **0-Delay GTK Rekey + A2DP** | `ath10k` `key_update_no_sec_ind` skips 3s timeout and resets RX PN replay counters; `hci0` loads `00150100` fw with BlueZ A2DP Sink/AVRCP |
| **USB-C Port** | `DWC3` (`172.16.42.1/16` USB NCM) | ✅ **Restored** | DTB `dr_mode = "peripheral"` + `gcc_usb30_master_clk` `CLK_OPS_PARENT_ENABLE` |
| **Power-Off** | PM8953 PON (`qcom,pm8916-pon`) | ✅ **Stays Off** | `qcom,pon-reset-off` clears `CBLPWR_N` + `PON1` in `PON_TRIGGER_EN` (`0x880`) so `poweroff` is not undone by the always-present DC supply (battery-less board, no power key) |
| **Clock / RTC** | PM8953 RTC without backup battery | ✅ **Anchor Restored** | `tsv-clock` saves the `(rtc0, realtime)` pair after NTP sync and restores an estimated wall clock at early boot; the RTC counter itself survives reboot/poweroff but resets to 1970 when the supply is removed |
| **Kiosk GPU Workaround** | Adreno 506 / freedreno in WebKit2GTK | ✅ **No GMEM Hang** | `FD_MESA_DEBUG=sysmem` in `tsv-kiosk.service` only, avoiding the `layout_gmem()` infinite loop on render targets that do not fit in the 136 KiB GMEM |

---

## 3. Summary of System & Kernel Fixes (What We Patched)

### 3.1 Custom Kernel Patches (`kernel/patches/0901..0909`, on top of `jethac` `0001..0704` & `salaman` `0801..0807`)

1. **`0901-arm64-dts-qcom-apq8053-lenovo-cd-18781y-dual-variant.patch` (Dual-Variant DTB, I2C1 Sleep Pinmux, IPA & Venus)**:
   * Restores `panel@0` compatible to the generic `lenovo,cd-18781y-panel` placeholder and sets both `ft8201_ts` and `hx83100a_ts` to `status = "disabled"` with `wakeup-source`, allowing the `lk2nd` bootloader to dynamically patch the active display and touchscreen variant at boot.
   * Pins `&i2c_1` `pinctrl-0` (`default`) and `pinctrl-1` (`sleep`) both to `<&i2c_1_default>` so GPIO 2/3 never drop out of `func2 (blsp_i2c1)` when `78b5000.i2c` enters runtime PM suspend.
   * Disables unused `&ipa` to silence interconnect warnings and sets `&venus` `firmware-name = "venus.mdt"` to match the flat modem partition layout.
2. **`0902-ASoC-qcom-apq8016_sbc-configure-spkr_iomux-for-QUATE.patch` (Speaker QUAT MI2S Pin Routing)**:
   * On `CD-18781Y`, `QUATERNARY_MI2S_RX` audio output is physically wired through the `SECONDARY_MI2S` pins (`GPIO 135–138`). Mainline `apq8016_sbc.c` only configured `mic_iomux` on `MI2S_QUATERNARY`, leaving `BCLK`/`WS` unrouted (`TAS5782M` clock error `0x5E = 0x2C`).
   * Configures `pdata->spkr_iomux` (`MCLK_EN | SCLK_EN | DATA1_EN | WS_OUT_SEL_SEC | WS_EN_SEL_SEC`, `0x00030000 -> 0x0007004E`) in the `MI2S_QUATERNARY` branch.
3. **`0903-ASoC-qcom-qdsp6-fix-q6asm-unmap-OOB-and-always-free-.patch` (QDSP6 `q6asm` Capture Re-Prepare & OOB Fix)**:
   * Fixes an out-of-bounds read in `q6asm_unmap_memory_regions()` where `port->buf[dir].phys` indexed `dir = SNDRV_PCM_STREAM_CAPTURE (1)` on a single-element allocation (`port->buf[0]`).
   * Ensures `q6asm_dai_prepare()` and `q6asm_unmap_memory_regions()` always reset `port->mem_map_handle = 0` and call `q6asm_audio_client_free_buf()`, eliminating `"Buffer already allocated"` lockups when restarting PipeWire/ALSA capture streams.
4. **`0904-iio-light-vcnl4000-safe-VCNL4200-1-pulse-50mA-9T-ini.patch` (Safe VCNL4200 IIO Initialization & Integer Counts)**:
   * Programs `VCNL4200` in `vcnl4200_init()` with safe hardware defaults: **Active-Force single-shot (`PS_AF=1`), 1 pulse (`MPS=0`), 50 mA IR LED drive (`LED_I=0`), 9T (`864 µs`) proximity integration time, 16-bit HD (`PS_HD=1`), and 100 ms ALS integration time** (replacing the upstream 8-pulse @ 120 mA default).
   * Sets `ps_scale = 1` and returns `IIO_VAL_INT` from `in_proximity_raw` so userspace reads clean 16-bit integer ADC counts directly (`~39` unobstructed, `>50` on hand approach).
5. **`0905-drm-msm-dpu-check-atomic-encoder_mask-in-get_encoder.patch` (Eliminate DPU Vblank Error Spam)**:
   * Updates `get_encoder_from_crtc()` in `dpu_crtc.c` to inspect `crtc->state->encoder_mask` via `drm_for_each_encoder_mask()` before falling back to legacy `encoder->crtc`, completely eliminating `[drm:dpu_crtc_get_vblank_counter [msm]] *ERROR* no encoder found for crtc 0` under Wayland/Weston atomic commits.
6. **`0906-drm-panel-hx83100a-preserve-touch-and-panel-supplies.patch` (Himax Panel Touch-Wake Supply Retention)**:
   * Aligns `panel-lenovo-cd-18781y-hx83100a.c` with the `FT8201` driver (`0806`): retains `vsp`/`vsn` panel supplies and keeps `reset_gpio` deasserted across normal `drm_panel_unprepare()` screen blanking so the TDDI touchscreen remains active for touch-to-wake, while powering off cleanly on `.shutdown` / `.remove` or initialization failure.
7. **`0907-media-venus-venc-resume-PM-on-stop_streaming-and-mar.patch` (Venus Encoder Drain EOS & `STREAMOFF` Deadlock Fix)**:
   * Wraps `venus_helper_vb2_stop_streaming()` with `venc_pm_get()` / `venc_pm_put()` in `venc.c` so `VIDIOC_STREAMOFF` never writes HFI registers while the Venus GDSC/clocks are runtime-suspended (which previously caused an immediate SoC AXI bus hang).
   * Marks 0-byte capture buffers in `VENUS_ENC_STATE_DRAIN` with `V4L2_BUF_FLAG_LAST` to handle `HFI 3xx` firmware (`VIDEO.VE.4.2-00078`) omitting `HFI_BUFFERFLAG_EOS`.
8. **`0908-ASoC-qcom-qdsp6-reset-playback-queue-pointer-and-wrap-hw-pointer.patch` (QDSP6 Playback Restart & Hardware Pointer Wrap)**:
   * Resets `prtd->queue_ptr` in `q6asm_dai_prepare()`: ALSA resets `appl_ptr` to zero when prepare completes, so a stream stopped and prepared again otherwise keeps the driver's queue pointer ahead of the application pointer; `avail_periods` in `q6asm_dai_ack()` becomes negative and no further period is ever queued to the DSP (playback stays silent after a stop/restart). `q6asm_audio_client_free_buf()` also resets the DSP period index (`port->dsp_buf`), so the first period queued after a restart is the first period the application wrote.
   * Wraps the DSP hardware pointer with `% runtime->periods` in `q6asm_dai_pointer()` (matching mainline): Q6ASM reports one past the period it has just finished, so the previous `period_size - 1` result walked past `buffer_size` at every ring lap and made PipeWire's clock estimate jump.
9. **`0909-power-reset-qcom-pon-stay-off-after-poweroff.patch` (Battery-less PM8953 Power-Off Retention)**:
   * Adds the `qcom,pon-reset-off` property to the `qcom-pon` driver and enables it on `CD-18781Y`: at probe, clear `CBLPWR_N` (`BIT(6)`) and `PON1` (`BIT(5)`) in `PON_TRIGGER_EN` (`0x880`). With no battery and no power key, the permanently present DC supply counts as a power-on event, so a normal `poweroff` used to restart the device ~25 s later. Clearing these triggers keeps it off until the supply is removed and re-applied (the PMIC then resets to its default triggers, so plugging it back in powers the device on normally). `reboot` is unaffected.

### 3.2 Root Cause Eliminations & System-Level Fixes (`overlay/` & `image/build-edl-image.sh`)

* **Root Cause of I2C1 (`1-0049` TAS5782M) Dropouts Fixed**:
  * Investigation revealed that a legacy script (`/usr/local/sbin/i2c1-pinmux-fix.sh` via `i2c1-pinmux-fix.service`) in earlier community images miscalculated Qualcomm TLMM `GPIO_CFG` bitfields and executed `devmem 0x1002000 32 0xC3` at boot—actively overwriting GPIO 2/3 from `func=2 (blsp_i2c1)` to `func=0 (GPIO)` and breaking I2C1, while `pmos-audio-route.service` muted `QUAT_MI2S_RX Audio Mixer MultiMedia1`.
  * **Fix**: Removed all legacy `devmem`/unbind/route services and locked `&i2c_1` sleep pinmux in DTB (`0901`) plus `i2c-qup` clock-readiness polling (`0802`).
* **Bootloader (`lk2nd`) Initramfs Size Limit Fixed**:
  * Stuffing 39 MB of `7.3.0-tsv` kernel modules into `/boot/initramfs` bloated it to 70.7 MB, causing `lk2nd` to abort boot (`Could not do normal boot`).
  * **Fix**: Core storage/filesystem/USB drivers (`ext4`, `mmc`, `sdhci`, `dwc3`) are built into `Image.gz`; `/boot/initramfs` remains compact (~11 MB) and all loadable modules reside in `/lib/modules/7.3.0-tsv` on the rootfs.
* **Authentic 1523-Register Lenovo GPL TAS5782M DSP Firmware**:
  * Legacy images shipped a 1522-pair table (`tas5728m_dsp_lenovo_cd-18781y.bin`) missing clock/PLL setup registers (`0x25=0x18`, `0x0D=0x10`) required by mainline `snd-soc-tas5782m`.
  * **Fix**: `firmware/fetch-tas5782m-tuning.sh` extracts and verifies the exact **1523-register (3046-byte)** tuning binary (`SHA256: 8122f082...`) from Lenovo's official GPL tarball (`lenovo_cd-18781y_cd-18781y.201218.2018_opensource.tgz`) and installs both `tas5782m_dsp_lenovo_cd-18781y.bin` and the legacy alias, loaded deterministically via `tas5782m-load.service` after `msm-firmware-loader.service` and `adsp-start.service`.
* **ZRAM Swap (`tsv-zram.service`) & First-Boot Auto-Resize (`tsv-growroot.service`)**:
  * Fixed `zramctl` failure on Kernel 7.3 by using the kernel's native `zstd` compressor (`1900M` swap at priority 100) and ordering `After=local-fs.target` with graceful `msm` eviction parameter handling.
  * Added `tsv-growroot.service` (`resize2fs`) to automatically expand the `pmOS_root` ext4 partition to fill the full ~6.4 GB `system` eMMC partition on first boot, plus `tsv-ssh-hostkeys.service` to generate SSH host keys if missing.
* **Non-Root Hardware Access (`udev`) & Bluetooth Audio (`BlueZ` + `WirePlumber`)**:
  * `70-tsv-vcnl4200.rules` configures `vcnl4000` IIO sysfs attributes (`in_proximity_oversampling_ratio=1`, `in_proximity_calibbias=0.050000`, `in_proximity_integration_time=0.000864`, `in_illuminance_integration_time=0.100000`, `MODE=0664`, `GROUP=i2c`) and grants group `video` write access (`0664`) to `/sys/class/backlight/*/brightness` so unprivileged services can control the backlight and read IIO sensors without `sudo`.
  * `99-tsv-touchscreen.rules` tags both `Himax Touchscreen` and `FocalTech FT8201*` input nodes for seat access.
  * `etc/bluetooth/main.conf` (`FastConnectable = true`, `JustWorksRepairing = always`), `bluetooth.service.d/override.conf` (`--noplugin=hostname,sap`), and `51-tsv-bluetooth.lua` enable low-latency 48 kHz SBC-XQ Bluetooth A2DP Sink & AVRCP media control under headless `systemd` (without requiring `logind`).
* **ALSA/PipeWire QDSP6 Node Fixes (`overlay/etc/wireplumber/main.lua.d/99-tsv-alsa.lua`)**:
  * `api.alsa.disable-mmap` is a PCM-node property, not a card property. It is now applied to the playback and capture nodes; the previous card-level setting silently did nothing.
  * Playback and capture share the ADSP clock (`clock.name = "api.alsa.cd18781y"`), with `api.alsa.disable-batch`, a fixed 960-frame period/quantum and explicit headroom (`4096` playback, `768` capture) so stream joins/leaves do not change the graph quantum and Q6ASM's whole-period pointer does not cause resampling jitter.
* **Battery-less RTC Anchor (`overlay/usr/local/bin/tsv-clock` + `tsv-clock-*.service`/`.timer`)**:
  * The PM8953 RTC has no backup battery: it keeps counting across reboot and poweroff but starts from 1970 after the supply is removed. `tsv-clock` records the `(rtc0/since_epoch, system realtime)` pair after NTP synchronization (timer every 10 min) and restores an estimated wall clock at early boot before the network is up.
* **WebKit/freedreno GMEM Hang Avoided (`tsv-kiosk.service`)**:
  * Adreno 506 `layout_gmem()`/`calc_nbins()` can spin forever when a WebKit render target does not fit in the 136 KiB GMEM (GPU canvas, WebGL, some complex dashboards). `FD_MESA_DEBUG=sysmem` is set for the browser service only, so rendering goes straight to memory; it is deliberately not set system-wide because it disables tiling for every other GL program.
* **Clean From-Scratch `mke2fs -d` Image Assembly (`image/build-edl-image.sh`)**:
  * Builds `pmOS_boot` (249 MiB `ext2`) and `pmOS_root` (`ext4`) directly from staging directories without loop-mounting or inheriting dirty state, and explicitly verifies via `debugfs` that Linux file capabilities (e.g. `cap_net_raw` on `/usr/bin/ping`) are preserved.

---

## 4. Repository Structure

```text
.
├── kernel/
│   ├── build.sh                 # Fetches msm8953-mainline 7.3, applies all 43 patches, and builds Image.gz, DTB & modules
│   ├── install-to-device.sh     # Live SSH kernel/DTB/module/overlay updater (retains *.619 backup for instant rollback)
│   ├── check-device.sh          # Automated post-boot hardware & subsystem health check script
│   ├── config/
│   │   └── lenovo-cd-18781y.config
│   └── patches/                 # 43 ordered kernel patches:
│       ├── 0001..0704-*.patch   #   [27] jethac/lenovo-thinksmart-view baseline patches
│       ├── 0801..0807-*.patch   #   [ 7] salaman/tsv-lineage patches (simplefb, i2c-qup, usb-clk, drm/dpu, ft8201, bma253)
│       └── 0901..0909-*.patch   #   [ 9] Our patches (dual-variant DTB/i2c1, QUAT spkr_iomux, q6asm, VCNL4200, DPU, HX83100A, Venus, q6asm playback/pointer, PON power-off)
├── firmware/
│   ├── fetch-tas5782m-tuning.sh # Extracts & verifies the 1523-register TAS5782M DSP firmware from Lenovo's official GPL archive
│   └── tas5782m-dsp-fw.py
├── overlay/                     # Clean rootfs overlay (ALSA UCM2, WirePlumber ALSA/BT, systemd services, udev rules, tsv-kiosk, tsv-clock)
├── image/
│   └── build-edl-image.sh       # From-scratch MBR + ext2/ext4 EDL system image builder
├── tools/
│   └── dpms.c                   # DRM/KMS display DPMS state test utility
└── docs/                        # Hardware reports, Linux 7.3 bring-up logs & the guge2/m0s4ik reference integration note
```

---

## 5. Quick Start

### 5.1 Build Mainline Linux `7.3.0-tsv` Kernel & Modules

Install host build dependencies (`clang-19`, `lld-19`, `llvm-19`, `bc`, `bison`, `flex`, `device-tree-compiler`, `libelf-dev`, `libssl-dev`):

```bash
./kernel/build.sh
```

Build artifacts are generated at:
* `kernel/build-7.3/arch/arm64/boot/Image.gz`
* `kernel/build-7.3/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb`
* `kernel/stage/modules.tar`

### 5.2 Build the Clean Standalone EDL System Image

Ensure the base system archives (`ubuntu-24.04-base-bootfs.tar.zst` and `ubuntu-24.04-base-rootfs.tar.zst`) are placed in `flash/`, then run:

```bash
# Build the standalone EDL system image:
./image/build-edl-image.sh

# Or build and produce a compressed .img.xz archive:
./image/build-edl-image.sh --compress
```

Output image and checksums:
* `flash/thinksmart-ubuntu-kernel73.img`
* `flash/thinksmart-ubuntu-kernel73.img.sha256`

### 5.3 Flash via Qualcomm EDL (`9008`) Mode

1. Unplug the power adapter and connect the ThinkSmart View to your PC via a USB-A to USB-C data cable.
2. **Press and hold both `Volume +` and `Volume -`**, plug in the DC power cable, wait ~5 seconds until `05c6:9008` appears in `lsusb`, then release the buttons.
3. Flash the `system` partition and reboot:

```bash
./edl-venv/bin/edl w system flash/thinksmart-ubuntu-kernel73.img
./edl-venv/bin/edl reset
```

On first boot, `tsv-growroot.service` automatically expands the root `ext4` filesystem to fill the entire `system` partition (~6.4 GB) and starts the `7.3.0-tsv` hardware stack and Wayland kiosk session.

---

## 6. Credits & License

* Build scripts, overlay configurations, tools, and documentation are licensed under the **MIT License**; Linux kernel patches under `kernel/patches/` are licensed under **GPL-2.0-only**.
* Special thanks to the community projects that laid the groundwork for mainline Linux on the Lenovo ThinkSmart View:
  * [FelixKa](https://gitlab.postmarketos.org/postmarketOS/pmaports) (postmarketOS `lenovo-cd-18781y` port & early `TAS5782M` bring-up)
  * [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart) (Ubuntu 24.04 port, partition layout & `QUAT_MI2S` `spkr_iomux` discovery)
  * [justhalfbit/thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image) (Ubuntu system image, Freedreno a5xx fixes & DMIC decimator clock discovery)
  * [jethac/lenovo-thinksmart-view](https://github.com/jethac/lenovo-thinksmart-view) (Linux 7.3 mainline patchset & reverse-engineered `S5KC505A` camera driver)
  * [salaman/tsv-lineage](https://github.com/salaman/tsv-lineage) (QUP I2C clock readiness, USB FSM parent clock, DPU flush & `FT8201` blanking retention patches)
  * [guge2/thinksmart-view-assistant](https://github.com/guge2/thinksmart-view-assistant) (qdsp6 playback `queue_ptr`/hardware-pointer analysis, WirePlumber QDSP6 clock/IRQ properties, battery-less RTC anchor)
  * [m0s4ik/thinksmart-view-debian](https://github.com/m0s4ik/thinksmart-view-debian) (PM8953 `qcom,pon-reset-off` power-off retention, freedreno GMEM hang workaround)
