; ============================================================
; basic.asm - Z80 HEX Downloader Bootloader
;
; 功能: 通过 UART 接收 Intel HEX 文件
;       240 字节环形缓冲区，支持一次性发送所有数据
;       解析后写入 RAM ($2000-$2FFF)
;       完成后跳转到用户程序入口
;
; 串口格式:
;   直接发送完整的 Intel HEX 文件内容（所有行连在一起）
;   无需换行、无需等待、无需 CR/LF
;   地址已包含 $2000 偏移（直接对应 RAM 地址）
;   示例: :1020000031001B11...4D:102010002100...B6......:00000001FF
;
; 编译: sjasmplus basic.asm --hex=BASIC.HEX
; ============================================================

; ============================================================
; 系统常量
; ============================================================
UART_DATA   EQU $81     ; UART 数据端口
UART_STAT   EQU $80     ; UART 状态端口 (bit0=可读, bit1=可写)
RAM_START   EQU $2000   ; RAM 起始地址
STACK_TOP   EQU $2FFF   ; 栈顶

; ============================================================
; 变量区 (RAM $2F00-$2F03)
; ============================================================
BYTE_COUNT  EQU $2F00   ; 当前行的数据字节数
EXT_ADDR    EQU $2F01   ; 扩展地址 (2字节)

; ============================================================
; 复位入口 $0000
; ============================================================
    ORG $0000

RESET:
    DI
    LD SP, STACK_TOP

    ; --- UART 初始化 ---
    LD A, $03
    OUT (UART_STAT), A
    LD A, $15
    OUT (UART_STAT), A

    ; --- 输出欢迎信息 ---
    LD HL, MSG_BOOT
    CALL PRINT_STR

    ; --- 进入 HEX 下载 ---
    CALL HEX_LOADER

    ; --- 下载完成，跳转 ---
    LD HL, MSG_DONE
    CALL PRINT_STR
    JP RAM_START

; ============================================================
; 字符串
; ============================================================
MSG_BOOT:  
    DB 0Dh, 0Ah              ; 换行
    DB "Z80 Boot", 0Dh, 0Ah  ; 显示Z80 Boot
    DB "OK", 0Dh, 0Ah        ; 显示OK
    DB 0                     ; 结束字符串

MSG_DONE:
    DB 0Dh, 0Ah               ; 换行
    DB "Jump $2000", 0Dh, 0Ah ; 显示Jump $2000
    DB 0                      ; 结束字符串

MSG_ERR:  
    DB 0Dh, 0Ah               ; 换行
    DB "ERROR", 0Dh, 0Ah      ; 显示ERROR
    DB 0                      ; 结束字符串

; ============================================================
; UART 驱动 - 直接轮询，无缓冲区
; ============================================================

; 发送字符 A -> UART
UART_PUTCHAR:
    PUSH AF
_UP_W:
    IN A, (UART_STAT)
    BIT 1, A
    JR Z, _UP_W
    POP AF
    OUT (UART_DATA), A
    RET

; 接收字符 -> A (忙等，带回显)
UART_GETCHAR:
    IN A, (UART_STAT)
    BIT 0, A
    JR Z, UART_GETCHAR
    IN A, (UART_DATA)
    AND $7F
    RET

; 输出字符串 HL (0结尾)
PRINT_STR:
    PUSH AF
    PUSH HL
_PS_L:
    LD A, (HL)
    CP 0
    JR Z, _PS_E
    CALL UART_PUTCHAR
    INC HL
    JR _PS_L
_PS_E:
    POP HL
    POP AF
    RET

; ============================================================
; ASCII -> 4-bit 十六进制
; ============================================================
A2H:
    CP '0'
    JR C, _A2H_E
    CP '9'+1
    JR C, _A2H_09
    CP 'A'
    JR C, _A2H_E
    CP 'F'+1
    JR C, _A2H_AF
    CP 'a'
    JR C, _A2H_E
    CP 'f'+1
    JR C, _A2H_af
    JR _A2H_E
_A2H_09:
    SUB '0'
    RET
_A2H_AF:
    SUB 'A' - 10
    RET
_A2H_af:
    SUB 'a' - 10
    RET
_A2H_E:
    LD A, $FF
    RET

; ============================================================
; 读 1 字节 (2个十六进制字符) -> A
; ============================================================
RD_BYTE:
    CALL UART_GETCHAR  ; 高4位
    CALL A2H
    RLCA
    RLCA
    RLCA
    RLCA
    LD B, A
    CALL UART_GETCHAR  ; 低4位
    CALL A2H
    OR B
    RET

; ============================================================
; HEX 加载主程序
; ============================================================
HEX_LOADER:
    XOR A
    LD (EXT_ADDR), A
    LD (EXT_ADDR+1), A

; --- 等待 ':' ---
_HL_W:
    CALL UART_GETCHAR
    CP ':'
    JR Z, _HL_P
    CP 1Bh
    JR NZ, _HL_W
    RET

; --- 解析一行 ---
_HL_P:
    ; BB: 字节数
    CALL RD_BYTE
    LD (BYTE_COUNT), A
    LD B, A             ; B = 数据字节数

    ; AAAA: 地址
    CALL RD_BYTE
    LD D, A             ; D = 地址高
    CALL RD_BYTE
    LD E, A             ; E = 地址低

    ; TT: 类型
    CALL RD_BYTE
    LD C, A

    ; 根据类型处理
    LD A, C
    CP 01h
    JP Z, _HL_END       ; 结束
    CP 00h
    JP Z, _HL_DATA      ; 数据
    CP 04h
    JP Z, _HL_EL        ; 扩展线性地址
    CP 02h
    JP Z, _HL_ES        ; 扩展段地址
    JP _HL_SKIP         ; 其他（包括03起始地址）

; --- 扩展线性地址 04 ---
_HL_EL:
    CALL RD_BYTE
    LD D, A
    CALL RD_BYTE
    LD E, A
    ; 跳过校验和
    CALL RD_BYTE
    ; 保存扩展地址
    LD A, D
    LD (EXT_ADDR), A
    LD A, E
    LD (EXT_ADDR+1), A
    JP _HL_NEXT

; --- 扩展段地址 02 ---
_HL_ES:
    CALL RD_BYTE
    LD D, A
    CALL RD_BYTE
    LD E, A
    ; 跳过校验和
    CALL RD_BYTE
    ; 转换段地址到线性地址 (<< 4)
    LD HL, 0
    LD H, D
    LD L, E
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD A, H
    LD (EXT_ADDR), A
    LD A, L
    LD (EXT_ADDR+1), A
    JR _HL_NEXT

; --- 数据记录 00 ---
_HL_DATA:
    ; 目标地址 = EXT_ADDR + 行地址（已包含 $2000 偏移）
    LD HL, (EXT_ADDR)
    ADD HL, DE
    EX DE, HL           ; DE = 最终写入地址

    ; 范围检查: $2000-$2FFF
    LD A, D
    CP $20
    JP C, _HL_ERR
    CP $30
    JP NC, _HL_ERR

    ; 读数据字节并写入 RAM
    LD A, (BYTE_COUNT)
    LD C, A             ; C = 数据字节计数

_HL_DL:
    LD A, C
    CP 0
    JR Z, _HL_DE

    CALL RD_BYTE
    LD (DE), A          ; 写入 RAM
    INC DE
    DEC C
    JR _HL_DL

_HL_DE:
    ; 跳过校验和
    CALL RD_BYTE

    ; 进度点
    LD A, '.'
    CALL UART_PUTCHAR
    JR _HL_NEXT

; --- 跳过数据区（未知类型，简单跳过） ---
_HL_SKIP:
    LD A, (BYTE_COUNT)
    LD C, A
_HL_SL:
    LD A, C
    CP 0
    JR Z, _HL_SC
    CALL RD_BYTE
    DEC C
    JR _HL_SL
_HL_SC:
    CALL RD_BYTE       ; 跳过校验和
    JR _HL_NEXT

; --- 错误 ---
_HL_ERR:
    LD HL, MSG_ERR
    CALL PRINT_STR
    JR _HL_NEXT

; --- 下一行 ---
_HL_NEXT:
    JP _HL_W

; --- 文件结束 ---
_HL_END:
    ; 跳过校验和
    CALL RD_BYTE
    RET

; ============================================================
    END RESET