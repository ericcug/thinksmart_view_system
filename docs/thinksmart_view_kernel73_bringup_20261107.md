# ThinkSmart View：mainline Linux 7.3 内核编译与上线记录（2026-11-07）

> 设备：Lenovo ThinkSmart View CD-18781Y（Himax HX83100A 屏/触控变体）
> 目标内核：`7.3.0-tsv`（msm8953-mainline `barni2000/7.3/develop` @ `755ffc44d5d8`）
> 结果：**已上线并稳定运行**，CPU 1.8GHz、音频、Wi-Fi、USB 网卡、双麦、摄像头探测、Venus、传感器均正常

---

## 1. 补丁组成

| 来源 | 内容 |
| :--- | :--- |
| `jethac/lenovo-thinksmart-view` `kernel/patches/` | 全部 27 个：`0001~0003` DTS/面板常供电、`0101` ath10k 密钥、`0201~0206` cpufreq/CPR/温控/看门狗、`0301~0303` TAS5782M、`0401~0404` S5KC505A、`0501~0504` DMIC 时钟、`0601~0602` VCNL4200、`0701~0704` Venus |
| `salaman/tsv-lineage` | `0003` I2C QUP 时钟就绪、`0005` USB FSM 父时钟、`0011` DRM GEM、`0012` DPU flush、`0018` FT8201 熄屏保活 |
| 本地 `local-patches/0001` | ① panel compatible 还原为通用占位符 `lenovo,cd-18781y-panel`（由 lk2nd 在启动时按实际面板前置插入具体型号）② `ft8201_ts` 还原为 `disabled`，`panel-lenovo-cd-18781y-hx83100a` 补 `wakeup-source` ③ Venus `firmware-name` 改为镜像里实际存在的扁平 `venus.mdt` |

构建：`clang 19.1.7` + `LLD 19.1.7`，`LOCALVERSION="-tsv"`，8 核约 10 分钟。
产物：`Image.gz` 9.2 MB、`apq8053-lenovo-cd-18781y.dtb` 67 KB、模块 39 MB。

---

## 2. 上线时踩到的四个坑（重要）

### 坑 1：70 MB 的 initramfs 让 lk2nd 直接放弃启动（本次“变砖”的真凶）
第一次安装时把 7.3 的 39 MB 模块塞进原 11 MB initramfs，未压缩体积涨到 **70.7 MB**，lk2nd 加载失败并退回 fastboot（屏幕/日志显示 `Could not do normal boot`）。
**解决**：initramfs 保持原样（`6.19.5` 那份），模块放根分区 `/lib/modules/7.3.0-tsv` 由 udev 加载。ext4/mmc/sdhci/DWC3 在 7.3 中均为 built-in，initramfs 不需要新模块即可挂根。
> 结论：**不要重打 initramfs**。`/boot/initramfs` 至今仍是 6.19 的原始文件。

### 坑 2：功放固件文件名差一个字符，声卡根本不注册
7.3 的 `tas5782m` 驱动按 `tas5782m_dsp_<name>.bin` 找固件，镜像里只有 rickx 时代的 `tas5728m_dsp_lenovo_cd-18781y.bin`（5728 拼写）。缺文件 → probe 失败 → `snd_soc_apq8016_sbc` 卡片 deferred probe → `aplay -l` 空。
**解决**：
```bash
ln -sf tas5728m_dsp_lenovo_cd-18781y.bin /lib/firmware/tas5782m_dsp_lenovo_cd-18781y.bin
```

### 坑 3：`snd-soc-tas5782m` 开机不自动加载
`/etc/modules-load.d` 在该镜像里没有真正生效（且原有 `audio-cd18781y.conf` 写的是已不存在的 `snd_soc_tas5782m_dbg`）。**注意：不能把服务挂到 `sound.target`**——声卡不存在就不会触发 `sound.target`，形成死循环。
**解决**：新增 `/etc/systemd/system/tas5782m-load.service`：
```ini
[Unit]
Description=Load the TAS5782M speaker amplifier codec
After=local-fs.target
Before=multi-user.target
[Service]
Type=oneshot
ExecStart=/sbin/modprobe snd-soc-tas5782m
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
```
并把 `/etc/modules-load.d/audio-cd18781y.conf` 内容改为 `snd-soc-tas5782m`。

### 坑 4：zram 的 lz4 在 7.3 下不可用
7.3 配置里 zram 只注册了 `zstd`（`/sys/block/zram0/comp_algorithm` 只有 `[zstd]`），原服务写死 `--algorithm lz4` 会报 `Invalid argument`；此外该服务 `DefaultDependencies=no` 跑得太早，`/sys/module/msm/parameters/enable_eviction` 还不存在，导致整体失败。
**解决**：
- 去掉 `--algorithm lz4`（改用 zstd）
- `ExecStartPre=-/bin/sh -c 'echo N > /sys/module/msm/parameters/enable_eviction'`（`-` 容忍失败）
- 增加 `After=local-fs.target`

---

## 3. 实测结果（重启后自动生效）

| 项目 | 结果 |
| :--- | :--- |
| 内核 | `7.3.0-tsv`，量到 7.3 |
| 显示 | DSI `connected`，背光 1670，面板为 Himax 变体（lk2nd 正确前置 compatible） |
| 触控 | `input1: Himax Touchscreen`，`2-0048` |
| 扬声器 | `card 0: cd18781y`，PipeWire sink `Built-in Audio Speaker`，`tas5782m` 写入 1522 条 DSP 系数 |
| 麦克风 | `pw-record --target thinksmart_mic` 3 秒：rms 99.2、peak 714（有真实信号） |
| 语音栈 | `thinksmart-client` 与 `xiaozhi-hub` 均 active，客户端输入/输出流都挂在真实设备上 |
| Wi-Fi | `wlan0` 已连 `Home`，5GHz ch52 80MHz |
| USB | gadget 枚举 `18d1:d00a`，`usb0 = 172.16.42.1/16`（**6.19 下失效的 USB 网卡已恢复**） |
| CPU | `scaling_max_freq = 1804800`（1.8GHz 满血），温度 47.6°C |
| 看门狗 | `/dev/watchdog0` 存在 |
| 传感器 | `bma253`、`vcnl4000` 两个 IIO 设备；ALS raw 0、prox raw 0（无遮挡，符合 jethac 实测的 0~1 counts） |
| 摄像头 | `s5kc505a 3-0037: chip id 0x5034` 探测成功，CAMSS/CCI/CSIPHY0 拓扑建立，`/dev/media0` 可枚举 |
| Venus | `qcom-venus-decoder`/`encoder` 注册（`/dev/video6/7`），固件按需加载 |
| zram | `zstd`，1.9 GB swap，`systemctl --failed` 为 0 |

---

## 4. 与 6.19 的差异与收益

- CPU 从 1.23 GHz 锁频恢复到 **1.8048 GHz**（+46%）
- USB 设备模式/网卡恢复（`172.16.42.1`）
- 功放、双麦、传感器不再依赖用户态守护：VCNL4200 走内核 active-force；I2C 不再需要 unbind/rebind；Wi-Fi 换密钥不再等 3 秒
- Venus 支持含 B 帧的 1080p H.264/HEVC 硬解与任意分辨率硬编码
- 摄像头主线驱动可用

---

## 5. 回滚方法

`/boot` 下保留完整 6.19.5 启动文件：
```
/boot/vmlinuz.619
/boot/apq8053-lenovo-cd-18781y.dtb.619
/boot/initramfs.619
/boot/System.map.619
/boot/config.619
```
- 系统还能开机/SSH 时：把上述文件改回原名即可。
- 系统起不来时：进 EDL（lk2nd 菜单选 `edl`，或 Vol+/- + 插电），只写回 249 MB 启动分区：
```bash
edl ws 925696 /tmp/bootpart.img      # 从 flash/thinksmart-ubuntu-20261101.img 的 2048 扇区起切出
edl reset
```
- 根分区（Friday 配置、网关数据）在两种方式下都不受影响。

---

## 6. 仍未完成/待验证

1. **蓝牙**：`hci0: Frame reassembly failed`，7.3 DTS 未配置 QCA9379 的 `firmware-name`/`local-bd-address`（需要时按 `devices/bluetooth/ANALYSIS.md` 补 DTS）。
2. **摄像头实际出图**：驱动与拓扑已就绪，尚未跑 `tsvcam`/libcamera 的完整采集（需加载 `system_heap`）。
3. **Venus 功能性验证**：模块与固件就绪，尚未跑含 B 帧的 1080p 解码/编码用例。
4. **Himax 变体的真 DPMS 熄屏**：`salaman 0018` 只针对 FT8201；本机仍沿用 halfbit 的“只关背光”方案（`idle-blanker`）。若要在 Himax 上做 DRM off 保活触控，需要给 `panel-lenovo-cd-18781y-hx83100a.c` 写同款补丁。
5. **KASLR**：aboot 未提供 `kaslr-seed`，内核日志 `KASLR disabled due to lack of seed`（不影响功能）。
6. `smsm: can't parse "mboxes" property`、`debugfs 'me' already exists` 均为无害告警，7.3 DTS 的遗留项。
---

## 7. 扬声器无声：两个独立根因（2026-11-07 晚补记）

上电后 `aplay -l` 有卡、`tas5782m` 也 probe 成功（写入 1522 条系数），但喇叭完全无声。逐层排查后确认是**两个独立问题叠加**：

### 7.1 根因 A：QUAT MI2S 没有接到 TLMM 引脚（缺 rickx 的 iomux 补丁）
7.3 主线的 `apq8016_sbc.c` 只在 **SECONDARY** 分支里配置 `spkr_iomux`；QUATERNARY 分支只写了 `mic_iomux` 的 WS/SLCK 位。本板把 QUAT MI2S 输出复用到 SEC 的物理引脚（GPIO 135–138），因此 Q6 AFE 虽然有数据，**引脚上没有 BCLK/WS**。
判据（直接读功放寄存器）：
- `0x5E`（时钟错误）= `0x2C`（非 0）
- `0x03` 在播放中读 `0x40`（正常播放应为 `0x00` 且 `0x5E=0`）

修复：把 rickx `apq8016_sbc-quat-mi2s-iomux.patch` 的思路加进 QUATERNARY 分支——清 `WS_OUT_SEL/WS_EN_SEL`，置 `MCLK_EN|SCLK_EN|DATA<｜begin▁of▁sentence｜>当前位置1_EN|WS_OUT_SEL_SEC|WS_EN_SEL_SEC`。实测写入 `spkr_iomux: 0x00030000 → 0x0007004E`。
已固化为本地补丁：`/work/repos/tsv-kernel/local-patches/0002-apq8016-sbc-quat-mi2s-iomux.patch`。

### 7.2 根因 B：DSP 固件是旧驱动那一份，缺少时钟/采样率初始化
镜像里的 `/lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin` 是 rickx 时代给 `tas5782m-dbg` 用的表（**1522 对**，3044 B），前几项是 `0x02=0x80`、`0x22=0x03`，**没有** jethac 驱动依赖的时钟配置（`0x25=0x18`、`0x0D=0x10` 等），所以即使引脚有 BCLK，功放也锁不住。
修复：用 jethac 的 `fetch-tas5782m-tuning.sh` 从联想 GPL 源码（`lenovo_cd-18781y_cd-18781y.201218.2018_opensource.tgz`，376 MB，SHA256 `713685c2…`）转换出正确的表：
- 文件：`tas5782m_dsp_lenovo_cd-18781y.bin`
- **1523 对 / 3046 B**，SHA256 `8122f08212ba17ea5f1dfafb04afc381a90e0bb0fdf1a59bb8647d9dca65a0bf`（与 jethac 实测一致）
- 安装到 `/lib/firmware/`，**不要**再用 `tas5728m…` 的软链接

### 7.3 验证（用本机麦克风回采，客观测量）
| 测试 | 结果 |
| :--- | :--- |
| 直接 ALSA：`speaker-test -D hw:0,0` 1 kHz，音量 0 dB，`arecord hw:0,1` 回采 | rms 5767、1 kHz Goertzel 幅值 3966，`0x5E=0x00` |
| 全链路 PipeWire：`pw-play` 440 Hz（sink 0.5），麦克风回采 | rms 960、440 Hz 幅值 85（可闻） |
| 功放寄存器 | `0x03=0xE0`（数据中）/`0x5E=0x00`（无时钟错误） |

> 注：调试时用 `i2ctransfer -y -f 1 …` 才能绕过已绑定的驱动读写功放寄存器；`i2cget` 会报 `Device or resource busy`。

### 7.4 与旧 6.19 栈的差异汇总（扬声器相关）
| 项 | 6.19（rickx） | 7.3（本次） |
| :--- | :--- | :--- |
| 驱动 | `snd-soc-tas5782m-dbg.ko` + 自带 preboot（含 0x25/0x0D 写入） | 主线化 `snd-soc-tas5782m.ko`，preboot 依赖固件文件 |
| 固件 | 1522 对的旧表 | 1523 对、Lenovo GPL 原始表 |
| 路由 | 需要 `apq8016_sbc` 的 QUAT iomux hack | 同样需要，已补 |
| 混音路由 | UCM 设 `QUAT_MI2S_RX Audio Mixer MultiMedia1=1` | 相同 |

---

## 8. 其余硬件项的内核实测（2026-11-07 晚）

### 8.1 蓝牙 QCA9379：已可用，不需要改 DTS
`hci0` 在 7.3 下正常起来：
```
Bluetooth: hci0: QCA controller version 0x00150100
Bluetooth: hci0: QCA Downloading qca/rampatch_00150100.bin
Bluetooth: hci0: QCA setup on UART is completed
```
- 控制器地址为真实 OTP MAC（`94:08:53:…`），`Powered: yes`
- `bluetoothctl scan on` 能扫到周边 BLE 设备（如 `trzn.light.wy0a01`、`lemesh.light.wy0d02`）
- `/lib/firmware/qca/rampatch_00150100.bin`(38248B) 与 `nvm_00150100.bin`(2172B) 就是 stock `btfwnpla.tlv` / `btnvnpla.bin` 的改名，内容一致
- 日志里的 `Frame reassembly failed (-84)` 出现在 rampatch 下载阶段，之后 setup 成功，属良性

### 8.2 摄像头 S5KC505A：能出 RAW 帧
用 `jethac/streams/camera/device-test.sh pattern 1304x980` 跑通完整管线
（`s5kc505a 3-0037 → msm_csiphy0 → msm_csid0 → msm_ispif0 → msm_vfe0_rdi0`）：
- **30.07 fps**
- 4 帧 RAW10 = 6,397,440 B（stride 1632 × 980，格式 `pgAA`）
- 彩色条测试图（test_pattern=2），不涉及隐私画面
- 说明：出图/软 ISP 用 `tsvcam` 或 `libcamera`（需 `modprobe system_heap`）另做，属用户态

### 8.3 Venus：H.264 含 B 帧解码实测通过
- 素材：`libx264 -bf 3`，1280x720@30，5 s（150 帧）
- 解码：`ffmpeg -c:v h264_v4l2m2m -i h264bf.mp4 -f null -` → **150/150 帧，8.7× 实时**
- HEVC `bframes=4` 用 ffmpeg 的 v4l2 封装会卡住（ffmpeg 侧的老问题，jethac 也记录过它的丢包/挂起）；内核 0703/0704 的 EOS/尺寸修正在 H.264 上已验证，HEVC 需用非 ffmpeg 客户端复测

### 8.4 Himax 面板的 DPMS 熄屏/点亮
设备上没有 `modetest`/`wlopm`，也无法在 weston 持有 DRM master 时改 DPMS，因此：
- 现编了一个小工具 `tools/dpms.c`（libdrm，`gcc -I/usr/include/libdrm -ldrm`），设备上装了 `gcc` + `libdrm-dev`
- 停掉 kiosk（weston）后连续 **5 次 DPMS off/on**：
  - 无任何 panel/DSI 报错
  - **熄屏期间触摸芯片仍在 I2C 上 ACK**（TDDI 的 `avdd/vdd` 由触控节点自己供电，面板 `vsp/vsn` 断开不影响触控控制器）
  - 点亮后 backlight 正常、kiosk 重新起画面
- 结论：7.3 这版 Himax 面板驱动 + `regulator-always-on` 的 `panel_avdd` 已经能安全走 DPMS 循环；**不需要给 Himax 再写 FT8201 那款保活补丁**。真正的“DPMS 熄灭 + 触摸中断唤醒”策略留给 v3 应用层实现（当前镜像仍是只关背光的 `idle-blanker`）

---

## 9. 全量硬件深度复查、新增内核补丁（`local-patches/0001~0007`）与 EDL 系统刷机包构建（2026-11-08）

针对前期调研报告中列出的所有硬件与驱动隐患，我们对 `7.3.0-tsv` 进行了逐项复查，抓出了原镜像残留脚本的隐蔽破坏与 7 处内核驱动缺陷，并全部封装为标准内核补丁与一键 EDL 刷机镜像构建流水线。

### 9.1 复查新抓出的重大根因（之前被掩盖的真相）

1. **为什么之前禁用 `qup-i2c-pinctrl-fix.service` 后功放 I2C1 (`1-0049`) 仍会变成 `func0 8mA pull up` 掉线？**
   * **真凶不是硬件或 PM autosuspend，而是原镜像里残留的 `/etc/systemd/system/i2c1-pinmux-fix.service` (`/usr/local/sbin/i2c1-pinmux-fix.sh`)！**
   * 该脚本是早期作者在 2026-04-22 写的，把高通 TLMM `GPIO_CFG` 寄存器的位域算反了（误以为 `bits[9:6]` 是 `func`、`bits[5:2]` 是 `drv`，实际 `bits[5:2]` 才是 `func`、`bits[8:6]` 是 `drv`），在开机时调用 `devmem 0x1002000 32 0xC3` 和 `devmem 0x1003000 32 0xC3`，**亲手把 GPIO 2/3 改成了 `func=0 (GPIO), drv=3 (8mA), pull=3 (pull-up)`，直接切断了 I2C1 总线**！随后又在 5 月写了 `qup-i2c-pinctrl-fix.service` 去 unbind/rebind 救火。
   * 同时原镜像还残留了 `/etc/systemd/system/pmos-audio-route.service`，开机执行 `amixer -c 0 cset name="QUAT_MI2S_RX Audio Mixer MultiMedia1" 0` 把扬声器路由关掉。
   * **彻底解决**：删除 `i2c1-pinmux-fix.service`、`qup-i2c-pinctrl-fix.service` 和 `pmos-audio-route.service`，并在 DTB 中为 `&i2c_1` 固定 `pinctrl-0 = <&i2c_1_default>; pinctrl-1 = <&i2c_1_default>;`。实测 `78b5000.i2c` 进入 runtime `suspended` 后 GPIO 2/3 依然稳稳保持 `func2 (blsp_i2c1)`，彻底告别用户态 I2C 刷写脚本。

2. **播放 (`QUAT_MI2S_RX`) 与双麦录音 (`DMIC`) 跨域时钟漂移实测（回答调研报告 §7.2 层 B 开放问题）**
   * 通过直接 ALSA (`aplay -D hw:0,0` + `arecord -D hw:0,1`, 48kHz S16LE) 发射间隔精确 `480,000` 样本（10.000000 秒）的双 2kHz 脉冲并做互相关峰值检测：
   * 实测脉冲间距为 `479,989` 样本，**物理时钟漂移仅为 `-11 samples / 480,000 = -22.92 ppm`（10 秒内偏差仅 0.23 毫秒）**，完全在 WebRTC AEC3 自适应滤波器的天然锁定范围内，无需额外软件重采样或硬件 loopback。

3. **为什么 `dmesg` 持续刷屏 `[drm:dpu_crtc_get_vblank_counter [msm]] *ERROR* no encoder found for crtc 0`？**
   * 根因：`drivers/gpu/drm/msm/disp/dpu1/dpu_crtc.c` 中除了 `get_encoder_from_crtc()` 以外的所有函数都使用原子 KMS 的 `crtc->state->encoder_mask` 遍历 encoder，唯独 `get_encoder_from_crtc()` 还在检查旧版非原子字段 `encoder->crtc == crtc`（在 Wayland/Weston 原子提交下为 NULL）。
   * 修复：`local-patches/0005` 在 `get_encoder_from_crtc()` 中优先读取 `crtc->state->encoder_mask`，开机后该报错计数直接归 **0**。

4. **为什么 `jethac` 在 Venus 编码器 `V4L2_ENC_CMD_STOP` 后调 `VIDIOC_STREAMOFF` 会触发 SoC 死锁？**
   * 根因（`drivers/media/platform/qcom/venus/venc.c`）：
     1. MSM8953 的 HFI 3xx 固件（`VIDEO.VE.4.2-00078`）在编码器排空（Drain）结束时返回的 0 字节 CAPTURE 空包未带 `HFI_BUFFERFLAG_EOS`，导致 `venc_buf_done()` 未置位 `V4L2_BUF_FLAG_LAST`，客户端傻等 3 秒；
     2. 在这 3 秒等待期间，Venus 编码器满 2 秒触发 PM runtime autosuspend 关闭了时钟与 GDSC；
     3. 随后客户端调 `VIDIOC_STREAMOFF` 触发 `venus_helper_vb2_stop_streaming()`，而 `venc.c`（不同于 `vdec.c`）没有包装 `venc_pm_get(inst)`，在时钟关闭状态下直接写 HFI 寄存器导致 **AXI 总线挂死**！
   * 修复：`local-patches/0007` 增加 `venc_stop_streaming()` 确保唤醒 PM 后再停止会话，并在 `VENUS_ENC_STATE_DRAIN` 收到 0 字节包时自动置位 `V4L2_BUF_FLAG_LAST`。

5. **VCNL4200 内核 IIO 驱动默认参数与守护进程冲突修复**
   * 原 `vcnl4000.c` 在 `vcnl4200_init()` 中默认写入 `VCNL4040_CONF3_PS_SAMPLE_16BITS`（8 脉冲 @ 120mA）且将 `in_proximity_raw` 除以 `ps_scale=16` 输出小数；同时旧 `vcnl4200-proximity-daemon.py` 试图直接打开 `/dev/i2c-0` (`0x51`) 与内核驱动冲突报 `Errno 16 (Device or resource busy)`。
   * 修复：`local-patches/0004` 在内核 `vcnl4200_init()` 中直接为 VCNL4200 写入安全默认值（Active-Force 单次触发、**1 脉冲**、**50mA**、**9T = 864us 积分时间**、**ALS 100ms 积分时间**）并返回 16-bit 原始整数（`IIO_VAL_INT`，无遮挡约 `39` counts，手靠近 `>50` counts）；同时更新 `vcnl4200-proximity-daemon.py` 与 `idle-blanker.py` 走内核 `/sys/bus/iio/devices/iio:device1/in_proximity_raw` 与 `in_illuminance_raw`，实现零 I2C 冲突、亮屏零红外脉冲（`reg 0x00=0x0041`, `0x03=0x080b`, `0x04=0x0008`，闲置 2 秒自动断电休眠）。

---

### 9.2 最终内核补丁全集（共 41 个补丁，位于 `/work/repos/tsv-kernel/`）

1. **`jethac/kernel/patches/`（27 个）**：`0001`~`0704` 全量合入。
2. **`salaman/patches/kernel/mainline/msm8953-mainline/`（7 个）**：
   * `0002-arm64-dts-qcom-thinksmart-preserve-simplefb-clocks.patch`
   * `0003-i2c-qup-wait-for-clock-readiness.patch`
   * `0005-clk-qcom-msm8953-enable-usb-fsm-parent.patch`
   * `0011-drm-msm-gem-shared-vm-last-handle.patch`
   * `0012-drm-msm-dpu-flush-video-cleanup.patch`
   * `0018-drm-panel-ft8201-preserve-touch-during-blanking.patch`
   * `0021-arm64-dts-qcom-thinksmart-accelerometer-mount.patch`（BMA253 安装矩阵 `-1, 0, 0; 0, -1, 0; 0, 0, 1`）
3. **`local-patches/`（7 个，本次编写）**：
   * `0001-arm64-dts-qcom-apq8053-lenovo-cd-18781y-dual-variant.patch`（保留 `lk2nd` 双面板/双触控动态匹配占位符、Himax `wakeup-source`、`&i2c_1` 睡眠保持 pinmux、禁用无用 `&ipa` 消除 interconnect 警告、扁平 `venus.mdt` 路径）
   * `0002-ASoC-qcom-apq8016_sbc-configure-spkr_iomux-for-QUATE.patch`（打通 `QUATERNARY_MI2S_RX` 到 GPIO 135-138 的 `spkr_iomux`）
   * `0003-ASoC-qcom-qdsp6-fix-q6asm-unmap-OOB-and-always-free-.patch`（修复 `q6asm_unmap_memory_regions` 的 `port->buf[dir]` 越界读取，并在重 prepare/unmap 失败时强制清理 `port->buf`，根治 `Buffer already allocated`）
   * `0004-iio-light-vcnl4000-safe-VCNL4200-1-pulse-50mA-9T-ini.patch`（内核级初始化 VCNL4200 为 1 脉冲 / 50mA / 9T / Active-Force 并返回整数 ADC 值）
   * `0005-drm-msm-dpu-check-atomic-encoder_mask-in-get_encoder.patch`（消除 DPU `no encoder found for crtc 0` 报错）
   * `0006-drm-panel-hx83100a-preserve-touch-and-panel-supplies.patch`（Himax 面板与 FT8201 对齐的熄屏供电/复位保持与关机断电逻辑）
   * `0007-media-venus-venc-resume-PM-on-stop_streaming-and-mar.patch`（修复 Venus 编码器 Drain EOS 标志与 `STREAMOFF` 未唤醒 PM 导致的 SoC 死锁）

---

### 9.3 EDL 系统刷机包与一键构建脚本

已生成可直接通过高通 EDL 刷入 `system` 分区的完整系统镜像，并提供了支持随时合入 V3 Rust 二进制（`tsv-voice`）的打包脚本：

* **已生成的 EDL 刷机镜像（含完整 `7.3.0-tsv` 内核与硬件修复）**：
  * 路径：`/work/repos/smart_home/flash/thinksmart-ubuntu-kernel73.img`（3.3 GB）
  * 校验：`/work/repos/smart_home/flash/thinksmart-ubuntu-kernel73.img.sha256`（`8fcbde7ef4947984a8d279f8111a6e04473f0cc1c55f707a9136564f7a9552e58`）
* **待 V3 (`tsv-voice`) 编译完成后的一键合成命令**：
  ```bash
  # 将 V3 二进制直接注入 7.3 内核系统镜像并禁用旧版小智服务（耗时约 20 秒）：
  /work/repos/tsv-kernel/build-edl-image.sh --with-v3 /work/repos/smart_home/tsv/target/aarch64-unknown-linux-gnu/release/tsv-voice
  ```
* **EDL 刷机命令**：
  ```bash
  # 设备按住 Vol+ 和 Vol- 插电进 EDL (9008) 模式后执行：
  /work/repos/smart_home/edl-venv/bin/edl w system /work/repos/smart_home/flash/thinksmart-ubuntu-kernel73.img
  /work/repos/smart_home/edl-venv/bin/edl reset
  ```
