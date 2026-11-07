# Lenovo ThinkSmart View (CD-18781Y) — Mainline Linux 7.3 Kernel & EDL System Image Builder

为 **联想 ThinkSmart View (`CD-18781Y` / `lenovo-cd-18781y`)** 打造的主线 **Linux 7.3 (`7.3.0-tsv`)** 硬件硬化内核补丁集与 **高通 EDL (`9008`) 刷机镜像构建工程**。

本仓库的设计哲学是：**“在内核驱动与设备树层彻底解决硬件生命周期与时序问题，消除脆弱的用户态脚本绕过（Workarounds）”**，并提供可一键打包 **V3 原生 Rust 语音终端 (`tsv-voice`)** 的完整 EDL 刷机镜像流水线。

---

## 一、 硬件支持矩阵（Mainline Linux `7.3.0-tsv`）

| 硬件模块 | 芯片 / 规格 | Linux 7.3 状态 | 驱动与内核级修复说明 |
| :--- | :--- | :--- | :--- |
| **SoC / CPU / 温控** | Qualcomm APQ8053-Lite (8× Cortex-A53) | ✅ **满血 1.80 GHz** | 修复 `cpr4pd` APM 850mV 阈值比较（`>=`），解锁 `652MHz ~ 1804.8MHz`；内置 75°C/85°C/100°C 两级热节流 |
| **硬件看门狗** | APSS Watchdog (`qcom-wdt`) | ✅ **已启用** | 内核与 systemd (`RuntimeWatchdogSec=30s`, `RebootWatchdogSec=2min`) 联动，死机自动硬重启 |
| **显示屏与背光** | 8" 800×1280 MIPI DSI + PMI8950 WLED | ✅ **双变体自适应** | 保留 `lk2nd` 面板占位符，自动适配 **Boe/Himax (`HX83100A`)** 与 **Boyi/FocalTech (`FT8201`)**；修复 DPU 原子 `encoder_mask` vblank 报错 |
| **触摸屏** | Himax `HX83100A` (`2-0048`) / FocalTech `FT8201` (`2-0038`) | ✅ **双变体 + 熄屏保活** | 双面板驱动在普通熄屏 (`unprepare`) 时保留偏置供电与释放复位，支持触摸唤醒 (`wakeup-source`) |
| **扬声器功放** | TI `TAS5782M` (10W D 类 + 内置 DSP) | ✅ **原厂腔体保护** | 主线化 `snd-soc-tas5782m` 驱动 + `apq8016_sbc` `QUAT_MI2S` `spkr_iomux` 修复 + 联想 GPL 1523 项 EQ/DRC 保护固件 + `i2c-qup` 时钟就绪等待（零用户态 `devmem`/unbind 脚本） |
| **双数字麦克风** | DMIC1 + DMIC2 阵列 (`msm8916-wcd-digital`) | ✅ **2.4MHz 同步低噪** | 按抽取器 (`DEC1/DEC2`) 独立写入 DMIC 分频，锁定原厂 `2.4MHz` 时钟；修复 `q6asm` 解映射越界与残留 `port->buf` 死锁；实测与扬声器时钟漂移仅 `-22.9 ppm` |
| **距离与环境光传感器** | Vishay `VCNL4200` (`i2c-0 @ 0x51`) | ✅ **Active-Force 单脉冲** | 内核 `vcnl4000` 驱动直接初始化为 **Active-Force 单次触发、1 脉冲、50mA、9T (`864us`) 积分** 并返回 16-bit 原始整数；亮屏自动休眠（红外灯 100% 物理关闭） |
| **重力加速度计** | Bosch `BMA253` (`iio:device0`) | ✅ **含安装矩阵** | 内置 `mount-matrix` (`-1, 0, 0; 0, -1, 0; 0, 0, 1`) |
| **前置摄像头** | Samsung `S5KC505A` (5MP, `CCI 0x37` + `CAMSS`) | ✅ **RAW10 30fps** | 逆向 `libmmcamera_s5kc505a.so` 提取完整寄存器表，支持 `2608×1960` / `1304×980` 30fps 采集与物理隐私盖 (`GPIO 87`) 检测 |
| **硬件视频编解码** | Qualcomm `Venus` (`video6` / `video7`) | ✅ **含 B 帧硬解 & 硬编** | 修复 H.264/HEVC B 帧 EOS 丢失、NV12 编码 +4K 余量、以及 `STREAMOFF` 未唤醒 PM 导致的 SoC 死锁 |
| **Wi-Fi & 蓝牙** | Qualcomm `QCA9379` (SDIO + UART) | ✅ **GTK 换密钥 0 等待** | `ath10k` 增加 `key_update_no_sec_ind` 跳过 3s 超时并重置 RX PN 重放计数；蓝牙 `hci0` 正常加载 `00150100` 固件 |
| **USB-C 接口** | `DWC3` (`172.16.42.1` USB NCM 网卡) | ✅ **已恢复工作** | DTB 固定 `dr_mode = "peripheral"` + `gcc_usb30_master_clk` `CLK_OPS_PARENT_ENABLE` |

---

## 二、 仓库目录结构

```text
.
├── kernel/
│   ├── build.sh                 # 自动拉取 msm8953-mainline 7.3、打齐 41 个补丁并编译内核与模块
│   ├── install-to-device.sh     # 通过 SSH 在线热更新内核/DTB/模块/Overlay（保留 *.619 一键回滚）
│   ├── check-device.sh          # 启动后全硬件状态自动体检脚本
│   ├── config/
│   │   └── lenovo-cd-18781y.config
│   └── patches/                 # 41 个按序编号的内核补丁：
│       ├── 0001..0704-*.patch   #   [27] jethac/lenovo-thinksmart-view 基线补丁集
│       ├── 0801..0807-*.patch   #   [ 7] salaman/tsv-lineage 精选补丁集 (i2c-qup, usb-clk, dpu, panel, accel)
│       └── 0901..0907-*.patch   #   [ 7] 本项目针对双变体硬件与驱动深坑编写的内核补丁
├── firmware/
│   ├── fetch-tas5782m-tuning.sh # 从联想官方 GPL 源码包提取并校验 TAS5782M 1523 项腔体保护固件
│   └── tas5782m-dsp-fw.py
├── overlay/                     # 注入根文件系统的最小化硬件配置（udev 规则、watchdog、zram、IIO 脚本）
├── image/
│   └── build-edl-image.sh       # 构建可在 EDL (9008) 模式直接刷入 system 分区的完整镜像（支持 --with-v3）
├── tools/
│   └── dpms.c                   # DRM/KMS 屏幕 DPMS 状态切换与测试小工具
└── docs/                        # 硬件逆向调研报告、内核 7.3 移植排障记录与 V2/V3 架构方案
```

---

## 三、 快速开始

### 1. 编译 Linux `7.3.0-tsv` 内核与模块

主机需安装 `clang-19`、`lld-19`、`llvm-19`、`bc`、`bison`、`flex`、`device-tree-compiler`、`libelf-dev`、`libssl-dev`：

```bash
./kernel/build.sh
```

编译产物位于：
* `kernel/build-7.3/arch/arm64/boot/Image.gz`
* `kernel/build-7.3/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb`
* `kernel/stage/modules.tar`

### 2. 构建可在 EDL 模式刷机的系统镜像包

将基础 Ubuntu 镜像放在 `flash/thinksmart-ubuntu-20261101.img`，执行：

```bash
# 构建包含 7.3.0-tsv 内核与全套硬件修复的 EDL 系统镜像：
./image/build-edl-image.sh

# 当 V3 版 Rust 语音终端 (tsv-voice) 编译完成后，一键将其合入刷机包（并自动停用旧版小智服务）：
./image/build-edl-image.sh --with-v3 tsv/target/aarch64-unknown-linux-gnu/release/tsv-voice --compress
```

生成的刷机包位于 `flash/thinksmart-ubuntu-kernel73.img`（以及 `.img.sha256`）。

### 3. 在 EDL (9008) 模式下刷入设备

1. 拔掉设备电源线，用 USB-A 转 USB-C 数据线连接电脑；
2. **同时按住音量+ 和 音量-** 不放，插上电源线，等待约 5 秒后松开（`lsusb` 出现 `05c6:9008`）；
3. 刷入 `system` 分区并重启：

```bash
./edl-venv/bin/edl w system flash/thinksmart-ubuntu-kernel73.img
./edl-venv/bin/edl reset
```

---

## 四、 致谢与开源许可

* 构建脚本、Overlay 工具与文档采用 **MIT License**；`kernel/patches/` 下的 Linux 内核补丁遵循 **GPL-2.0-only**。
* 特别致谢社区先驱项目：
  * [FelixKa](https://gitlab.postmarketos.org/postmarketOS/pmaports)（postmarketOS `lenovo-cd-18781y` 与早期 TAS5782M 驱动）
  * [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart)（Ubuntu 24.04 移植、GPT 分区方案与 QUAT MI2S 路由发现）
  * [justhalfbit/thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image)（Ubuntu 语音终端镜像、Mesa a5xx 修复与 DMIC 抽取器时钟问题发现）
  * [jethac/lenovo-thinksmart-view](https://github.com/jethac/lenovo-thinksmart-view)（Linux 7.3 主线化补丁集与 S5KC505A 摄像头逆向驱动）
  * [salaman/tsv-lineage](https://github.com/salaman/tsv-lineage)（QUP I2C 时钟就绪、USB FSM 父时钟、DPU flush 与面板保活补丁）
