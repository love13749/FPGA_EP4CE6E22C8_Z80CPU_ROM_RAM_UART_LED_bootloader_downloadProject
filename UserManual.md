# MC（Micro Computer）v2.0 技术文档

## 基于 FPGA 的 Z80 微型计算机系统

---

## 目录

1. [项目概述](#1-项目概述)
2. [硬件架构](#2-硬件架构)
3. [系统配置](#3-系统配置)
4. [内存映射](#4-内存映射)
5. [I/O 映射](#5-io-映射)
6. [PWM 脉宽调制模块详解](#6-pwm-脉宽调制模块详解)
7. [Bootloader 使用说明](#7-bootloader-使用说明)
8. [用户程序开发](#8-用户程序开发)
9. [项目文件结构](#9-项目文件结构)
10. [开发工具链](#10-开发工具链)
11. [常见问题](#11-常见问题)

---

## 1. 项目概述

### 1.1 简介

MC（Micro Computer）是一个基于 **Z80 兼容软核 CPU（T80s）** 的微型计算机系统，在 **Altera Cyclone IV FPGA** 上实现。系统包含 8KB ROM、4KB RAM、UART 串口、8 位 LED 并行输出和 8 通道可编程 PWM 输出接口。

### 1.2 主要特性

| 特性 | 参数 |
|------|------|
| CPU | T80s（Z80 兼容软核），10MHz |
| ROM | 8KB（$0000-$1FFF），存放 Bootloader |
| RAM | 4KB（$2000-$2FFF），存放用户程序 |
| 串口 | 6850 ACIA 兼容 UART，115200 baud，16 字节 FIFO |
| LED | 8 位并行输出，端口 $90 |
| PWM | 8 通道可编程脉宽调制输出，端口 $84-$87 |
| 主时钟 | 50MHz FPGA 晶振 |
| 下载方式 | 串口下载 Intel HEX 格式文件 |

### 1.3 系统框图

```raw
                    50MHz 晶振          独立PWM时钟
                        │                    │
                        ▼                    ▼
               ┌────────────────┐    ┌──────────────┐
               │   时钟分频器     │    │  PWM时钟域    │
               │ CPU: 10MHz      │    │ (clk_pwm)    │
               │ UART: 115200    │    └──────────────┘
               └────────┬───────┘
                        │
┌───────────────────────────────────────────────────┐
│                    Z80 CPU (T80s 软核)             │
│  ┌─────────────────────────────────────────────┐  │
│  │  地址总线 A[15:0]     数据总线 D[7:0]        │  │
│  │  控制总线 MREQ/IORQ/RD/WR                   │  │
│  └─────────────────────────────────────────────┘  │
└──────┬──────────┬──────────┬──────────┬───────────┘
       │          │          │          │
       ▼          ▼          ▼          ▼
   ┌──────┐  ┌──────┐  ┌──────────┐  ┌──────────┐
   │ ROM  │  │ RAM  │  │ UART     │  │ PWM      │
   │8KB   │  │4KB   │  │ $80-$81  │  │ $84-$87  │
   │$0000-│  │$2000-│  │ 115200   │  │ 可编程   │
   │$1FFF │  │$2FFF │  │ 16B FIFO │  │ 8通道    │
   └──────┘  └──────┘  └─────┬────┘  └─────┬────┘
                             │              │
                         ┌──────┐      ┌──────────┐
                         │ LED  │      │ PWM输出  │
                         │ $90  │      │ pwmout   │
                         └──────┘      │[7:0]     │
                                       └──────────┘
```
## 2. 硬件架构

### 2.1 FPGA 引脚分配

| 引脚 | 方向 | 连接 |
|------|------|------|
| n_reset | 输入 | 复位按钮（低有效） |
| clk | 输入 | 50MHz 晶振 |
| clk_pwm | 输入 | PWM 独立时钟输入（如 27MHz） |
| rxd1 | 输入 | USB 转串口 TX（FPGA 接收） |
| txd1 | 输出 | USB 转串口 RX（FPGA 发送） |
| leds[7:0] | 输出 | 8 个 LED |
| pwmout[7:0] | 输出 | 8 通道 PWM 并行输出 |

> **v2.0 新增**：增加了 `clk_pwm`（PWM 独立时钟输入引脚）和 `pwmout[7:0]`（8 通道 PWM 并行输出引脚）。

### 2.2 顶层实体（Microcomputer.vhd）

```vhdl
entity Microcomputer is
    port(
        n_reset     : in std_logic;                     -- 复位（低有效）
        clk         : in std_logic;                     -- 50MHz 主时钟
        clk_pwm     : in std_logic;                     -- PWM 独立时钟
        rxd1        : in std_logic;                     -- UART 接收
        txd1        : out std_logic;                    -- UART 发送
        leds        : out std_logic_vector(7 downto 0); -- 8位 LED
        pwmout      : out std_logic_vector(7 downto 0)  -- 8通道 PWM 输出
    );
end Microcomputer;
```

### 2.3 CPU 配置（T80s 软核）

| 参数 | 值 | 说明 |
|------|-----|------|
| mode | 1 | Z80 兼容模式（快速模式） |
| t2write | 1 | 写操作在 T2 周期完成 |
| iowait | 0 | I/O 不插入等待周期 |
| wait_n | '1' | 不使用等待状态 |
| int_n | '1' | 未使用中断 |

### 2.4 时钟系统

系统基于 50MHz 主时钟产生两个时钟域：

**CPU 时钟（10MHz）**：

```vhdl
cpuClkCount: 0 → 1 → 2 → 3 → 4 → 0（5 分频）
cpuClock: 计数 < 2 时低，≥ 2 时高
频率: 50MHz / 5 = 10MHz
```

**串口时钟（~1.8432MHz）**：

```vhdl
serialClkCount += 2416（每时钟周期）
serialClock = serialClkCount(15) -- 取最高位
频率 = 50MHz × 2416 / 65536 ≈ 1.843MHz
波特率 = 1.843MHz / 16 ≈ 115200 baud
```

**PWM 时钟（独立时钟域）**：

```raw
-- PWM 模块使用独立的 clk_pwm 时钟输入
-- 不与 CPU 和 UART 共用时钟域
-- 典型频率：27MHz（如开发板提供），也可使用 50MHz
```

> **v2.0 新增**：PWM 模块工作在**独立的时钟域**（`clk_pwm`），与 CPU 主时钟（`clk`）完全解耦，这使得 PWM 输出频率不受 CPU 工作频率的影响。

### 2.5 地址译码

地址译码在 `Microcomputer.vhd` 中通过 VHDL 的 when-else 语句实现：

```vhdl
-- 内存译码
n_basRomCS <= '0' when cpuAddress(15 downto 13) = "000" else '1';
-- ROM: $0000-$1FFF (8KB)，A15-A13 = "000"

n_internalRam1CS <= '0' when cpuAddress(15 downto 12) = "0010" else '1';
-- RAM: $2000-$2FFF (4KB)，A15-A12 = "0010"

-- I/O 译码（IORQ 必须有效）
n_interface1CS <= '0' when cpuAddress(7 downto 1) = "1000000"
                       and (n_ioWR='0' or n_ioRD='0') else '1';
-- UART: $80-$81，A7-A1 = "1000000"

n_aaronCS <= '0' when cpuAddress(7 downto 1) = "1001000"
                  and (n_ioWR='0' or n_ioRD='0') else '1';
-- LED: $90-$91，A7-A1 = "1001000"

n_pwmCS <= '0' when cpuAddress(7 downto 2) = "100001"
                and (n_ioWR='0' or n_ioRD='0') else '1';
-- PWM: $84-$87，A7-A2 = "100001"（4个寄存器，使用 A1-A0 选择）
```

**I/O 地址译码对照表**：

| 外设 | 译码位宽 | 译码条件 | 基址 | 地址范围 | 寄存器选择 |
|------|----------|----------|------|---------|-----------|
| UART | A[7:1] (7位) | 1000000 | $80 | $80-$81 | A0 |
| PWM  | A[7:2] (6位) | 100001  | $84 | $84-$87 | A1, A0 |
| LED  | A[7:1] (7位) | 1001000 | $90 | $90-$91 | A0 |

> **v2.0 变更**：PWM 使用 **A[7:2]**（6 位）进行译码，**A[1:0]**（2 位）用于内部 4 个寄存器的选择，因此 PWM 模块占用 **4 个连续的 I/O 地址**（$84-$87），而 UART 和 LED 各只占用 2 个地址。

### 2.6 数据总线多路选择

```vhdl
cpuDataIn <=
    interface1DataOut     when n_interface1CS = '0' else  -- UART
    interfacePwmDataOut   when n_pwmCS = '0' else         -- PWM
    basRomData            when n_basRomCS = '0' else      -- ROM
    internalRam1DataOut   when n_internalRam1CS = '0' else-- RAM
    x"FF";                                                -- 默认值
```

> **v2.0 变更**：数据总线增加了 `interfacePwmDataOut` 优先级分支（仅次于 UART），确保 PWM 寄存器的读取操作能够正常进行。

---

## 3. 系统配置

### 3.1 Quartus 项目配置

- **项目文件**：`Microcomputer/Microcomputer.qpf`
- **设置文件**：`Microcomputer/Microcomputer.qsf`
- **目标器件**：Cyclone IV EP4CE10E22C8（或其他兼容器件）
- **综合工具**：Quartus Prime 16.0+

### 3.2 编译步骤

1. 打开 Quartus Prime
2. 打开项目：`File → Open Project → Microcomputer.qpf`
3. 编译：`Processing → Start Compilation`
4. 烧录：`Tools → Programmer → 选择 .sof 文件 → Start`

### 3.3 ROM 初始化文件

ROM 内容由 `BASIC.HEX` 文件初始化，该文件由 `basic.asm` 编译生成：

```raw
basic.asm → sjasmplus 编译 → BASIC.HEX → Quartus 烧写进 FPGA
```

更新 ROM 内容后需要**重新编译 Quartus 项目并重新烧录 FPGA**。

---

## 4. 内存映射

| 地址范围 | 大小 | 器件 | 属性 | 说明 |
|---------|------|------|------|------|
| $0000-$1FFF | 8KB | ROM | 只读 | Bootloader 程序 |
| $2000-$2FFF | 4KB | RAM | 读写 | 用户程序/数据 |
| $2F00 | 1B | RAM 变量区 | 读写 | BYTE_COUNT |
| $2F01-$2F02 | 2B | RAM 变量区 | 读写 | EXT_ADDR |
| $2F03-$2FFF | 253B | RAM 栈区 | 读写 | 栈空间（SP=$2FFF） |
| $3000-$FFFF | - | 未使用 | - | 读取返回 $FF |

### 4.1 ROM 布局（$0000-$1FFF）

| 地址 | 内容 | 说明 |
|------|------|------|
| $0000-$0001 | DI / LD SP,$2FFF | 复位入口 |
| $0004-$000B | UART 初始化 | OUT ($80),$03 / OUT ($80),$15 |
| $000C-$0012 | 打印欢迎信息 | CALL PRINT_STR |
| $0013-$0016 | 进入下载模式 | CALL HEX_LOADER |
| $0017-$001B | 打印完成信息 | "Jump $2000" |
| $001C | 跳转用户程序 | JP RAM_START ($2000) |
| $0020-$0038 | MSG_BOOT | "Z80 Boot\nOK\n" |
| $003D-$0053 | MSG_DONE | "Jump $2000\n" |
| $0055-$006B | MSG_ERR | "ERROR\n" |
| $006B-$01FF | 子程序 | UART_GETCHAR / PRINT_STR / A2H / RD_BYTE / HEX_LOADER |

### 4.2 RAM 用户程序区（$2000-$2EFF）

| 地址 | 用途 | 可用大小 |
|------|------|---------|
| $2000-$2EFF | 用户程序代码/数据 | 3840 字节 |
| $2F00 | BYTE_COUNT 变量（Bootloader 使用） | 1 字节 |
| $2F01-$2F02 | EXT_ADDR 变量（Bootloader 使用） | 2 字节 |
| $2F03-$2FFF | 栈空间（向下增长，SP=$2FFF） | 253 字节 |

> **注意**：用户程序若使用 `$2F00-$2F02` 作为数据区，注意 Bootloader 已完成使命，这些地址可以被安全覆盖。

---

## 5. I/O 映射

### 5.1 外设地址总览

| I/O 地址 | 外设 | 读 | 写 |
|---------|------|-----|-----|
| $80 | UART 控制/状态 | 状态寄存器 | 控制寄存器 |
| $81 | UART 数据 | 接收数据 | 发送数据 |
| $84 | PWM 控制 | CTRL 寄存器 | CTRL 寄存器 |
| $85 | PWM 周期 | PRD 寄存器 | PRD 寄存器 |
| $86 | PWM 占空比 | CCR 寄存器 | CCR 寄存器 |
| $87 | PWM 计数器 | CNT 寄存器 | 保留 |
| $90 | LED | - | LED 输出 |

> **v2.0 新增**：增加了 PWM 的 4 个 I/O 地址（$84-$87），新增 8 通道可编程脉宽调制输出功能。

### 5.2 UART（$80-$81）

**外设模块**：`Components/UART/bufferedUART.vhd`

**标准 6850 ACIA 兼容**，基于 **A0（regSel）** 选择寄存器：

| regSel（A0） | 读 | 写 |
|:-----------:|-----|-----|
| 0（$80） | 状态寄存器 | 控制寄存器 |
| 1（$81） | 接收数据寄存器 | 发送数据寄存器 |

#### 状态寄存器（$80 读）

| Bit | 名称 | 说明 |
|-----|------|------|
| 0 | RDRF | 接收数据满（1=可读） |
| 1 | TDRE | 发送寄存器空（1=可写） |
| 2 | n_DCD | 数据载波检测（恒为 0） |
| 3 | n_CTS | 清除发送（恒为 0） |
| 4 | - | 未使用（0） |
| 5 | - | 未使用（0） |
| 6 | - | 未使用（0） |
| 7 | IRQ | 中断请求 |

#### 控制寄存器（$80 写）

| Bit | 名称 | 说明 |
|-----|------|------|
| 7 | Rx 中断使能 | 1=使能接收中断 |
| 6-5 | Tx 控制 | 00=RTS 低电平（默认） |
| 4-2 | - | 未使用 |
| 1-0 | 复位 | 11=复位 UART |

#### Z80 驱动示例

```asm
; --- UART 初始化 ---
LD A, $03
OUT ($80), A         ; 复位 UART
LD A, $15
OUT ($80), A         ; 配置完成

; --- 发送字符（A寄存器） ---
UART_PUTCHAR:
    PUSH AF
_WAIT_TX:
    IN A, ($80)      ; 读状态寄存器
    BIT 1, A         ; 检查 bit1（发送空）
    JR Z, _WAIT_TX   ; 等待发送就绪
    POP AF
    OUT ($81), A     ; 写入数据寄存器
    RET

; --- 接收字符（返回A寄存器） ---
UART_GETCHAR:
_WAIT_RX:
    IN A, ($80)      ; 读状态寄存器
    BIT 0, A         ; 检查 bit0（接收满）
    JR Z, _WAIT_RX   ; 等待数据到达
    IN A, ($81)      ; 读取数据寄存器
    AND $7F          ; 清除最高位
    RET
```

### 5.3 LED（$90-$91）

**外设模块**：`Components/UART/aaron.vhd`

**功能**：8 位并行输出，驱动 FPGA 板上的 8 个 LED。

**写操作**：
```asm
OUT ($90), A    ; A[7:0] 对应 LED7-LED0
```

**复位初始值**：`$55`（LED 交替亮灭）

| LED7 | LED6 | LED5 | LED4 | LED3 | LED2 | LED1 | LED0 |
|------|------|------|------|------|------|------|------|
| 0 | 1 | 0 | 1 | 0 | 1 | 0 | 1 |

> **注意**：LED 输出**低电平点亮**。如果 FPGA 板上 LED 是低电平点亮，写入值需要取反：
```asm
CPL              ; A 取反
OUT ($90), A     ; 输出到 LED
```

### 5.4 PWM（$84-$87）

**外设模块**：`Components/PWM/PWM.vhd`（v2.0 新增）

PWM 模块是 v2.0 核心新增功能，详见 [第 6 章 PWM 脉宽调制模块详解](#6-pwm-脉宽调制模块详解)。

---

## 6. PWM 脉宽调制模块详解

### 6.1 概述

PWM（Pulse Width Modulation，脉宽调制）模块是 v2.0 版本新增的外设，提供 **8 通道可编程脉宽调制输出**。该模块工作在独立的时钟域（`clk_pwm`），与 CPU 主时钟完全解耦。

### 6.2 硬件架构

```vhdl
entity PWM is
    port(
        clk     : in std_logic;                      -- PWM 独立时钟
        n_wr    : in std_logic;                      -- I/O 写选通（低有效）
        n_rd    : in std_logic;                      -- I/O 读选通（低有效）
        regSel  : in std_logic_vector(1 downto 0);   -- 寄存器选择
        dataIn  : in std_logic_vector(7 downto 0);   -- CPU 写入数据
        dataOut : out std_logic_vector(7 downto 0);  -- CPU 读取数据
        pwm_out : out std_logic_vector(7 downto 0)   -- 8路 PWM 输出
    );
end PWM;
```

**端口说明**：

| 端口 | 位宽 | 方向 | 说明 |
|------|------|------|------|
| clk | 1 | 输入 | PWM 独立时钟（来自 clk_pwm 引脚） |
| n_wr | 1 | 输入 | 写选通（低有效，由 n_pwmCS or n_ioWR 产生） |
| n_rd | 1 | 输入 | 读选通（低有效，由 n_pwmCS or n_ioRD 产生） |
| regSel | 2 | 输入 | 寄存器选择（连接 CPU 地址 A1, A0） |
| dataIn | 8 | 输入 | CPU 写入数据 |
| dataOut | 8 | 输出 | CPU 读取数据 |
| pwm_out | 8 | 输出 | 8 路 PWM 方波输出 |

### 6.3 内部寄存器

PWM 模块包含 **4 个可编程 8 位寄存器**，通过 I/O 地址 $84-$87 访问：

| I/O 地址 | regSel | 寄存器 | 符号 | 读写 | 说明 |
|---------|--------|--------|------|------|------|
| $84 | 00 | 控制寄存器 | CTRL | 读写 | 控制 PWM 使能/复位/极性 |
| $85 | 01 | 周期寄存器 | PRD | 读写 | 设置 PWM 周期（0-255） |
| $86 | 10 | 占空比寄存器 | CCR | 读写 | 设置 PWM 占空比（0-255） |
| $87 | 11 | 计数寄存器 | CNT | 只读 | 当前计数器值 |

#### 控制寄存器 CTRL（$84）

| Bit | 名称 | 说明 |
|-----|------|------|
| 7 | RST | **软件复位**（1=复位）：清零计数器，关闭 PWM 输出 |
| 6-2 | - | 保留（恒为 0） |
| 1 | POL | **极性选择**（1=正相，0=反相） |
| 0 | EN | **PWM 使能**（1=使能，0=关闭输出为低电平） |

#### 周期寄存器 PRD（$85）

- 取值范围：0x00 ~ 0xFF（0 ~ 255）
- 设定 PWM 输出的**周期长度**（以时钟周期为单位）
- 当内部计数器 CNT 达到 PRD 值时自动归零

#### 占空比寄存器 CCR（$86）

- 取值范围：0x00 ~ 0xFF（0 ~ 255）
- 设定 PWM 输出的**高电平宽度**
- 当 CNT < CCR 时输出高电平，否则输出低电平
- 当 CCR = 0 时输出恒低，CCR > PRD 时输出恒高

#### 计数寄存器 CNT（$87）

- 只读寄存器
- 从 0 递增到 PRD，然后归零循环
- 可通过读取 CNT 获取 PWM 的当前相位

### 6.4 工作原理

PWM 模块的核心是一个**锯齿波比较器**：

```raw
CNT = 0 → 1 → 2 → ... → PRD → 0（循环递增）
     ▲               ▲
     │               │
     └── CNT < CCR ──┘
     pwm_out = 1     pwm_out = 0
```

**时序波形示例（PRD=10, CCR=6）**：

```raw
CLK   ┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐
CNT   0 1 2 3 4 5 6 7 8 9 10 0 1 2...
      ▲       ▲           ▲
      │       │           │
      │ CNT < CCR=6       │ CNT=PRD=10
      │ 输出高电平         │ 归零
      ▼                   ▼
PWM   ████████████████░░░░░░░░████████
      高电平（6周期）    低电平（5周期）
      ←──── 周期(PRD+1)=11 ─────→
```

**占空比计算**：

```raw
占空比 = CCR / (PRD + 1) × 100%

示例：
  PRD=10, CCR=5 → 占空比 = 5/11 ≈ 45.5%
  PRD=10, CCR=10 → 占空比 = 10/11 ≈ 90.9%
  PRD=255, CCR=128 → 占空比 = 128/256 = 50%
```

**PWM 输出频率计算**：

```raw
PWM频率 = clk_pwm频率 / (PRD + 1)

示例（clk_pwm = 27MHz）：
  PRD=0   → 频率 = 27MHz / 1   = 27MHz
  PRD=9   → 频率 = 27MHz / 10  = 2.7MHz
  PRD=99  → 频率 = 27MHz / 100 = 270kHz
  PRD=255 → 频率 = 27MHz / 256 ≈ 105kHz
  PRD=255 → 频率 = 50MHz / 256 ≈ 195kHz（当 clk_pwm = 50MHz）
```

### 6.5 寄存器操作流程

#### 6.5.1 基本 PWM 输出

```asm
; --- 配置并启动 PWM 输出 ---

; 第1步：关闭 PWM（先配置参数）
LD A, $00
OUT ($84), A         ; CTRL = 0x00，关闭 PWM

; 第2步：设置周期
LD A, $FF
OUT ($85), A         ; PRD = 255（周期=256个时钟周期）

; 第3步：设置占空比
LD A, $80
OUT ($86), A         ; CCR = 128（约50%占空比）

; 第4步：使能 PWM
LD A, $01
OUT ($84), A         ; CTRL = 0x01，使能 PWM（正相输出）

; --- PWM 已输出，无需 CPU 干预 ---
```

#### 6.5.2 动态调整占空比

```asm
; 运行中动态修改占空比（不影响 PWM 运行）
LD A, $40
OUT ($86), A         ; 立即生效，CCR = 64（约25%占空比）
```

#### 6.5.3 软件复位 PWM

```asm
LD A, $80
OUT ($84), A         ; CTRL(7)=1 → 计数器清零，输出关闭

; ... 重新配置 ...

LD A, $01
OUT ($84), A         ; CTRL = 0x01，重新使能
```

#### 6.5.4 反相输出

```asm
LD A, $03
OUT ($84), A         ; CTRL = 0x03，使能 + 反相输出
                     ; pwm_out 内部高/低电平取反后输出
```

### 6.6 完整编程示例

**汇编示例（project.asm）**：

```asm
; ============================================================
; PWM 测试程序 - 占空比 0→255 循环递增
; ============================================================
PWM_CTRL    EQU $84
PWM_PRD     EQU $85
PWM_CCR     EQU $86

    ORG $2000

START:
    LD SP, $2FFF
    
    ; 初始化 PWM
    XOR A
    OUT (PWM_CTRL), A    ; CTRL = 0x00，关闭 PWM
    LD A, $FF
    OUT (PWM_PRD), A     ; PRD = 255
    LD B, $00            ; 初始占空比 = 0

LOOP:
    ; 设置占空比
    LD A, B
    OUT (PWM_CCR), A
    
    ; 使能 PWM
    LD A, $01
    OUT (PWM_CTRL), A    ; 启动 PWM
    
    ; 占空比递增
    INC B
    
    ; 延时
    CALL DELAY
    
    JR LOOP              ; 无限循环

; --- 延时子程序 ---
DELAY:
    PUSH BC
    LD B, $FF
_DELAY_OUTER:
    LD C, $FF
_DELAY_INNER:
    DEC C
    JR NZ, _DELAY_INNER
    DEC B
    JR NZ, _DELAY_OUTER
    POP BC
    RET

    END START
```

**C 语言示例（SDCC）**：

```c
#define PWM_CTRL (*(volatile unsigned char *)0x84)
#define PWM_PRD  (*(volatile unsigned char *)0x85)
#define PWM_CCR  (*(volatile unsigned char *)0x86)

void delay(void);

void main(void) 
{
    unsigned char duty = 0;
    
    // 初始化 PWM
    PWM_CTRL = 0x00;     // 关闭
    PWM_PRD  = 0xFF;     // 周期 = 255
    
    while (1) 
    {
        PWM_CCR  = duty;    // 设置占空比
        PWM_CTRL = 0x01;    // 使能 PWM
        
        if (duty == 0xFF)
            duty = 0;
        else
            duty++;
        
        delay();
    }
}
```

### 6.7 应用场景

| 应用 | 说明 | 典型参数 |
|------|------|---------|
| **LED 亮度调节** | 通过改变占空比控制 LED 亮度 | clk_pwm=27MHz, PRD=255 |
| **电机调速** | 改变占空比控制直流电机转速 | 需外部驱动电路 |
| **蜂鸣器音调** | 改变 PWM 频率（周期）产生不同音调 | PRD 设为小值 |
| **模拟信号输出** | PWM + RC 滤波 = DAC | 需外部低通滤波器 |
| **舵机控制** | 标准 50Hz PWM 信号 | PRD 调至约 50Hz |

### 6.8 使用注意事项

1. **独立时钟域**：PWM 使用 `clk_pwm` 而非 CPU 主时钟 `clk`。确保 FPGA 引脚连接了合适的时钟源（如 27MHz 或 50MHz）。
2. **8 路同步输出**：8 路 PWM 输出完全同步，占空比相同（由同一个 CCR 寄存器控制）。
3. **非精确时序**：PWM 的占空比调节受 Z80 CPU 运行速度影响，动态调节时占空比变化速率取决于 CPU 执行速度。
4. **软件复位**：CTRL(7) 的软件复位会清零计数器并关闭输出，配置完成后需重新使能。

---

## 7. Bootloader 使用说明

### 7.1 概述

Bootloader 存储在 ROM（$0000-$01FF）中，上电后自动运行，通过串口接收 Intel HEX 格式的用户程序，写入 RAM 后跳转执行。

### 7.2 上电启动流程

```raw
1. FPGA 上电 → CPU 从 $0000 开始执行
2. Bootloader 初始化 UART（115200, 8N1）
3. 串口输出：
   
   Z80 Boot
   OK
   
4. 等待用户发送 HEX 文件
5. 接收完成后输出：Jump $2000
6. 自动跳转到用户程序 $2000 执行
```

### 7.3 Intel HEX 格式说明

Bootloader 接收标准 Intel HEX 格式，所有行可连在一起发送（无需换行等待）：

```raw
:BBAAAATT[数据...]CC
```

| 字段 | 字节数 | 说明 |
|------|--------|------|
| : | 1 | 起始标志 |
| BB | 1 | 数据字节数 |
| AAAA | 2 | 起始地址 |
| TT | 1 | 类型 |
| 数据 | BB | 实际数据 |
| CC | 1 | 校验和 |

**支持的类型**：

| 类型码 | 名称 | 说明 |
|--------|------|------|
| 00 | 数据记录 | 解析数据并写入 RAM |
| 01 | 文件结束 | 结束下载，跳转执行 |
| 02 | 扩展段地址 | 设置段基址（左移 4 位） |
| 04 | 扩展线性地址 | 设置线性基址 |

**注意**：目标地址必须在 $2000-$2FFF 范围内，否则会显示 ERROR 并跳过。

**示例**（流水灯程序的第一行）：

```raw
:1020000031FF2F216E20CD51203E012FD3902FF58F
```

| 部分 | 值 | 说明 |
|------|-----|------|
| :10 | 16 | 16 字节数据 |
| 2000 | $2000 | RAM 起始地址 |
| 00 | 数据 | 数据记录类型 |
| 31FF2F... | 数据 | 16 字节机器码 |
| 8F | 校验和 | 数据完整性验证 |

### 7.4 发送步骤

**使用串口助手**：
1. 设置串口参数：115200 baud, 8 数据位, 1 停止位, 无校验
2. 打开串口
3. 给 FPGA 复位或重新上电
4. 等待收到 "Z80 Boot\nOK\n"
5. 发送 HEX 数据（将 .HEX 文件内容复制粘贴到发送区）
6. 观察接收区显示 "."（每个数据记录一个点）
7. 收到 "Jump $2000" 表示下载成功
8. 用户程序自动开始运行

**使用 Python 脚本**（需要 pyserial 库）：

```python
import serial

ser = serial.Serial('COM3', 115200, timeout=5)
with open('Object/project.hex') as f:
    hex_data = f.read().replace('\n', '').replace('\r', '')
ser.write(hex_data.encode('ascii'))
ser.close()
```

### 7.5 快捷键

| 按键 | 功能 |
|------|------|
| ESC（0x1B） | 退出下载模式 |

---

## 8. 用户程序开发

### 8.1 开发环境

- **汇编器**：sjasmplus（Z80 汇编器）
- **C 编译器**：SDCC（Small Device C Compiler）
- **文本编辑器**：VS Code 等
- **串口工具**：任意串口助手（115200, 8N1）

### 8.2 程序模板

```asm
; ============================================================
; 用户程序模板
; 编译: ORG $2000（下载到 RAM 运行）
; ============================================================

UART_DATA   EQU $81      ; UART 数据端口
UART_STAT   EQU $80      ; UART 状态端口
LED_PORT    EQU $90      ; LED 输出端口
PWM_CTRL    EQU $84      ; PWM 控制端口
PWM_PRD     EQU $85      ; PWM 周期端口
PWM_CCR     EQU $86      ; PWM 占空比端口

    ORG $2000

START:
    LD SP, $2FFF         ; 初始化栈指针
    
    ; --- 程序代码从这里开始 ---
    
    ; 示例：通过串口输出信息
    LD HL, MSG_HELLO
    CALL PRINT_STRING
    
    ; 示例：LED 输出
    LD A, $01
    OUT (LED_PORT), A
    
    ; 示例：死循环
LOOP:
    JR LOOP

; ============================================================
; 子程序
; ============================================================

; UART 发送字符（A = 要发送的字符）
UART_PUTCHAR:
    PUSH AF
_WAIT_TX:
    IN A, (UART_STAT)
    BIT 1, A
    JR Z, _WAIT_TX
    POP AF
    OUT (UART_DATA), A
    RET

; 输出字符串（HL = 字符串地址，0 结尾）
PRINT_STRING:
    PUSH AF
    PUSH HL
_PS_LOOP:
    LD A, (HL)
    CP 0
    JR Z, _PS_END
    CALL UART_PUTCHAR
    INC HL
    JR _PS_LOOP
_PS_END:
    POP HL
    POP AF
    RET

; ============================================================
; 数据区
; ============================================================
MSG_HELLO:
    DB 0Dh, 0Ah           ; 换行
    DB "Hello from Z80!", 0Dh, 0Ah
    DB 0                   ; 字符串结束

; ============================================================
    END START
```

### 8.3 系统常量定义

```asm
; --- 系统常量（用户程序中使用） ---
UART_DATA   EQU $81      ; UART 数据端口
UART_STAT   EQU $80      ; UART 状态端口
LED_PORT    EQU $90      ; LED 输出端口
PWM_CTRL    EQU $84      ; PWM 控制端口（v2.0 新增）
PWM_PRD     EQU $85      ; PWM 周期端口（v2.0 新增）
PWM_CCR     EQU $86      ; PWM 占空比端口（v2.0 新增）
PWM_CNT     EQU $87      ; PWM 计数器端口（v2.0 新增）
RAM_START   EQU $2000    ; RAM 起始地址（用户程序入口）
STACK_TOP   EQU $2FFF    ; 栈顶地址
```

### 8.4 编译

使用 build.cmd 脚本（自动编译并转换）：

```raw
.\build.cmd
```

或手动执行：

```bash
sjasmplus project.asm --hex=Object\project.hex
```

编译输出：
- `Object/project.hex`：Intel HEX 格式（用于串口下载）

### 8.5 下载

使用 load.cmd 脚本：

```raw
.\load.cmd
```

或使用串口助手发送 `Object/project.hex` 的内容。

### 8.6 C 语言开发（SDCC）

项目同时支持使用 **SDCC 编译器** 进行 C 语言开发：

**编译命令**：

```bash
sdcc -mz80 --code-loc 0x2000 --data-loc 0x2E00 Project.c
```

**C 语言 PWM 示例**（详见 `compile/Project.c`）：

```c
#define PWM_CTRL (*(volatile unsigned char *)0x84)
#define PWM_PRD  (*(volatile unsigned char *)0x85)
#define PWM_CCR  (*(volatile unsigned char *)0x86)

void main(void) 
{
    unsigned char pwm_duty = 0;
    
    PWM_CTRL = 0x00;     // 关闭 PWM
    PWM_PRD  = 0xFF;     // 周期 = 255
    
    while (1) 
    {
        PWM_CCR = pwm_duty;   // 设置占空比
        PWM_CTRL = 0x01;      // 使能 PWM
        
        if (pwm_duty == 0xFF)
            pwm_duty = 0;
        else
            pwm_duty++;
    }
}
```

### 8.7 延时子程序

```asm
; 延时子程序（约 1 秒 @ 10MHz）
DELAY:
    PUSH BC
    LD B, $FF
_DELAY_OUTER:
    LD C, $FF
_DELAY_INNER:
    DEC C
    JR NZ, _DELAY_INNER
    DEC B
    JR NZ, _DELAY_OUTER
    POP BC
    RET
```

### 8.8 完整示例：流水灯 + 串口 + PWM（v2.0 新增 PWM 控制）

参见 `Z80Project/project.asm` 和 `compile/Project.c`，该程序实现：
- 上电输出 "Z80 Program Started!"
- LED 流水灯效果
- PWM 占空比 0→255 循环递增
- 串口实时输出当前占空比的十六进制值

主要流程：

```asm
START:
    ; 初始化 PWM
    XOR A
    OUT (PWM_CTRL), A       ; 关闭 PWM
    LD A, $FF
    OUT (PWM_PRD), A        ; 周期 = 255

MAIN_LOOP:
    ; --- PWM 输出 ---
    LD A, $00
    OUT (PWM_CTRL), A       ; 关闭（先配置）
    LD A, B
    OUT (PWM_CCR), A        ; 设置占空比
    LD A, $01
    OUT (PWM_CTRL), A       ; 使能
    
    ; 占空比递增
    INC B
    
    ; --- 发送占空比到串口 ---
    CALL SEND_HEX           ; 发送十六进制值
    LD A, ' '
    CALL UART_PUTCHAR       ; 发送空格
    
    ; --- LED 输出 ---
    CPL
    OUT (LED_PORT), A
    CPL
    
    ; --- 延时 ---
    CALL DELAY
    
    ; --- LED 左移 ---
    RLCA
    CP $00
    JR NZ, MAIN_LOOP
    LD A, $01
    JR MAIN_LOOP
```

---

## 9. 项目文件结构

```raw
MC/
│
├── Microcomputer/                    # Quartus 主工程
│   ├── Microcomputer.vhd             # 顶层文件（系统整合）
│   ├── Microcomputer.qpf             # Quartus 项目文件
│   ├── Microcomputer.qsf             # Quartus 设置文件
│   ├── Z80_BASIC_ROM.vhd             # ROM 模块（8KB）
│   ├── InternalRam4K.vhd             # RAM 模块（4KB）
│   ├── BootROM.vhd                   # 备用 ROM 模块
│   ├── *.cmp / *.qip                 # 模块配置文件
│   ├── db/                           # Quartus 编译数据库
│   ├── incremental_db/               # 增量编译数据
│   └── output_files/
│       └── Microcomputer.sof         # FPGA 配置文件（烧录用）
│
├── Components/                       # 外设模块（VHDL 源码）
│   ├── Z80/                          # Z80 CPU 软核（T80s）
│   │   ├── T80.vhd / T80s.vhd        # CPU 核心
│   │   ├── T80_ALU.vhd               # 算术逻辑单元
│   │   ├── T80_MCode.vhd             # 微码控制器
│   │   ├── T80_Pack.vhd              # 包定义
│   │   └── T80_Reg.vhd / T80_RegX.vhd # 寄存器组
│   │
│   ├── UART/                         # 串口通信模块
│   │   ├── bufferedUART.vhd          # 6850 ACIA 兼容 UART
│   │   └── aaron.vhd                 # LED 输出模块
│   │
│   └── PWM/                          # PWM 脉宽调制模块（v2.0 新增）
│       └── PWM.vhd                   # 8 通道可编程 PWM 发生器
│
├── ROMS/
│   └── Z80/
│       ├── basic.asm                 # Bootloader 汇编源码
│       ├── BASIC.HEX                 # 编译后的 ROM 初始化文件
│       ├── Z80_BASIC_ROM.vhd         # ROM 封装模块
│       └── run.cmd                   # 编译命令（双击运行）
│
├── Z80Project/                       # 用户程序（汇编示例）
│   ├── project.asm                   # 用户程序源码（含 PWM 控制）
│   ├── build.cmd                     # 编译命令
│   ├── load.cmd                      # 下载命令
│   ├── Object/                       # 编译输出
│   │   ├── project.bin               # 二进制文件
│   │   └── project.hex               # HEX 文件
│   └── runasm.cmd                    # 运行编译
│
├── compile/                          # C 语言开发环境（v2.0 新增目录）
│   ├── Project.c                     # C 语言示例（含 PWM 控制）
│   ├── Project.asm                   # SDCC 编译生成的汇编
│   └── compile.cmd                   # 编译命令
│
├── tools/                            # 辅助工具
│   ├── download.c / download.exe     # 串口下载工具
│   └── Transform.c / Transform.exe   # HEX 转 BIN 工具
│
└── UserManual.md                     # 本技术文档（v2.0）
```

### 9.1 v2.0 文件变更清单

| 变更类型 | 文件路径 | 说明 |
|---------|---------|------|
| **新增** | `Components/PWM/PWM.vhd` | PWM 脉宽调制模块 VHDL 源码 |
| **修改** | `Microcomputer/Microcomputer.vhd` | 顶层增加 PWM 实例化、引脚、译码、数据选择 |
| **修改** | `Z80Project/project.asm` | 示例程序增加 PWM 控制代码 |
| **新增** | `compile/Project.c` | C 语言版本 PWM 示例程序 |
| **新增** | `compile/Project.asm` | SDCC 编译生成的汇编文件 |
| **新增** | `compile/compile.cmd` | C 语言编译命令脚本 |
| **修改** | `UserManual.md` | 本文档升级至 v2.0 |

### 9.2 关键文件说明

| 文件 | 说明 |
|------|------|
| `Microcomputer/Microcomputer.vhd` | 顶层文件，整合所有模块（含 PWM） |
| `Microcomputer/output_files/Microcomputer.sof` | FPGA 配置文件 |
| `Components/PWM/PWM.vhd` | **PWM 核心模块（v2.0 新增）** |
| `ROMS/Z80/basic.asm` | Bootloader 源码（上电自动运行） |
| `ROMS/Z80/BASIC.HEX` | Bootloader 编译输出，用于初始化 ROM |
| `Z80Project/project.asm` | 用户程序示例（含 PWM 控制） |
| `compile/Project.c` | **C 语言 PWM 示例（v2.0 新增）** |
| `Z80Project/build.cmd` | 编译用户程序 |
| `Z80Project/load.cmd` | 下载用户程序到 FPGA |

---

## 10. 开发工具链

### 10.1 工具列表

| 工具 | 用途 | 获取方式 |
|------|------|---------|
| Quartus Prime 16.0+ | FPGA 综合/布局布线/烧录 | Intel/Altera 官网 |
| sjasmplus | Z80 汇编编译器 | GitHub 开源 |
| SDCC | Z80 C 语言编译器（v2.0 新增） | sdcc.sourceforge.net |
| 串口助手 | 串口通信/下载程序 | SSCOM / Putty / Arduino IDE |

### 10.2 编译流程

**编译 Bootloader（更新 ROM 内容）**：

```bash
cd ROMS/Z80
.\run.cmd              # 运行 sjasmplus basic.asm --hex=BASIC.HEX
```

**编译用户程序（汇编）**：

```bash
cd Z80Project
.\build.cmd            # 编译 project.asm → Object/project.hex
```

**编译用户程序（C 语言，v2.0 新增）**：

```bash
cd compile
.\compile.cmd          # SDCC 编译 Project.c → Project.asm → Project.hex
```

**烧录 FPGA**：
1. 打开 Quartus Prime
2. 打开项目 `Microcomputer/Microcomputer.qpf`
3. `Processing → Start Compilation`
4. `Tools → Programmer → 选择 .sof → Start`

**下载用户程序**：

```bash
cd Z80Project
.\load.cmd             # 通过串口下载程序
```

### 10.3 完整工作流程

```raw
1. 修改 basic.asm
       │
       ▼
2. 运行 run.cmd → 生成 BASIC.HEX
       │
       ▼
3. 在 Quartus 中重新编译项目
       │
       ▼
4. 烧录 .sof 到 FPGA
       │
       ▼
5. 上电，看到 "Z80 Boot\nOK\n"
       │
       ▼
6. 修改 project.asm（或 Project.c）
       │
       ▼
7. 运行 build.cmd（或 compile.cmd）→ 生成 .hex
       │
       ▼
8. 发送 .hex 到串口
       │
       ▼
9. 看到 "Jump $2000" → 用户程序运行
```

### 10.4 编译选项说明

**sjasmplus 编译选项**：

| 选项 | 说明 |
|------|------|
| `--hex=文件名.hex` | 输出 Intel HEX 格式文件 |
| `-s` | 生成符号表 |
| `-l` | 生成列表文件 |

**SDCC 编译选项**（v2.0 新增）：

| 选项 | 说明 |
|------|------|
| `-mz80` | 目标处理器为 Z80 |
| `--code-loc 0x2000` | 代码段起始地址 $2000 |
| `--data-loc 0x2E00` | 数据段起始地址 $2E00 |

---

## 11. 常见问题

### Q1: 串口没有输出？

- 检查串口参数：115200, 8N1
- 检查 USB 转串口驱动是否安装
- 检查 FPGA 是否已烧录并复位
- 检查串口号是否正确

### Q2: 下载程序后显示 "ERROR"？

- 检查 HEX 文件格式是否正确
- 检查地址是否在 $2000-$2FFF 范围内
- 检查 HEX 文件校验和是否正确
- 避免发送过程中混入其他字符

### Q3: 用户程序运行但 LED 不亮？

- 确认程序中有 `OUT ($90), A` 指令
- 确认 FPGA 板 LED 的极性（低电平点亮需 `CPL` 取反）
- 确认地址译码中 A[7:1] = "1001000"（即 $90-$91）

### Q4: 如何让程序在 RAM 中运行？

用户程序必须：
1. 使用 `ORG $2000` 指定起始地址
2. 用 `LD SP, $2FFF` 初始化栈指针
3. 编译成 Intel HEX 格式
4. 通过串口下载

### Q5: PWM 模块没有输出？（v2.0 新增）

- 检查 `clk_pwm` 引脚是否连接了有效的时钟源
- 确认 `CTRL(0)=1`（使能 PWM）
- 检查 `PRD` 是否大于 0（PRD=0 时频率很高，肉眼/万用表可能观察不到）
- 使用示波器观察 pwmout 引脚
- 尝试 `CTRL(1)=0` 切换极性

### Q6: PWM 占空比调节不明显？

- PWM 输出是 8 路同步的，所有通道占空比相同
- PRD 值越大，占空比调节步数越多（256 级），变化越平滑
- PRD 值越小，PWM 频率越高，但占空比调节分辨率越低

### Q7: ROM 和 RAM 的地址范围？

- ROM：$0000-$1FFF（8KB，只读，存放 Bootloader）
- RAM：$2000-$2FFF（4KB，读写，存放用户程序和栈）
- 用户程序下载到 RAM 的 $2000 地址开始执行

### Q8: 如何重置系统？

按下 FPGA 板上的复位按钮（n_reset 引脚），系统将从 $0000 重新执行 Bootloader。

### Q9: 用户程序最大可以多大？

最多 3840 字节（$2000-$2EFF），栈空间占用 253 字节（$2F00-$2FFF）。

### Q10: 为什么我的程序下载后不运行？

- 检查 HEX 地址是否以 $2000 开头
- 检查程序是否以 `ORG $2000` 开始
- 检查程序是否在 `END` 之前定义了入口标签
- 确保 Bootloader 输出了 "Jump $2000"

### Q11: 汇编和 C 语言如何选择？（v2.0 新增）

| | 汇编 | C 语言（SDCC） |
|------|------|---------|
| 代码体积 | 小（精简） | 较大（有运行时库开销） |
| 运行速度 | 快 | 较慢（有函数调用开销） |
| 开发效率 | 低 | 高 |
| 硬件控制 | 精确 | 间接 |
| 推荐场景 | 时序敏感、代码精简 | 逻辑复杂、快速开发 |

### Q12: C 语言编译报错？（v2.0 新增）

- 确认已安装 SDCC 并添加到 PATH
- 确认使用 `-mz80` 选项指定目标处理器
- 确认 `--code-loc 0x2000` 和 `--data-loc 0x2E00` 地址设置正确
- 硬件寄存器使用 `volatile` 关键字声明

---

## 附录

### A. 参考资源

- [Z80 CPU 指令集手册](http://www.z80.info/zip/z80cpu_um.pdf)
- [Grant Searle's Multicomp Project](http://searle.hostei.com/grant/Multicomp/index.html)
- [sjasmplus 文档](https://github.com/z00m128/sjasmplus)
- [SDCC 编译器文档](http://sdcc.sourceforge.net/doc/)
- [6850 ACIA 数据手册](http://pdf.datasheetcatalog.com/datasheets2/14/142829_1.pdf)

### B. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | - | 初始版本：Z80 CPU + ROM + RAM + UART + LED |
| v2.0 | - | **新增 PWM 模块**：8 通道可编程脉宽调制输出，独立时钟域，4 个 I/O 寄存器；新增 C 语言（SDCC）开发环境支持 |

### C. 许可证

本项目基于 Grant Searle 的开源 Multicomp 项目构建，遵循开源许可证。详见各模块文件头的版权声明。

---

*文档版本：v2.0*
*文档生成日期：2026年5月14日*
