# MC（Micro Computer）v1.0 用户手册

## 基于 FPGA 的 Z80 微型计算机系统

---

## 目录

1. [项目概述](#1-项目概述)
2. [硬件架构](#2-硬件架构)
3. [系统配置](#3-系统配置)
4. [内存映射](#4-内存映射)
5. [I/O 映射](#5-io-映射)
6. [Bootloader 使用说明](#6-bootloader-使用说明)
7. [用户程序开发](#7-用户程序开发)
8. [项目文件结构](#8-项目文件结构)
9. [开发工具链](#9-开发工具链)
10. [常见问题](#10-常见问题)

---

## 1. 项目概述

### 1.1 简介

MC（Micro Computer）是一个基于 **Z80 兼容软核 CPU（T80s）** 的微型计算机系统，在 **Altera Cyclone IV FPGA** 上实现。系统包含 8KB ROM、4KB RAM、UART 串口和 LED 输出接口。

### 1.2 主要特性

| 特性 | 参数 |
|------|------|
| CPU | T80s（Z80 兼容软核），10MHz |
| ROM | 8KB（$0000-$1FFF），存放 Bootloader |
| RAM | 4KB（$2000-$2FFF），存放用户程序 |
| 串口 | 6850 ACIA 兼容 UART，115200 baud，16 字节 FIFO |
| LED | 8 位并行输出，端口 $90 |
| 主时钟 | 50MHz FPGA 晶振 |
| 下载方式 | 串口下载 Intel HEX 格式文件 |

### 1.3 系统框图

```raw
                    50MHz 晶振
                        │
                        ▼
               ┌────────────────┐
               │   时钟分频器     │
               │ CPU: 10MHz      │
               │ UART: 115200    │
               └────────┬───────┘
                        │
┌───────────────────────────────────────────┐
│  Z80 CPU (T80s 软核)                      │
│  ┌─────────────────────────────────────┐  │
│  │ 地址总线 A[15:0]                     │  │
│  │ 数据总线 D[7:0]                      │  │
│  │ 控制总线 MREQ/IORQ/RD/WR            │  │
│  └─────────────────────────────────────┘  │
└──────┬──────────┬──────────┬──────────────┘
       │          │          │
       ▼          ▼          ▼
   ┌──────┐  ┌──────┐  ┌──────────┐
   │ ROM  │  │ RAM  │  │ UART     │
   │8KB   │  │4KB   │  │ $80-$81  │
   │只读   │  │读写   │  │ 115200   │
   └──────┘  └──────┘  └──────────┘
                           │
                       ┌──────┐
                       │ LED  │
                       │ $90  │
                       └──────┘
```

---

## 2. 硬件架构

### 2.1 FPGA 引脚分配

| 引脚 | 方向 | 连接 |
|------|------|------|
| n_reset | 输入 | 复位按钮（低有效） |
| clk | 输入 | 50MHz 晶振 |
| rxd1 | 输入 | USB 转串口 TX（FPGA 接收） |
| txd1 | 输出 | USB 转串口 RX（FPGA 发送） |
| leds[7:0] | 输出 | 8 个 LED |

### 2.2 顶层信号（Microcomputer.vhd）

```vhdl
entity Microcomputer is
    port(
        n_reset : in std_logic;                     -- 复位（低有效）
        clk     : in std_logic;                     -- 50MHz 主时钟
        rxd1    : in std_logic;                     -- UART 接收
        txd1    : out std_logic;                    -- UART 发送
        leds    : out std_logic_vector(7 downto 0)  -- 8位 LED
    );
end Microcomputer;
```

### 2.3 CPU 配置（T80s 软核）

| 参数 | 值 | 说明 |
|------|-----|------|
| mode | 1 | Z80 兼容模式 |
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
serialClock = serialClkCount(15)
频率 = 50MHz × 2416 / 65536 ≈ 1.843MHz
波特率 = 1.843MHz / 16 ≈ 115200 baud
```

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
```

I/O 译码只用 **A[7:1]**（7 位），**A[0]** 用于寄存器选择，所以每个外设占用 2 个地址。

### 2.6 数据总线多路选择

```vhdl
cpuDataIn <=
    interface1DataOut when n_interface1CS = '0' else  -- UART 优先级最高
    basRomData         when n_basRomCS = '0' else      -- ROM
    internalRam1DataOut when n_internalRam1CS = '0' else -- RAM
    x"FF";                                              -- 默认值
```

---

## 3. 系统配置

### 3.1 Quartus 项目配置

- **项目文件**：`Microcomputer/Microcomputer.qpf`
- **设置文件**：`Microcomputer/Microcomputer.qsf`
- **目标器件**：Cyclone IV EP4CE10E22C8（或其他兼容器件）
- **综合工具**：Quartus Prime 16.0

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
| $001C | 跳转用户程序 | JP $2000 |
| $0020-$0038 | MSG_BOOT | "Z80 Boot\nOK\n" |
| $003D-$0053 | MSG_DONE | "Jump $2000\n" |
| $0055-$006B | MSG_ERR | "ERROR\n" |
| $006B-$01FF | 子程序 | UART_GETCHAR/PRINT_STR/A2H/RD_BYTE 等 |

### 4.2 RAM 用户程序区（$2000-$2EFF）

| 地址 | 用途 | 可用大小 |
|------|------|---------|
| $2000-$2EFF | 用户程序代码/数据 | 3840 字节 |
| $2F00 | BYTE_COUNT 变量 | 1 字节 |
| $2F01-$2F02 | EXT_ADDR 变量 | 2 字节 |
| $2F03-$2FFF | 栈空间（向下增长） | 253 字节 |

---

## 5. I/O 映射

### 5.1 外设地址总览

| I/O 地址 | 外设 | 读 | 写 |
|---------|------|-----|-----|
| $80 | UART 控制 | 状态寄存器 | 控制寄存器 |
| $81 | UART 数据 | 接收数据 | 发送数据 |
| $90 | LED | - | LED 输出 |

### 5.2 UART（$80-$81）

**外设模块**：`Components/UART/bufferedUART.vhd`

**标准 6850 ACIA 兼容**，其寄存器基于 **A[0]（regSel）** 选择：

| regSel（A0） | 读 | 写 |
|:-----------:|-----|-----|
| 0（$80） | 状态寄存器 | 控制寄存器 |
| 1（$81） | 接收数据寄存器 | 发送数据寄存器 |

#### 状态寄存器（$80 读）

| Bit | 名称 | 说明 |
|-----|------|------|
| 0 | RDRF | 接收数据满（1=可读） |
| 1 | TDRE | 发送寄存器空（1=可写） |
| 2 | n_DCD | 数据载波检测 |
| 3 | n_CTS | 清除发送 |
| 4 | - | 未使用（0） |
| 5 | - | 未使用（0） |
| 6 | - | 未使用（0） |
| 7 | IRQ | 中断请求 |

#### 控制寄存器（$80 写）

| Bit | 名称 | 说明 |
|-----|------|------|
| 7 | Rx 中断使能 | 1=使能 |
| 6-5 | Tx 控制 | 00=RTS 低 |
| 4-2 | - | 未使用 |
| 1-0 | 复位 | 11=复位 UART |

#### Z80 驱动示例

```asm
; --- UART 初始化 ---
LD A, $03
OUT ($80), A         ; 写入控制寄存器
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
    RET
```

### 5.3 LED（$90-$91）

**外设模块**：`Components/UART/aaron.vhd`

**功能**：8 位并行输出，驱动 FPGA 板上的 8 个 LED。

**写操作**：
```asm
OUT ($90), A    ; A[7:0] 对应 LED7-LED0
```

**复位初始值**：`$55`（LED 交替亮灭：0=亮, 1=灭）

| LED7 | LED6 | LED5 | LED4 | LED3 | LED2 | LED1 | LED0 |
|------|------|------|------|------|------|------|------|
| 0 | 1 | 0 | 1 | 0 | 1 | 0 | 1 |

**注意**：LED 输出**低电平点亮**，写入值需要取反。示例：
```asm
CPL              ; A 取反
OUT ($90), A     ; 输出到 LED
CPL              ; 恢复 A
```

---

## 6. Bootloader 使用说明

### 6.1 概述

Bootloader 存储在 ROM（$0000-$01FF）中，上电后自动运行，通过串口接收 Intel HEX 格式的用户程序，写入 RAM 后跳转执行。

### 6.2 上电启动流程

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

### 6.3 Intel HEX 格式说明

Bootloader 接收标准 Intel HEX 格式，所有行连在一起发送（无需换行）：

```raw
:BBAAAATT[数据...]CC
```

| 字段 | 字节数 | 说明 |
|------|--------|------|
| : | 1 | 起始标志 |
| BB | 1 | 数据字节数 |
| AAAA | 2 | 起始地址 |
| TT | 1 | 类型（00=数据，01=结束） |
| 数据 | BB | 实际数据 |
| CC | 1 | 校验和 |

**注意**：地址必须包含 $2000 偏移（直接对应 RAM 地址）。

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
| 8F | 校验和 | 验证数据完整性 |

### 6.4 发送步骤

**使用串口助手**：
1. 设置串口参数：115200 baud, 8数据位, 1停止位, 无校验
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

### 6.5 快捷键

| 按键 | 功能 |
|------|------|
| ESC（0x1B） | 退出下载模式 |

---

## 7. 用户程序开发

### 7.1 开发环境

- **汇编器**：sjasmplus（Z80 汇编器）
- **文本编辑器**：任何文本编辑器（VS Code 推荐）
- **串口工具**：任意串口助手（115200, 8N1）

### 7.2 程序模板

```asm
; ============================================================
; 用户程序模板
; 编译: ORG $2000（下载到 RAM 运行）
; ============================================================

UART_DATA   EQU $81      ; UART 数据端口
UART_STAT   EQU $80      ; UART 状态端口
LED_PORT    EQU $90      ; LED 输出端口

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
    
    ; 示例：循环等待
LOOP:
    JR LOOP               ; 死循环

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

### 7.3 编译

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

### 7.4 下载

使用 load.cmd 脚本：
```raw
.\load.cmd
```

或使用串口助手发送 `Object/project.hex` 的内容。

### 7.5 系统常量定义

```asm
; --- 系统常量（用户程序中使用） ---
UART_DATA   EQU $81      ; UART 数据端口
UART_STAT   EQU $80      ; UART 状态端口
LED_PORT    EQU $90      ; LED 输出端口
RAM_START   EQU $2000    ; RAM 起始地址（用户程序入口）
STACK_TOP   EQU $2FFF    ; 栈顶地址
```

### 7.6 延时子程序示例

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

### 7.7 完整示例：流水灯 + 串口输出

参见 `Z80Project/project.asm`，该程序实现：
- 上电输出 "Z80 Program Started!"
- LED 流水灯效果
- 串口实时输出当前 LED 状态值（十六进制）

---

## 8. 项目文件结构

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
├── Components/                       # 外设模块
│   └── UART/
│       ├── bufferedUART.vhd          # UART 串口模块
│       ├── aaron.vhd                 # LED 输出模块
│       ├── T80s.vhd / T80s_pack.vhd  # Z80 CPU 软核
│       └── ....vhd                   # T80s 相关文件
│
├── ROMS/
│   └── Z80/
│       ├── basic.asm                 # Bootloader 汇编源码
│       ├── BASIC.HEX                 # 编译后的 ROM 初始化文件
│       ├── Z80_BASIC_ROM.vhd         # ROM 封装模块
│       ├── Z80_BASIC_ROM.qip         # ROM 配置文件
│       ├── Z80_BASIC_ROM.cmp         # ROM 编译信息
│       └── run.cmd                   # 编译命令（双击运行）
│
├── Z80Project/                       # 用户程序
│   ├── project.asm                   # 用户程序源码（流水灯）
│   ├── build.cmd                     # 编译命令
│   ├── load.cmd                      # 下载命令
│   ├── Object/                       # 编译输出
│   │   ├── project.bin               # 二进制文件
│   │   └── project.hex               # HEX 文件（自动删除）
│   └── runasm.cmd                    # 运行编译
│
└── tools/
    ├── download.c / download.exe     # 串口下载工具
    └── Transform.c / Transform.exe   # HEX 转 BIN 工具
```

### 8.1 关键文件说明

| 文件 | 说明 |
|------|------|
| `Microcomputer/Microcomputer.vhd` | 顶层文件，整合所有模块 |
| `Microcomputer/output_files/Microcomputer.sof` | FPGA 配置文件 |
| `ROMS/Z80/basic.asm` | Bootloader 源码（上电自动运行） |
| `ROMS/Z80/BASIC.HEX` | Bootloader 编译输出，用于初始化 ROM |
| `ROMS/Z80/run.cmd` | 编译 bootloader（双击运行） |
| `Z80Project/project.asm` | 用户程序模板/示例 |
| `Z80Project/build.cmd` | 编译用户程序 |
| `Z80Project/load.cmd` | 下载用户程序到 FPGA |

---

## 9. 开发工具链

### 9.1 工具列表

| 工具 | 用途 | 获取方式 |
|------|------|---------|
| Quartus Prime 16.0 | FPGA 综合/布局布线/烧录 | Intel/Altera 官网 |
| sjasmplus | Z80 汇编编译器 | GitHub 开源 |
| 串口助手 | 串口通信/下载程序 | SSCOM/Putty/Arduino IDE |

### 9.2 编译流程

**编译 Bootloader（更新 ROM 内容）**：
```bash
cd ROMS/Z80
.\run.cmd              # 运行 sjasmplus basic.asm --hex=BASIC.HEX
```

**编译用户程序**：
```bash
cd Z80Project
.\build.cmd            # 编译 project.asm → Object/project.hex
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

### 9.3 完整工作流程

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
6. 修改 project.asm
       │
       ▼
7. 运行 build.cmd → 生成 project.hex
       │
       ▼
8. 发送 project.hex 到串口
       │
       ▼
9. 看到 "Jump $2000" → 用户程序运行
```

---

## 10. 常见问题

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
- LED 是低电平点亮，需要 `CPL` 取反
- 确认地址译码中 A[7:1] = "1001000"（即 $90-$91）

### Q4: 如何让程序在 RAM 中运行？

用户程序必须：
1. 使用 `ORG $2000` 指定起始地址
2. 用 `LD SP, $2FFF` 初始化栈指针
3. 编译成 Intel HEX 格式
4. 通过串口下载

### Q5: ROM 和 RAM 的地址范围？

- ROM: $0000-$1FFF（8KB，只读）
- RAM: $2000-$2FFF（4KB，读写）
- 用户程序下载到 RAM 的 $2000 地址开始

### Q6: 如何重置系统？

按下 FPGA 板上的复位按钮（n_reset 引脚），系统将从 $0000 重新执行 bootloader。

### Q7: 用户程序最大可以多大？

最多 3840 字节（$2000-$2EFF），栈空间占用 253 字节（$2F00-$2FFF）。

### Q8: 为什么我的程序下载后不运行？

- 检查 HEX 地址是否以 $2000 开头
- 检查程序是否以 `ORG $2000` 开始
- 检查程序是否在 `END` 之前定义了入口标签
- 确保 bootloader 输出了 "Jump $2000"

---

## 附录

### A. 参考资源

- [Z80 CPU 指令集手册](http://www.z80.info/zip/z80cpu_um.pdf)
- [Grant Searle's Multicomp Project](http://searle.hostei.com/grant/Multicomp/index.html)
- [sjasmplus 文档](https://github.com/z00m128/sjasmplus)
- [6850 ACIA 数据手册](http://pdf.datasheetcatalog.com/datasheets2/14/142829_1.pdf)

### B. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | - | 初始版本 |

### C. 许可证

本项目基于 Grant Searle 的开源 Multicomp 项目构建，遵循开源许可证。详见各模块文件头的版权声明。

---

*文档生成日期：2026年5月14日*
