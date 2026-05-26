; ============================================================
; project.asm
; Z80 测试程序 - 通过串口输出信息并控制LED
; 
; 功能: 上电后通过串口输出信息，LED闪烁
; 编译: ORG $2000 (下载到 RAM 运行)
; ============================================================

; ============================================================
; 系统常量定义
; ============================================================
UART_DATA   EQU $81      ; UART 数据端口
UART_STAT   EQU $80      ; UART 状态端口 (bit0=可读, bit1=可写)
LED_PORT    EQU $90      ; LED 输出端口
PWM_CTRL    EQU $84      ; PWM 控制端口
PWM_PRD     EQU $85      ; PWM 周期端口
PWM_CCR     EQU $86      ; PWM 占空比端口
PWM_CNT     EQU $87      ; PWM 计数器端口

; ============================================================
; 程序入口 - 必须从 $2000 开始
; ============================================================
    ORG $2000

;程序入口点
START: 
    ; --- 初始化栈指针 ---
    LD SP, $2FFF      ; 设置栈顶地址,堆栈段为$2F00-$2FFF
    
    ; --- 输出启动信息 ---
    LD HL, MSG_START  ; 传递字符串首地址
    CALL PRINT_STRING ; 调用打印字符串子程序
    
    ; --- 主循环：LED流水灯 + 串口输出 ---
    LD A, $01             ; 初始 LED 值 (bit0亮)
    LD B, 0FFH            ; 初始占空比为0%

MAIN_LOOP:
    ; PWM输出
    push AF               ; 保存AF寄存器
    LD A, 00H             ; 00H为PWM关闭状态
    OUT (PWM_CTRL), A     ; 关闭PWM输出
    LD A, 0FFH            ; 设置PWM周期为255
    OUT (PWM_PRD), A      ; 设置PWM周期端口
    LD A, B               ; 当前占空比
    OUT (PWM_CCR), A      ; 设置PWM占空比端口
    LD A, 01H             ; 01H为PWM使能状态
    OUT (PWM_CTRL), A     ; 使能PWM输出

    LD A, B
    CP 0FFH
    JR NZ, _B_INCREASE   ; 如果占空比未到最大值
    LD B, 00             ; 重置占空比为0%
_B_INCREASE:
    INC B                ; 增加占空比
    
    CALL SEND_HEX        ; 发送当前占空比的十六进制值到串口
    LD A, ' '            ; 发送一个空格分隔
    CALL UART_PUTCHAR    ; 发送空格到串口

    pop AF               ; 恢复AF寄存器

    ; 输出LED
    CPL                  ; A值每位取反
    OUT (LED_PORT), A    ; 输出到LED端口
    CPL                  ; 恢复A值
    
    ; 延时
    CALL DELAY           ; 调用延时子程序
    
    ; 左移一位
    RLCA                 ; A左移一位，bit0移到bit7
    CP $00               ; 如果移出所有位
    JR NZ, MAIN_LOOP     ; 如果未移出所有位，继续循环
    LD A, $01            ; 重新从 bit0 开始
    JR MAIN_LOOP         ; 继续循环

; ============================================================
; 发送一个字节的十六进制值到串口
; 输入: A = 要发送的字节
; ============================================================
SEND_HEX:
    PUSH AF
    PUSH AF
    ; 高4位
    RRA
    RRA
    RRA
    RRA
    CALL HEX_TO_ASCII
    CALL UART_PUTCHAR
    ; 低4位
    POP AF
    CALL HEX_TO_ASCII
    CALL UART_PUTCHAR
    POP AF
    RET

; ============================================================
; 4位二进制转ASCII十六进制
; 输入: A = 低4位为要转换的值
; 输出: A = ASCII字符 ('0'-'9' 或 'A'-'F')
; ============================================================
HEX_TO_ASCII:
    AND $0F
    CP $0A
    JR C, _HTA_DIGIT
    ADD A, 'A' - 10
    RET
_HTA_DIGIT:
    ADD A, '0'
    RET

; ============================================================
; UART 发送一个字符
; 输入: A = 要发送的字符
; ============================================================
UART_PUTCHAR:
    PUSH AF
_UART_PUT_WAIT:
    IN A, (UART_STAT)
    BIT 1, A
    JR Z, _UART_PUT_WAIT
    POP AF
    OUT (UART_DATA), A
    RET

; ============================================================
; 输出字符串
; 输入: HL = 字符串首地址 (以 0 结尾)
; ============================================================
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
; 延时子程序
; ============================================================
DELAY:
    PUSH BC
    LD B, $FF
_DELAY_OUTER:
    LD C, 0DFH
_DELAY_INNER:
    DEC C
    JR NZ, _DELAY_INNER
    DEC B
    JR NZ, _DELAY_OUTER
    POP BC
    RET

; ============================================================
; 字符串常量
; ============================================================
MSG_START:
    DB 0Dh, 0Ah
    DB "Z80 Program Started!", 0Dh, 0Ah
    DB "LED Running...", 0Dh, 0Ah
    DB 0

; ============================================================
; 程序结束
; ============================================================
    END START