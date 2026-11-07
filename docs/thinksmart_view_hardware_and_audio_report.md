# Lenovo ThinkSmart View (CD-18781Y) 硬件驱动、Linux 移植逆向与多麦克风远场语音技术调研报告

> **调研日期**：2026-11-07（已增补内核级底层硬件驱动改造与逆向打补丁方案）  
> **适用机型**：Lenovo ThinkSmart View (`CD-18781Y` / 代号 `starfire` / `lenovo-cd-18781y`)  
> **关联仓库**：`rickx/ubuntu-thinksmart`、`justhalfbit/thinksmart-ubuntu-image`、`jethac/lenovo-thinksmart-view`、`salaman/tsv-lineage`

---

## 一、 硬件底座与原版 Teams 系统支持情况

### 1.1 核心硬件架构清单
Lenovo ThinkSmart View 本质上是一台无电池、DC 20V/1.5A 供电的高通方案桌面智能屏，其内部真实硬件配置如下：

| 模块 | 硬件型号 / 规格 | 总线接口 / 连接方式 | 备注 |
| :--- | :--- | :--- | :--- |
| **SoC** | Qualcomm **APQ8053-Lite** (Snapdragon 624 / 无基带版骁龙 625) | 8× Cortex-A53 @ 1.8GHz + Adreno 506 GPU | 包含 Hexagon ADSP (`ADSP.8976.2.8.1`) 与 Venus 1080p 视频编解码引擎 |
| **内存与存储** | 2GB LPDDR3 + 8GB eMMC | 单通道 32-bit LPDDR3 | 去除基带保留内存后，主线 Linux 可用内存约 1.99GB |
| **电源管理 (PMIC)** | PM8953 + PMI8950 | SPMI | PMI8950 提供 4 路 WLED 背光驱动及 LAB/IBB 面板供电 |
| **扬声器功放** | **TI TAS5782M** (带内置 DSP 的 D 类数字功放) | 控制：`I2C1` (`0x49`, GPIO 2/3)<br>音频：`QUATERNARY_MI2S_RX` (GPIO 135-138) | 驱动 1.75 英寸 10W 全频喇叭 + 2 个被动辐射器，20V PVDD 供电 (GPIO 68) |
| **麦克风阵列** | **双数字麦克风 (DMIC1 & DMIC2)** | 直连 SoC 内部 `msm8916-wcd-digital` (LPASS Codec) | 经由 `TERT_MI2S_TX` 采集，机身顶部对称排布 |
| **显示屏与触摸** | 8 英寸 800×1280 IPS (MIPI DSI)，存在两套二供混用：<br>① Boe 面板 + **Himax HX83100A** (`3-0048`)<br>② Boyi 面板 + **FocalTech FT8201** (`3-0038`) | 显示：MIPI DSI<br>触摸：`I2C3` (`0x78b7000`) | 均支持 10 点触控，FT8201 为 TDDI（触控与显示驱动集成）芯片 |
| **距离与环境光** | **Vishay VCNL4200** (ALS + Proximity + IRED) | `i2c-0` (`0x51`, GPIO 518/519 Bit-bang 模拟 I2C) | 外置 PMOS FET 驱动大功率红外发射管 (IRED) |
| **重力加速度计** | **Bosch BMA253 / BMA255** | GPIO 6/7 Bit-bang 模拟 I2C | 用于横竖屏自动旋转与机身移动/敲击检测 |
| **前置摄像头** | **Samsung S5KC505A** (QTech 模组, 5MP 广角) | 控制：CCI Master 0 (`0x37`)<br>数据：2-lane MIPI CSI-2 (CSIPHY0 → CSID0 → VFE0) | 带物理隐私遮挡滑块 (`GPIO 87`, `SW_CAMERA_LENS_COVER`) |
| **无线网卡** | **Qualcomm QCA9379 hw1.0** | Wi-Fi：SDIO (`ath10k_sdio`)<br>蓝牙：UART HCI (`BT 4.2`) | 2x2 MIMO 802.11ac 双频 Wi-Fi |

### 1.2 原版 Teams 系统是否完美驱动？
**是的，原版系统（基于 AOSP 8.1 / Linux 3.18 32-bit）100% 完美驱动了所有硬件，且包含深度的声学和光学调校：**
1. **音频与远场算法**：原厂通过高通专有音频栈（QDSP6 + ACDB 声学配置数据库）在 Hexagon ADSP 上运行了高通 **Fluence** 双麦波束成形（Beamforming）、声学回声消除（AEC）和背景降噪（NS），同时将 TI TAS5782M 功放内部的 1523 组 EQ/DRC 腔体调音参数固化在驱动里，以满足微软 Teams 会议认证。
2. **传感器子系统**：距离/环境光（VCNL4200）和加速度计（BMA253）在原厂由高通 ADSP 内的 **SSC（Sensors Subsystem）** 接管，支持低功耗接近唤醒与自动旋转。
3. **相机与 3A 调校**：由高通闭源 `mm-camera` 架构驱动，具备针对 S5KC505A 镜头的自动曝光（AE）、自动白平衡（AWB）和 Chromatix 色彩校准文件。

---

## 二、 Mainline Linux 各硬件驱动现状与逆向成果

通过刷入二级引导 `lk2nd`，目前社区已在 Mainline Linux（`6.19.5` 至 `7.3`）上跑通了 postmarketOS、Ubuntu 24.04 及 Arch Linux ARM。各硬件具体支持状态如下：

### 2.1 扬声器（Speaker —— TI TAS5782M）：已完美驱动
* **驱动机制**：主线内核自带的 `tas5805m` 与 `tas5782m` 寄存器定义冲突（如 `0x03` 寄存器在 5805M 上是播放控制，在 5782M 上是静音控制）。社区（FelixKa / rickx / jethac）编写了专用 ASoC 驱动 `snd-soc-tas5782m`。
* **原厂 DSP 调音固件提取**：从联想 GPL 开源内核头文件 `tas5782m.h` 的 `tas5782m_init_sequence[]` 中提取出 1523 对寄存器配置（TI PurePath Console 3 导出的腔体分频、EQ、DRC 限幅参数），转换为 `/lib/firmware/tas5728m_dsp_lenovo_cd-18781y.bin`（约 3044 字节）。在音频流启动且 I2S BCLK 时钟稳定后写入功放 Book `0x8C`，音质与原厂完全一致，且能保护喇叭不在满功率下烧毁。
* **关键避坑点**：
  1. **强制 `S16LE` 格式**：高通主线 `q6asm` 前端对 `S24_LE` 存在位移缩放 Bug（音量小 48dB，近乎无声），且拒绝 `S32_LE`，必须在 WirePlumber 中强制锁定 `S16LE` @ 48kHz。
  2. **I2C1 QUP 休眠掉线修复**：主线 `i2c_qup` 驱动在 PM runtime autosuspend 后会将 GPIO 2/3 重置回普通 GPIO 模式（func0），导致功放 I2C 通信报 `-EIO`。需通过 `qup-i2c-pinctrl-fix.service` 重新绑定驱动并设置 `power/control = on`。
  3. **忽略 SCLK 错误**：初始化时必须写入 `0x25 = 0x18`（`IGNORE_SCLK | IGNORE_SCLK_HALT`），防止功放因 BCLK 锁定微小延迟而锁死在 Sleep 模式。

### 2.2 麦克风（Microphones —— 双 DMIC）：已完美驱动
* **驱动机制**：通过 ALSA UCM2 配置 `DEC1 MUX = DMIC1`、`DEC2 MUX = DMIC2` 以及 `MultiMedia2 Mixer TERT_MI2S_TX = 1`，并将数字音量 `TX1/TX2 Digital Volume` 设为 `108~115`，即可进行双声道立体声录音。
* **DMIC1 白噪音 Bug 与修复**：主线 `msm8916-wcd-digital.c` 默认将 DMIC 时钟设为 3.2MHz（MCLK/3），且抽取器（Decimator）时钟寄存器在交叉路由时存在未同步更新的 Bug，导致左声道（DMIC1）输出满幅白噪音。`justhalfbit` 与 `jethac` 通过补丁新增 `qcom,dmic-sample-rate = <2400000>` 设备树属性，将时钟降回原厂的 **2.4MHz（MCLK/4）** 并修正抽取器时钟写入逻辑，使两颗麦克风底噪均稳定在 -81dBFS 左右。
* **物理静音开关注意（2026-11-06 最新修正）**：早期部分分析误以为麦克风静音滑块未贴片，实测证实机身左侧上方的麦克风静音滑块连接到 **`GPIO 86`（`SW_MICROPHONE_INSERT`，`GPIO_ACTIVE_LOW`）**，且同时是一个**硬件级静音开关**——当滑块推到顶部时，`GPIO 86` 为高电平，两路 DMIC 在硬件层面直接输出全零数字静音（Digital Silence），任何软件均无法强行录音；滑块推到底部时 `GPIO 86` 为低电平，麦克风恢复拾音。

### 2.3 屏幕、背光与触摸（Display & Touch）：已完美驱动
* **二供自动适配**：原厂 `aboot` 会在 kernel cmdline 中传递屏幕型号，`lk2nd` 会解析该参数并动态修改主线 DTB，自动匹配启用 Boe/Himax (`himax_hx83112b`) 或 Boyi/FocalTech (`edt-ft5x06`) 驱动。
* **熄屏死锁大坑（DRM Off）**：在主线 Linux 下，若合成器（如 KWin/Weston）触发 DPMS 将 DSI 接口设为 `DRM Off`（或背光写 `0` 触发 DPMS），DSI 面板和 TDDI 触摸控制器会掉电并进入不可恢复的死锁状态（除非重启合成器）。
* **正确熄屏方案**：禁用桌面 DPMS 超时，通过用户态守护进程直接控制背光（将 `/sys/class/backlight/backlight/brightness` 设为 `10`——因 WLED 硬件阈值在 1200 以下即物理全黑，或者设置 `bl_power=4` 关闭 WLED 模块但保持 DSI 通路激活），从而实现安全熄屏与秒级触控唤醒。

### 2.4 距离传感器与红外传感器（VCNL4200）：已完美驱动（需防红外常亮）
* **重大硬件隐患**：Linux 主线自带的 `vcnl4000` 驱动兼容 VCNL4200，但**切勿直接加载未修改的上游驱动**。上游驱动默认开启连续测量模式，会导致外置 PMOS 驱动的大功率红外发射管（IRED）以高占空比持续发光发热。
* **两种安全驱动方案**：
  1. **用户态 I2C 轮询守护进程（`rickx` / `justhalfbit` 方案）**：禁用内核驱动，由 `vcnl4200-proximity-daemon.py` 通过 `smbus2` 直接操作 `/dev/i2c-0` (`0x51`)。仅当屏幕熄灭时开启传感器（2Hz 轮询 `PS_DATA` 寄存器 `0x08`），检测到手靠近（约 15~30cm，读数超过阈值 `50`）立即写背光唤醒屏幕；屏幕点亮期间立刻关闭红外发射管（实现亮屏零功耗）。
  2. **内核单次触发补丁（`jethac` 0601/0602 补丁方案）**：修改内核 `vcnl4000.c` 为 **Active Force Mode（按需单次触发）**，仅在熄屏读取时触发单脉冲（384μs，占空比 < 1/1300），若应用崩溃则硬件自动保持关闭。

### 2.5 摄像头（Samsung S5KC505A）：已完成逆向并成功出图/录像
* **逆向突破**：社区对原厂 `vendor.img` 中的 `libmmcamera_s5kc505a.so` 进行逆向，从 `sensor_open_lib()` 返回的 `sensor_lib_t` 结构体中完整提取出：
  * 真实 7-bit CCI/I2C 地址为 **`0x37`**（Chip ID `0x5034`）；
  * 严格的上电时序：`pm8953_l17` (2.85V VANA + GPIO 119) → `pm8953_l2` (1.2V VDIG + GPIO 118) → `pm8953_l6` (1.8V VIO) → 24MHz MCLK (GPIO 26) → Reset/Standby (GPIO 40/39)；
  * 45 条寄存器初始化序列与 5 组分辨率模式表（最高支持 `2608×1960 @ 30fps` RAW10 GRBG 输出）。
* **当前进展**：在 `jethac/lenovo-thinksmart-view` (`streams/camera/`) 中，主线 V4L2 驱动 `s5kc505a.c`（补丁 `0401-0404`）已通过高通 CAMSS (`CSIPHY0 → CSID0 → ISPIF0 → VFE0 RDI0`) 跑通，并配套开发了轻量级 C 库 `tsvcam`（仅依赖 `libturbojpeg`，内置软 ISP 去马赛克、50/60Hz 防闪烁 AE、灰世界 AWB、90° 顺时针旋转及 Venus H.264 硬件编码 MP4），同时支持通过 `GPIO 87` (`SW_CAMERA_LENS_COVER`) 实时检测物理镜头盖状态。`rickx/justhalfbit` 的 6.19 内核分支目前尚未合入该驱动，但可直接移植这 4 个补丁。

---

## 三、 衍生项目对比与 `justhalfbit` Ubuntu 底座的隐藏坑点

### 3.1 关于 `salaman/tsv-lineage` 项目
* **项目性质**：这不是早期的 Android 8.1 (`LineageOS 15.1`)，而是基于 **主线内核 `msm8953-mainline Linux 7.3`** 构建的 **`LineageOS 24.0` (Android 17)**。
* **真实支持度**：它复用了 Linux 社区的驱动成果（显示屏、触控、功放、麦克风、传感器、Venus 视频硬解均工作），但**摄像头（Camera）和整机深度休眠（Full system suspend）依然是 `Not working`**。
* **评估结论**：Android 17 系统本身对 2GB 内存压力极大，且本地编译需要同步完整的 AOSP 源码树（**要求 350GB 空闲磁盘空间**）。对于语音助手或智能家居中控场景，继续使用轻量化的 **`justhalfbit/thinksmart-ubuntu-image`（移除 Plasma 桌面后的 Ubuntu 24.04）** 远比刷主线 Android 17 实用。

### 3.2 `justhalfbit` 在 Ubuntu 底座上发现并填平的深坑（二次开发必读）
深入分析 `justhalfbit/thinksmart-ubuntu-image` 的源码后，可以发现作者为了解决长期运行的稳定性问题，处理了以下极其隐蔽的底层陷阱：

1. **QDSP6 录音通路“二次 Prepare 必死”与声卡锁死陷阱**
   * **根因**：在 `6.19.5` 内核上，高通 `q6asm` 录音前端在每次打开后**只能承受一次 `snd_pcm_prepare`**。如果让 PipeWire 直接管理麦克风，或者任何应用（如 PortAudio）重新打开/因缓冲区欠载（xrun）触发第二次 prepare，DSP 就会报 `q6asm CMD 10bcd / Buffer already allocated` 超时崩溃，且**连带导致扬声器彻底无声**，唯有重启能恢复。
   * **当前机制**：作者在 `99-cd18781y-alsa.lua` 中禁用了 PipeWire 对硬件录音节点的访问（`node.disabled = true`），并编写了 `/usr/local/bin/thinksmart-mic` 服务。该服务在开机扬声器就绪后，启动**唯一一个常驻的 `arecord -D hw:cd18781y,1` 进程**永久持有声卡，再通过非阻塞 FIFO 管道将数据桥接为 PipeWire 虚拟麦克风源（单声道 `thinksmart_mic` 和立体声 `thinksmart_mic_stereo`）。
   * **开发禁忌**：**严禁任何自定义脚本或程序直接通过 ALSA 访问 `hw:0,0` 或 `hw:0,1`**，所有音频读写必须走 PipeWire！

2. **Adreno 506 GPU 渲染 WebKit 时的三类死锁与白屏陷阱**
   * **根因**：Ubuntu 24.04 原版 Mesa (`25.2.8`) 的 `freedreno` (a5xx) 驱动在运行 Weston + WebKitGTK 时存在三个 Bug：
     1. 深度/模板缓冲区 MSAA 采样被重复计算两次，导致 GMEM 分块（binning）陷入死循环；
     2. WebKit 合成线程与绘制线程并发调用 GL 时，32 个 batch 槽位占满后在 `alloc_batch_locked()` 中活锁（Livelock）；
     3. 约 1/5 的开机概率在启动 20 秒后触发 GPU 硬件异常（`CP | opcode error` / `hangcheck recover`），导致画面定格在首帧。
   * **当前机制**：作者构建了打满 4 个补丁的定制版 **`mesa 25.2.8+thinksmart4`**，通过 `apt-mark hold` 锁死了 41 个关键包（见 `image/held-packages.txt`），并编写了 `gpu-watchdog.py` 监控内核日志，一旦发现 GPU fault 自动在 5 秒后重启前端 UI。

3. **刷机后 USB 网络失效与无电源键断电损坏 `/boot` 陷阱**
   * **USB 网络失效**：Bootstrap 阶段 USB 网络可用，但正式 Ubuntu 镜像启动后，USB 控制器未能自动切换到 `peripheral`（设备模式），主机无法枚举到 USB 网卡，因此**日常调试只能通过 Wi-Fi SSH 进行**。
   * **Wi-Fi 省电丢 DHCP**：QCA9379 开启省电模式会漏收 DHCP 回复导致开机几分钟拿不到 IP，已通过 `/etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf` 强制关闭省电。
   * **直接拔电进 Emergency Mode**：设备无电池、无电源键，若未执行 `sudo systemctl halt`（等待屏幕变黑 10 秒）就直接拔电源，极易导致 ext2 格式的 `/boot` 分区产生文件系统错误，下次开机因 `systemd-fsck` 写修复失败而卡在紧急模式。

---

## 四、 逆向原厂系统打补丁的方法论与本地编译成本

### 4.1 如何利用原厂 Teams 系统逆向打补丁？
当主线驱动遇到问题时，有两条成熟的逆向路径：
1. **对照联想开源的 Android 3.18 内核源码（`lenovo_cd-18781y.201218.2018_opensource.tar.gz`）**：
   * 直接查阅 `arch/arm/boot/dts/qcom/apq8053-lite-dragon-v2.0.dtsi` 获取准确的 GPIO 编号、有效电平、LDO 供电电压、I2C 地址和时钟频率（如 DMIC 2.4MHz 时钟即由此查出）。
   * 直接提取驱动头文件中的寄存器初始化序列（如功放 `tas5782m.h`）。
2. **逆向原厂 `vendor.img` 中的 32 位 ARM `.so` 二进制库**：
   * 对于摄像头、传感器校准等位于用户态 HAL 的模块，使用 Ghidra / IDA 分析 `/vendor/lib/libmmcamera_*.so`。由于高通 HAL 采用表驱动架构（如导出符号 `sensor_open_lib` 直接返回静态结构体指针），只需按结构体偏移编写 Python 脚本即可无损提取所有寄存器表与时序。

### 4.2 本地编译 `justhalfbit` Ubuntu 系统的资源与时间消耗
与需要 350GB 磁盘的 AOSP 不同，`justhalfbit/thinksmart-ubuntu-image` 采用 **Docker 容器化 + 模块化按需构建**，对本地电脑要求很低：

* **推荐主机配置**：
  * **CPU**：任意现代 4~8 核 x86_64 Linux / WSL2，或 Apple Silicon Mac（M 系列芯片原生跑 ARM64 容器最快）。
  * **内存**：最低 **8GB**，推荐 **16GB**（打包脚本中 `xz -T4 -9` 压缩阶段固定占用约 2.7GB 内存）。
  * **磁盘空间**：仅需 **25GB ~ 40GB** 空闲空间（若保留 7.8GB 原厂全盘 eMMC 备份，建议预留 50GB）。

* **各环节编译耗时明细**：

| 构建任务 | 执行脚本 | 适用场景 | 磁盘占用 | 预计耗时 |
| :--- | :--- | :--- | :--- | :--- |
| **1. 单独编译内核模块 (`.ko`) 与设备树 (`.dtb`)** | `codec-dmic/build.sh` | 修改音频、传感器或移植摄像头驱动（Out-of-tree 编译，**最常用**） | ~2 GB | **10 ~ 30 秒** |
| **2. 完整编译 Linux 6.19.5 内核** | `kernel/build.sh` | 修改内核 `.config` 或合入核心子系统补丁（使用 Alpine + Clang 21 容器） | ~6 GB | **5 ~ 12 分钟** |
| **3. 重新编译定制版 Mesa 图形包 (`.deb`)** | `mesa/build-mesa.sh` | 一般无需重编（直接用现有包）；仅在修改 GPU 驱动时需要 | ~8 GB | ARM64 主机：**8~15 分钟**<br>x86 跨架构模拟：**30~50 分钟** |
| **4. 抓取设备快照并打包生成 `.img.xz` 刷机镜像** | `image/pull-from-device.sh` + `image/build-image.sh` | 在真机调好软件后，自动脱敏隐私数据、校验驱动 MD5、免挂载生成 ext2/ext4 分区镜像并压缩 | ~15 GB | **3 ~ 6 分钟** |

---

## 五、 智能音箱多麦克风远场收音（AFE）架构与落地指南

现代智能音箱要在播放音乐/TTS 的同时实现远场（3~5 米）唤醒与识别，核心依赖 **音频前端信号处理流水线（Audio Front-End, AFE）**：

### 5.1 标准多麦克风信号处理流水线
```text
[双路/多路麦克风 DMIC] ──► 1. 多通道回声消除 (M-AEC) ◄── [扬声器播放参考信号 Loopback]
                             │
                             ▼
                       2. 声源定位 (DOA: GCC-PHAT) & 自适应波束成形 (Beamforming: MVDR/GSC)
                             │
                             ▼
                       3. 去混响 (Dereverberation: WPE)
                             │
                             ▼
                       4. 背景噪声抑制 (NS: 传统稳态滤波 + 神经网络非稳态降噪 RNNoise/GTCRN)
                             │
                             ▼
                       5. 自动增益控制 (AGC) ──► 干净单声道语音流 ──► 本地唤醒(KWS) & 语音识别(ASR)
```

1. **声学回声消除 (AEC)**：
   * **核心前提**：播放参考流（Reference）必须与麦克风采集流保持严格的时间对齐（延迟恒定、无时钟漂移）。
   * **双层架构**：先通过线性自适应滤波器（NLMS / MDF）消除 20~30dB 的直接路径与房间线性反射回声；再通过非线性处理（NLP / AES）压制小体积大功率喇叭（如 TSV 的 10W 扬声器）产生的谐波失真和外壳共振残余回声。
2. **波束成形 (Beamforming) 与远场拾音**：
   * 利用声波到达不同麦克风的微秒级时间差（TDOA），通过 **GCC-PHAT** 估计说话人方向（DOA）。
   * 采用 **MVDR（最小方差无失真响应）** 算法，在说话人方向形成拾音主瓣（同相增强），同时在侧向点声源干扰方向动态生成空间零陷（Null Steering，异相抵消）。
3. **背景音过滤 (NS) 的工程权衡**：
   * 传统谱减法/维纳滤波适合消除空调、风扇等稳态噪声且不破坏语音相位；深度学习降噪（如 RNNoise、DeepFilterNet）擅长压制敲击、关门等突发噪声，但容易引入频谱伪影（Artifacts）导致未针对性训练的 ASR 模型识别率下降。因此对 ASR 链路，轻度降噪配合波束成形往往优于激进的非线性降噪。

### 5.2 在 TSV (Ubuntu 24.04) 上的演进优化建议
目前 `xiaozhi-thinksmart-client` 仅使用了右声道单麦（`thinksmart_mic`）配合应用层 `WebRTC APM` 做单通道回声消除。既然底层 `codec-dmic` 补丁已经修好了左声道（DMIC1），并且 `thinksmart-mic` 服务已经暴露了双声道虚拟源 **`thinksmart_mic_stereo`**，后续可按以下两步升级远场能力：

1. **启用双麦立体声输入**：将客户端采集源从单声道 `thinksmart_mic` 切换至双声道 `thinksmart_mic_stereo`（左声道 DMIC1，右声道 DMIC2）。
2. **启用双通道 WebRTC APM / PipeWire `module-echo-cancel`**：利用双通道输入开启 WebRTC AudioProcessing 的多通道 AEC 与双麦定向波束成形（或直接配置 PipeWire 的 `libspa-aec-webrtc` 滤镜链），在不增加多少 A53 CPU 负担的前提下，显著提升斜向噪声抑制能力与大音量播报下的语音打断（Barge-in）成功率。

---

## 六、 “去软件 Daemon 化”：底层内核驱动级彻底修复与逆向补丁全案（2026-11-07 更新）

针对 **“底层系统应通过内核驱动与硬件机制本身解决硬件问题，而非依赖用户态 Python 守护进程绕过”** 的设计思想，我们对 GitHub 上近期（2026 年 10 月底至 11 月初）`jethac/lenovo-thinksmart-view` 和 `salaman/tsv-lineage` 两大仓库的内核补丁集进行了地毯式排查。

事实证明，原 `rickx` 和 `justhalfbit` 镜像中使用的几乎所有用户态妥协方案（如 `qup-i2c-pinctrl-fix.service`、`vcnl4200-proximity-daemon.py`、`idle-blanker.py` 防 DRM Off 死锁、`thinksmart-mic` 常驻管道、强行吞掉 `-ETIMEDOUT` 的 Wi-Fi 补丁等），**均已通过逆向高通/联想原厂驱动找到了真正的硬件根因，并有了对应的内核级 Patch！**

### 6.1 现有用户态软件 Workaround vs. 最新内核级硬件 Patch 对照表

| 硬件问题 | 旧方案（`rickx` / `justhalfbit` 软件绕过） | 真正的硬件/固件根因（逆向高通/联想驱动所得） | 最新内核级驱动 Patch 方案（零守护进程） |
| :--- | :--- | :--- | :--- |
| **1. 屏幕 DPMS 休眠后触控死锁、无法唤醒** | 禁用 DPMS，写 `idle-blanker.py` + `screen-wake-daemon.py` 把背光设为 `10` 假装关屏 | FT8201 是 **TDDI（触控与显示同晶圆）**。主线面板驱动在 `unprepare` 时拉低了共享的 Reset 引脚（GPIO 61/64）并关闭了面板偏置电源 `VSP/VSN (LAB/IBB)`，导致芯片内的触控部分断电死掉；且缺少 GPIO 100 (`avdd`) 控制。此外 DPU 视频编码器在 disable 时未清除上一帧残留的 SSPP flush 位。 | **① `0018-drm-panel-ft8201-preserve-touch-during-blanking.patch`** (`salaman`)：在面板 `unprepare`（普通熄屏）期间发送 DCS 睡眠指令，但**保持 VSP/VSN 供电与 Reset 释放状态**（仅在关机/卸载模块时断电），让硬件原生支持 DRM Off 熄屏与单击中断唤醒 (`wakeup-source`)。<br>**② `0012-drm-msm-dpu-flush-video-cleanup.patch`** (`salaman`)：在 `dpu_encoder_phys_vid_disable` 中调用 `clear_pending_flush` 防止 DPU 状态机卡死。 |
| **2. VCNL4200 距离传感器红外灯常亮过热** | 在 DT 中禁用设备，写 `vcnl4200-proximity-daemon.py` 通过 `/dev/i2c-0` 轮询寄存器 | 主线 `vcnl4000.c` 初始化时默认开启连续自主测量模式（Autonomous mode），且 DT 中将 `vio-supply` 错写成了 `vddio-supply`，中断极性也写反成了 `RISING`。 | **`0601-iio-light-vcnl4000-measure-vcnl4200-proximity-in-active-force-mode.patch` + `0602` (`jethac` / `salaman 0014`)**：在内核驱动中启用 VCNL4200 硬件的 **Active Force Mode (`VCNL4200_PS_AF | VCNL4200_PS_TRIG`)**，仅在读取 IIO 节点时由硬件发射单次 384μs 红外脉冲，配合 `runtime_pm` 自动休眠，彻底砍掉用户态 I2C 轮询脚本。 |
| **3. 功放 I2C1 总线报错 `-EIO` 掉线** | 写 `qup-i2c-pinctrl-fix.service` 在开机时 unbind/rebind 驱动并锁死 `power/control=on` | 逆向高通原厂 `i2c-qup.c` 发现：主线 QUP v2 在多子消息切换 `QUP_PAUSE_STATE` 前，只检查了 `OUTPUT_SERVICE` 而未等待 TX FIFO 排空及 I2C 时钟线进入 `BUSIDLE` 或 `FORCED_LOW` 状态，导致总线状态机竞争锁死。 | **`0003-i2c-qup-wait-for-clock-readiness.patch`** (`salaman`)：将高通原厂驱动的 `qup_i2c_poll_clock_ready()` 移植回主线，在暂停 v2 传输前轮询 `I2C_STATUS_CLK_STATE_MASK` 和 `QUP_OUT_NOT_EMPTY`，超时则触发 `QUP_SW_RESET`。 |
| **4. 功放 TAS5782M 杂音、PDN 极性与调音** | 外部编译 `snd-soc-tas5782m-dbg.ko`，错误配置 GPIO 44 为 PDN，挂在 `aux-devices` 下 | 对照联想 GPL `tas5782m.c` 与实测发现：GPIO 44 根本不是 PDN（原厂从不驱动它），GPIO 0/45 也未使用，且原 DT 错误地把功放同时挂在了不存在的模拟耳机 `HPH_R` 路由上。 | **`0301~0303` (`jethac`)**：标准主线化 `snd-soc-tas5782m` 驱动，移除错误的 GPIO 44/0/45 和 `HPH_R` 路由，在首次 unmute（SCLK 稳定 10~15ms 后）写入 1523 项联想腔体保护参数，音量上限硬件锁死在 0dB（防止越过 DSP 限幅器烧喇叭）。 |
| **5. QCA9379 Wi-Fi 组密钥重协商 (GTK Rekey) 断网与漫游卡顿 6 秒** | 二进制/源码粗暴吞掉 `ath10k_set_key` 的 `-ETIMEDOUT` 错误（每次换密钥仍会卡死主线程 3~6 秒，且导致包序号 PN 重放校验丢包） | QCA9379 SDIO 固件 (`WLAN.NPL.1.6-00163`) 仅在首次关联时发送 `HTT_T2H_MSG_TYPE_SEC_IND` 安全确认消息，在更新组密钥（GTK Rekey）和删除密钥（漫游）时**根本不发该消息**。原粗暴吞超时不仅白等 3 秒，还会因为没重置 `tids_last_pn` 导致新密钥下的组播包被当成重放攻击全部丢弃！ | **`0101-wifi-ath10k-don-t-wait-for-security-indications-QCA9379-SDIO-does-not-send.patch`** (`jethac` / `salaman 0020`)：为 QCA9379 SDIO 增加 `key_update_no_sec_ind` 硬件特性位，在 GTK 更新和删除密钥时**直接跳过 3 秒等待**，并同步在内核中执行 `ath10k_mac_reset_rx_pn()` 重置接收端重放计数器。 |
| **6. 刷机后正式系统 USB 网络/ADB 无法识别** | 只能放弃 USB 线，全部走 Wi-Fi | 两个底层原因：<br>① 主线 `&usb3` 节点未设置 `dr_mode = "peripheral"`（由于主板无 Type-C CC Rd 电阻，默认 OTG 模式无法检测角色）；<br>② `gcc-msm8953.c` 中 `gcc_usb30_master_clk` 缺少 `CLK_OPS_PARENT_ENABLE` 标志，内核清理未用时钟时父时钟未开启导致 USB 状态机卡死。 | **① `0002` (`jethac`)**：在 DTS 中将 `&usb3` 明确设为 `dr_mode = "peripheral"`。<br>**② `0005-clk-qcom-msm8953-enable-usb-fsm-parent.patch`** (`salaman`)：为 `gcc_usb30_master_clk` 加上 `CLK_OPS_PARENT_ENABLE`。 |
| **7. QDSP6 录音二次 Prepare 报 `Buffer already allocated` 锁死 DSP** | 禁用 PipeWire 录音，写 `thinksmart-mic` 用常驻 `arecord` + FIFO 管道绕过 | 检查主线 `sound/soc/qcom/qdsp6/q6asm.c` 发现：当 `q6asm_unmap_memory_regions` 超时失败时，内核**没有释放 `port->buf`**；下次 `q6asm_map_memory_regions` 看到 `port->buf` 非空，打印 `Buffer already allocated` 却**错误地返回了 `0`（成功）**，导致后续流在脏内存映射上操作进而锁死整个 ADSP！ | **内核 `q6asm.c` 修复 + Reopen 策略**：<br>① 修改 `q6asm_unmap_memory_regions` 无论 DSP 返回什么都强制清理本地 `port->buf` 链表；<br>② 经 `jethac` 在 7.3 内核实测，每次切换参数或 xrun 恢复时直接 `close + open`（耗时仅 99ms）可分配全新的 `q6asm` 会话，完全无需常驻 `arecord` + FIFO 管道。 |
| **8. CPU 被锁在 1.23GHz 无法跑满 1.8GHz 及高温死机** | 无（任由降频或无温控运行） | 逆向高通 `cpr3-regulator.c` 发现：主线 `cpr4pd.c` 在切换阵列电源多路复用器（APM）时写的是 `uv > apm_thr_uv` (850mV)，而原厂是 `>=`。TSV 的 1.8GHz 频点刚好是 850mV，导致主线错误地用低压 MX 轨给高频缓存供电！ | **`0201~0206` (`jethac`)**：修复 `cpr4pd.c` 的 `uv >= apm_thr_uv` 阈值判断，启用 652MHz~1.804GHz 全频段动态调频，补齐两级热节流温控策略（75°C 降频、85°C 深度限频、100°C 关机）并启用 APSS 硬件看门狗 (`qcom-wdt`)。 |
| **9. Venus 视频硬解码带 B 帧视频卡死、硬编码非 640×480 卡死** | 要求用户推流时必须加 `-bf 0` 禁用 B 帧 | 开启 Venus 固件日志逆向发现：<br>① 固件解码带 B 帧流结束时，会把 `EOS` 标记在**已经归还给驱动的最后一个输出缓冲区 Tag** 上，主线 `vdec_buf_done` 找不到该 buffer 直接丢弃了 EOS；<br>② 编码器固件要求 NV12 缓冲区末尾必须预留至少 128 字节余量，而 720p/1080p 刚好整除 4K 导致无余量被固件拒收。 | **`0701~0704` (`jethac`) / `0004` (`salaman`)**：<br>① `helpers.c` 在计算 NV12 帧大小时额外加 `SZ_4K` 余量；<br>② `vdec.c` 捕获已归还 buffer 上的 EOS 并异步 flush 队列；<br>③ `venc.c` 修正对齐尺寸与实际编码裁剪尺寸。修复后 **1080p 含 4 个 B 帧的 H.264/HEVC 硬解 100% 通过（达 5.2 倍速）**！ |
| **10. 前置摄像头 S5KC505A 无法使用** | 完全不可用 | 原厂驱动位于闭源 `libmmcamera_s5kc505a.so` 中 | **`0401~0404` (`jethac`)**：逆向 `.so` 提取出完整寄存器表，写成标准主线 V4L2 传感器驱动 `drivers/media/i2c/s5kc505a.c` 并配好 CAMSS MIPI 节点。 |

---

### 6.2 逆向高通 ADSP 音频 (Fluence AEC) 的可行性真相

你可能会问：**“能不能把原厂高通 Hexagon ADSP 里的硬件回声消除（Fluence AEC）和波束成形也逆向移植到主线 Linux？”**

根据 `jethac` 对原厂 `/dsp` 分区（包含 `fluence_voiceplus_module.so.1`）和主线 `qdsp6` 驱动的深度拆解，结论非常明确：
1. **为什么 ADSP 固件已经加载了，主线却用不了 Fluence？**
   主线 Linux 通过 `remoteproc` 启动的正是原厂的 Hexagon ADSP 固件（`ADSP.8976.2.8.1-00076`），里面的 Fluence 算法模块其实已经在 DSP 内存里了。但是，高通原厂开启 Fluence 需要用户态闭源的 `audio.primary.msm8953.so` + `libacdbloader.so` 读取 `/vendor/etc/acdbdata/` 下的几十个二进制校准拓扑块（ACDB tables），通过私有 APR 命令下发给 QDSP6 的 `q6adm`（Audio Device Manager）建立复杂的语音拓扑图；而主线内核的 `q6adm.c` 只硬编码了最基础的 `ADM_COPP_TYPE_NONE`（直通 PCM 拓扑）。
2. **还有必要逆向 ACDB 拓扑吗？**
   **没有必要，且得不偿失**。原因有两点：其一，`jethac` 在 `devices/echo-cancellation/ANALYSIS.md` 里明确指出，主线 `q6adm.c` 只硬编码了直通 PCM 拓扑，要跑 Fluence 就得把整个 ACDB 私有拓扑搬过来；其二（更关键），**这条路上还有一个尚未被验证的硬件事实**（见下）。

2. **必须分清“双麦时钟”的两个层次（重要更正）**：
   * **层次 A：两颗 DMIC 之间、以及抽取器与时钟发生器之间的一致性 —— 已有内核补丁解决。**
     LPASS 内部只有一个 DMIC 时钟发生器（`CLK_DMIC_B1_CTL`），DMIC1 和 DMIC2 共用它，所以两颗麦克风的**采样时刻在硬件上天然同步**（这正是双麦波束成形能用的前提）。但每个抽取器（DEC1/DEC2）自己还有一个时钟选择寄存器 `TXn_DMIC_CTL`，主线驱动原先按“DMIC 编号”去写（DMIC1 写 TX1、DMIC2 写 TX2），一旦交叉路由（DEC1←DMIC2）或只启用一路时就会失配，导致该路输出满幅白噪音。`jethac` 的 `0502` 把这个选择改成**跟随抽取器本身**，`0503` 把它与 2.4MHz 可配置速率统一，`0504` 在板级 DTS 钉死原厂的 2.4MHz。这一层已经完全解决。
   * **层次 B：播放参考流（QUAT MI2S → TAS5782M）与录音流（DMIC）之间的跨域时钟漂移 —— 尚未验证，也没有补丁。**
     `jethac` 把这个问题列为**决定性的开放问题**：*“Do MI2S playback and DMIC capture share an AFE root clock on mainline, or not? Decisive.”*，并给出了测量方法（播一段扫频、录回来、60 秒后比较录制长度与播放长度：同根 ≈ 0 ppm，不同根会有可见漂移）。
     `rickx/AUDIO.md` 观察到 QUAT MI2S 的 IBIT 时钟显示为 19.2 MHz（XO 父时钟），**这只能说明两者都挂在同一个 LPASS 时钟控制器下、由同一颗 XO 派生，不能直接等同于 ADSP 内部 AFE 端口时钟完全同相**。因此，在实测之前不要把“0 ppm 漂移”当作既定事实。
   * **如果实测有漂移该怎么办？** 三条备选路径（按优先级）：① 直接用 WebRTC AEC 自身的自适应延迟估计（`module-echo-cancel` 的 `aec_args="drift_compensation=1"`），几 ppm 的晶振漂移它本来就能跟；② 在 PipeWire 侧对参考或采集做重采样，统一到一个时钟域；③ 只有漂移大到 AEC 跟不住时，才考虑用 `afe_loopback`（debugfs，`/sys/kernel/debug/afe_loopback`）取硬件回环做参考，或回到 ADSP 拓扑那条重活。

---

### 6.3 面向 `justhalfbit` Ubuntu 底座的“内核硬化（Kernel Hardening）”落地方案

既然你目前使用的是 `justhalfbit/thinksmart-ubuntu-image`（基于 `linux-postmarketos-qcom-msm8953 6.19.5`），想要彻底抛弃繁杂的用户态修补脚本，让底层内核接管一切硬件能力，建议按以下 **三阶段方案** 实施：

#### 阶段一：立即可做的 Out-of-Tree 模块与 DTB 热替换（耗时 ~1 分钟，无需重刷系统）
利用 `justhalfbit` 仓库现成的 `codec-dmic/build.sh`（Docker Clang 21 环境），直接把以下补丁编译为 `.ko` 模块和 `.dtb` 推送到机器 `/lib/modules/` 和 `/boot/`：
1. **合入 VCNL4200 Active-Force 内核补丁**（取自 `jethac` `0601` + `0602`）：
   * 编译生成安全的 `vcnl4000.ko`，在 DTB 中将 `light-sensor@51` 设为 `status = "okay"`，修正 `vio-supply` 和 `IRQ_TYPE_EDGE_FALLING`。
   * **收益**：直接停用并删除 `vcnl4200-proximity-daemon.py`，改由标准 Linux `/sys/bus/iio/devices/iio:device*` 按需安全读取环境光（Lux）和距离（Proximity），内核自动保障红外灯绝不常亮。
2. **合入 FT8201 TDDI 熄屏保活补丁**（取自 `salaman` `0018`）：
   * 修改 `panel-lenovo-cd-18781y-ft8201.c`，在 `unprepare` 时保留 `VSP/VSN` 和 `reset_gpio` 释放状态，并在 DTB 的 `ft8201_ts` 节点加上 `wakeup-source;`。
   * **收益**：彻底解决 DRM Off 屏幕睡死无法唤醒的顽疾！可以直接使用标准的 Wayland/Weston DPMS 关屏，单击屏幕即可通过硬件中断唤醒。
3. **合入 S5KC505A 摄像头驱动**（取自 `jethac` `0401~0404`）：
   * 将 `s5kc505a.c` 编译为 `s5kc505a.ko`，在 DTB 中启用 `&cci`、`&camss` 和 `camera-sensor@37` 节点。
   * **收益**：在 Ubuntu 下直接点亮前置 500 万像素摄像头，配合 `tsvcam` 即可拍照或通过 Venus 硬编码录制 H.264 视频。

#### 阶段二：主线内核核心补丁重编（耗时 ~10 分钟，替换 `/boot/vmlinuz`）
使用 `justhalfbit` 的 `kernel/build.sh` 完整编译一次内核，打入以下核心级补丁（由于修改了 built-in 子系统，需替换 `/boot/vmlinuz`）：
1. **I2C QUP 时钟就绪等待补丁**（`salaman` `0003-i2c-qup-wait-for-clock-readiness.patch`）→ **彻底废除 `qup-i2c-pinctrl-fix.service`**。
2. **USB 设备模式与 FSM 父时钟补丁**（`jethac` `0002` `&usb3 { dr_mode = "peripheral"; }` + `salaman` `0005-clk-qcom-msm8953-enable-usb-fsm-parent.patch`）→ **彻底恢复正式系统下的 USB 网卡 (`172.16.42.1`) 与 ADB 调试功能**。
3. **Ath10k QCA9379 密钥更新免等待与 PN 重置补丁**（`jethac` `0101` / `salaman` `0020`）→ **替换掉原先粗暴吞 `-ETIMEDOUT` 的补丁，消除每次 GTK Rekey 时的 3 秒网络冻结和组播丢包**。
4. **CPU 1.8GHz APM 电压阈值、温控与硬件看门狗补丁**（`jethac` `0202`, `0204`, `0205`, `0206`）→ **释放全部 1.8GHz 算力（提升 46% CPU 性能），并具备死机 15 秒硬件自动重启保护**。
5. **Venus 视频编解码修复补丁**（`jethac` `0701~0704`）→ **原生支持含 B 帧的 1080p H.264/HEVC 视频流硬解与任意分辨率硬编码**。
6. **QDSP6 `q6asm.c` 内存解映射强制清理补丁** → 在 `q6asm_unmap_memory_regions()` 中无论 DSP 是否超时均清理 `port->buf`，消除 `Buffer already allocated` 死锁隐患。

#### 阶段三：（终极可选）直接切换到 `jethac` 的 Linux 7.3 内核树
如果不想自己往 6.19.5 回移（Backport）上述补丁，最省事的办法是直接采用 **`jethac/lenovo-thinksmart-view` 仓库下的 `kernel/` 构建树（基于 `msm8953-mainline 7.3`）**：
* 该内核树下的 `kernel/patches/0001` 至 `0704`（共 22 个精炼补丁）已经把上述所有硬件驱动集成完毕；
* 其编译产物（`Image.gz` + `apq8053-lenovo-cd-18781y.dtb` + `/lib/modules/7.3.0-*`）与 Ubuntu 24.04 的根文件系统完全兼容，可以直接放入 `justhalfbit` 镜像的 `/boot` (`pmOS_boot`) 分区中引导 Ubuntu！

---

## 七、 一步到位升级 `jethac` Linux 7.3 内核：剩余未解决问题与无损救砖指南

### 7.1 `jethac` 的 Linux 7.3 内核目前还有什么没解决的？（以及如何补齐最后 5 个细节）

把 `jethac/lenovo-thinksmart-view` 的 22 个补丁（`0001`~`0704`）全部拆开审查后，它的完成度已经达到 **95%**，但仍有 **5 个细节问题**（其中 3 个可以直接顺手从 `salaman` 仓库借补丁修掉）：

| 序号 | `jethac` 7.3 内核尚未解决的细节 | 具体原因与影响 | 解决办法（可顺手补齐） |
| :--- | :--- | :--- | :--- |
| **1** | **FT8201 面板电源常开，尚未合入真 DPMS 熄屏保持触控补丁** | `jethac` 的 `0003` 补丁在 DTS 里给 `panel_avdd` 写了 `regulator-always-on`，靠只关背光（`bl_power=4`）熄屏，未修改 `panel-lenovo-cd-18781y-ft8201.c`。另外其 DTS 硬编码了 `lenovo,cd-18781y-ft8201`（如果你的机器恰好是 Boe/Himax 屏幕二供，需要让 `lk2nd` 自动选或者保留通用兼容名）。 | **直接额外打上 `salaman` 的 `0018`（FT8201 熄屏保留触控供电）和 `0012`（DPU flush 清理）两个补丁**。 |
| **2** | **未包含 QUP I2C 时钟就绪轮询补丁与 USB FSM 父时钟补丁** | `jethac` 偶发仍可能遇到 QUP I2C 传输初期竞争，且未合入 `gcc_usb30_master_clk` 的 `CLK_OPS_PARENT_ENABLE` 标志。 | **直接额外打上 `salaman` 的 `0003-i2c-qup-wait-for-clock-readiness.patch` 和 `0005-clk-qcom-msm8953-enable-usb-fsm-parent.patch`**。 |
| **3** | **QDSP6 音频 `S24_LE` 音量小 48dB 的问题** | 高通 `q6asm` 前端把 24-bit LSB 对齐样本按 Q31 读取导致音量衰减 48dB，且 `q6asm_unmap_memory_regions` 超时未清理 `port->buf`。 | 保持 WirePlumber 锁定 `S16LE @ 48kHz` 即可（无需改代码），并可顺手在 `q6asm.c` 加一行强制清理 `port->buf`。 |
| **4** | **Venus 硬件编码器在 Drain 未完成时调 `STREAMOFF` 会触发看门狗重启** | `jethac` 在 2026-11-05 压测摄像头录像时发现：当向 Venus 编码器发 `V4L2_ENC_CMD_STOP` 后，若不等固件排空就对 OUTPUT 队列调 `VIDIOC_STREAMOFF`，SoC 会死锁并由硬件看门狗在 15 秒后自动重启。 | 只要关闭编码器时直接 `close(fd)`（像 `v4l2-ctl` 和新版 `tsvcam` 那样，不显式调 `STREAMOFF`），就 **100% 不会触发**。 |
| **5** | **蓝牙（Bluetooth）在 7.3 上尚未配置设备树固件名与 MAC** | `jethac` 因为只做 Wi-Fi 语音面板，没去测蓝牙。主线 `hci_qca` 驱动需要 DTB 里指定 `firmware-name` 和 `local-bd-address`。 | 如果你需要用蓝牙音箱/耳机，只需在 DTS 的 `&uart_5` -> `bluetooth` 节点加上固件路径即可（`rickx` 的 6.19 已经验证工作）。 |

### 7.2 双麦时钟同步：已包含什么、还缺什么（2026-11-07 补充，含对 6.2 节的更正）

**结论先说：`jethac` 的 22 个补丁里已经包含了“两颗 DMIC 内部时钟一致性”这一层，且是修得最彻底的一份；但“播放参考流与录音流之间的跨域漂移”这一层没有补丁，仍是一个需要实测的开放问题。**

#### 层次 A：DMIC 内部时钟一致性 —— 已被 `0501~0504` 完整覆盖
这一层决定的是**“两颗麦克风能不能同时、干净地采样”**，是双麦波束成形（TDOA/DOA）的物理前提。

| 补丁 | 作用 |
| :--- | :--- |
| `0501` | DT binding 新增 `qcom,dmic-sample-rate`（Hz，600000~6144000），语义与 LPASS VA/WSA macro 的同名属性一致 |
| `0502` | **核心修复**：`TXn_DMIC_CTL` 的时钟选择原先由 DMIC widget 事件按“DMIC 编号”写入（DMIC1→TX1、DMIC2→TX2），一旦交叉路由（DEC1←DMIC2）或只开一路，抽取器就沿用旧的分频值，输出**满幅白噪**。改成**由抽取器自己的 DAPM 事件写入**，谁上电谁对齐共享发生器 |
| `0503` | 把“固定 MCLK/3（3.2MHz）”改成**可配置**：从 2/3/4/6/16 中选不超过上限的最快分频，同时写给发生器 `CLK_DMIC_B1_CTL` 和每个已上电的抽取器 |
| `0504` | 板级 DTS 钉死原厂值 `qcom,dmic-sample-rate = <2400000>`（原厂 `qcom,cdc-dmic-sample-rate = <0x249f00>`） |

> ⚠️ **注意**：`0502` 单独用时仍然把分频硬编码成 `DIV3`，必须 `0501+0502+0503+0504` 四个一起打，2.4MHz 才真正生效。
>
> ⚠️ **不要重复打同一组**：`salaman` 的 `0019-asoc-msm8916-wcd-stock-dmic-clock.patch` 是这**四个补丁的合并增强版**（多了速率区间校验、宽位宽比较、时钟寄存器写失败上报）。**二选一**：要么用 `jethac` 的 `0501~0504`（他本人在机测过），要么用 `salaman` 的 `0019`（错误处理更严谨）。两者叠加会冲突。

**硬件层面的事实**：LPASS 内部只有**一个** DMIC 时钟发生器（`CLK_DMIC_B1_CTL`），DMIC1 与 DMIC2 共用它，所以两颗麦克风的**采样时刻在硬件上是同步的**——这正是双麦算法需要的。`jethac` 实测数据也印证了这一点：两通道在 2.4MHz 与 3.2MHz 下的房间底噪/语音电平差异 ≤ 0.7dB（小于两次 baseline 之间的环境差异），通道间相关系数 room 0.74~0.78、speech 0.63~0.65。这个 0.65 的相关性来自**两个麦克风的物理间距（声程差）**，是波束成形要利用的 TDOA 信号，不是时钟失配。

#### 层次 B：播放参考流 vs 录音流的跨域漂移 —— **没有补丁，属于未验证项**

| 项目 | 现状 |
| :--- | :--- |
| 播放路径 | `hw:0,0` → Q6 DPCM → `QUATERNARY_MI2S_RX` → TAS5782M |
| 录音路径 | `hw:0,1` → `TERT_MI2S_TX` → `msm8916-wcd-digital` → DMIC1/2 |
| 是否同源 | **未实测**。`rickx/AUDIO.md` 只观察到 QUAT MI2S 的 IBIT 时钟显示 19.2MHz（XO 父时钟），说明两者都挂在同一 LPASS 时钟控制器、由同一颗 XO 派生；但 ADSP 内部 AFE 的端口时钟是否完全同相，`jethac` 明确列为**决定性开放问题**：*“Do MI2S playback and DMIC capture share an AFE root clock on mainline, or not? Decisive.”*（`devices/echo-cancellation/ANALYSIS.md` §8） |
| 影响 | 如果两域有 ppm 级漂移，AEC 的自适应滤波器会缓慢发散，表现为“刚开始消得很干净，一分钟后回声又冒出来” |

**必须先做的测量（~15 分钟，一台设备即可）**：
```bash
# 1. 让扬声器播 60 s 扫频/白噪，同时用双麦录音（绕过 PipeWire，直接 ALSA）
speaker-test -D hw:0,0 -c 2 -t sine -f 1000 -l 1 &   # 或 pw-play 一段 60 s 文件
arecord -D hw:0,1 -f S16_LE -c 2 -r 48000 -d 60 /tmp/ref60.wav
# 2. 比较“写进去的样本数”与“录回来的样本数”，以及用互相关找首尾偏移
python3 - <<'PY'
import wave, numpy as np
w = wave.open('/tmp/ref60.wav'); n = w.getnframes(); sr = w.getframerate()
print("captured", n, "frames =", n/sr, "s @", sr)
# 播放端实际时长以播放文件的样本数/48000 为准，差值 ÷ 60 s 即 ppm 漂移
PY
```
判读标准：`录回时长 / 播放时长 - 1` 在 ±20 ppm 内 → WebRTC AEC 完全能跟；超过几百 ppm → 才需要引入重采样或硬件回环。

**如果确认有漂移，按优先级选择（都不需要改内核）**：
1. `module-echo-cancel` 的 WebRTC 后端本来就有延迟估计与漂移补偿（`aec_args="drift_compensation=1"`），先直接开，实测 10 分钟稳定性；
2. 在 PipeWire 图里对参考流或采集流加一级重采样，统一到同一个时钟域；
3. 只有前两条都不行，才考虑用 `afe_loopback`（debugfs `/sys/kernel/debug/afe_loopback`）取硬件回环做参考，或者回到 ADSP 拓扑那条重活（不推荐）。

#### 最终补丁清单（建议直接照此组合，避免冲突）

| 来源 | 补丁 | 用途 |
| :--- | :--- | :--- |
| `jethac` | `0001`~`0704`（22 个，全部） | 平台/显示/功放/麦克风/传感器/摄像头/Wi-Fi/CPU/温控/看门狗/Venus |
| `salaman` | `0003-i2c-qup-wait-for-clock-readiness.patch` | 根治功放 I2C1 掉线（`jethac` 未含） |
| `salaman` | `0005-clk-qcom-msm8953-enable-usb-fsm-parent.patch` | 修 USB 状态机清理时钟卡死（`jethac` 未含） |
| `salaman` | `0012-drm-msm-dpu-flush-video-cleanup.patch` | 修 DPU 编码器残留 flush 位（`jethac` 未含） |
| `salaman` | `0018-drm-panel-ft8201-preserve-touch-during-blanking.patch` | 真 DPMS 熄屏保活触控（`jethac` 只有 `regulator-always-on` 绕法） |

**明确不要再叠加的（与 `jethac` 重复）**：`salaman 0014`（= `jethac 0601/0602` VCNL4200）、`salaman 0019`（= `jethac 0501~0504` DMIC 时钟）、`salaman 0020`（= `jethac 0101` ath10k 密钥）。重复打会 `git apply` 失败或产生语义冲突。

---

### 7.3 如果刷入新内核后系统有问题（开不了机/黑屏/连不上网），怎么救砖？

**请完全放心：在 TSV 上替换内核（`/boot`），你的根文件系统（`/`，包含你调好的 Friday 唤醒词、HA MCP 配置、小智网关数据）一丁点都不会动，而且有 3 道 100% 必达的救砖防线！**

#### 为什么绝对不会变真砖？
TSV 的启动链是：
`高通硬件 BootROM (PBL，永远刷不死，提供 EDL 9008)` ──► `原厂 SBL1/aboot` ──► `boot 分区 (lk2nd)` ──► **`system 分区内的第 1 个小分区 pmOS_boot (/boot，约 249MB，存放内核 vmlinuz、dtb、initramfs)`** ──► `system 分区内的第 2 个大分区 pmOS_root (Ubuntu 根分区)`。

我们升级内核，**只修改 `/boot` 里的 3 个文件（`vmlinuz`、`apq8053-lenovo-cd-18781y.dtb`、`initramfs`）以及 `/lib/modules/7.3.0-*` 目录**，原来的 `/lib/modules/6.19.5-msm8953` 原封不动保留在根分区里！

#### 防线一：不用额外做 `boot` 救砖包——需要时从现有镜像现取（你的意见已采纳）
按你的判断，不必提前单独备份 `boot` 分区：`/work/repos/smart_home/flash/thinksmart-ubuntu-20261101.img` 里本来就内嵌着完整的 `pmOS_boot`，随时可以按需切出来，不占额外空间：
```bash
# 只有当确实需要回滚 /boot 时才执行（从现有镜像现场切出 249MB 启动分区）
dd if=/work/repos/smart_home/flash/thinksmart-ubuntu-20261101.img \
   of=/tmp/boot-619.img bs=512 skip=2048 count=509952 status=none
```
* **万一新内核开不了机，怎么救回来？**
  1. 拔电源 → 按住 `音量+` 和 `音量-` 插电源进 **EDL (9008) 模式**；
  2. 在你的服务器（`/work/repos/smart_home`）上运行，只把启动分区写回物理扇区 `925696`（= `system` 起始 `923648` + 内部偏移 `2048`）：
     ```bash
     /work/repos/smart_home/edl-venv/bin/edl ws 925696 /tmp/boot-619.img
     /work/repos/smart_home/edl-venv/bin/edl reset
     ```
  3. **耗时仅 10~15 秒**，重启后立刻回到原来的 `6.19.5` 内核，根分区（Friday 唤醒词、小智网关、HA 配置）一个字节都没动。

#### 防线二：`/boot` 里同时保留两个内核，能开机就不必进 EDL
`/boot` 分区有 249MB，而一个内核（`vmlinuz` + `dtb` + `initramfs`）只有约 40MB。装 7.3 内核时把原来的文件改名为 `vmlinuz.619` / `initramfs-619.img` / `apq8053-lenovo-cd-18781y.dtb.619`，并在 `/boot/extlinux/extlinux.conf` 里保留两个 `label`。
* 如果新内核能起来但某个外设不对（比如 Wi-Fi 或面板），因为新内核已经修好了 **USB 设备模式**，你可以直接插 USB 线 `ssh ubuntu@172.16.42.1`，把 `extlinux.conf` 的 `DEFAULT` 改成旧 label 再重启，**全程无需 EDL**。
* 只有在“连内核都起不来、USB 也不枚举”的情况下才动用防线一。

#### 防线三：最终兜底——直接重写 `system`（代价是丢用户数据）
最坏情况：进 EDL 跑一条
```bash
/work/repos/smart_home/edl-venv/bin/edl w system /work/repos/smart_home/flash/thinksmart-ubuntu-20261101.img
```
5 分钟内恢复成出厂 Ubuntu 24.04。注意这一步会覆盖 `pmOS_root`，`/home/ubuntu` 下的 Friday 配置、小智网关的 `chat.db`、API Key、Wi-Fi 密码都会丢；如果在意，换内核前先跑 `image/restore-userdata.sh` 对应的备份流程（`thinksmart_view_deployment_log_20261102.md` 里有现成命令）。想彻底回原厂则用 `edl wf flash/stock-full-emmc.bin`。
