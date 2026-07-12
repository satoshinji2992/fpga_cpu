# asm/soc_firmware.s - complete board firmware for the RV32 SoC.
#
# The model is trained offline by scripts/train_mnist8.py:
#   hidden = relu(b1 + W1 * pixels); score = b2 + W2 * hidden
#
# Pixels are 8x8 binary ASCII values sent over UART. Weights and bias live in
# data RAM via src/cnn_weights.vh. The CPU performs inference with custom
# float32 instructions fmul32/fadd32/fgt32.

.equ UART_TX,   0x1000
.equ UART_RX,   0x1004
.equ UART_STAT, 0x1008
.equ LED_OUT,   0x100C
.equ IRQ_ENABLE,  0x1014
.equ IRQ_PENDING, 0x1018
.equ SDRAM_STATUS, 0x1040
.equ SDRAM_BASE,   0x10000000

.equ IMG,     0x000
.equ CALC_PTR, 0x0AC
.equ CALC_ERR, 0x0B0
.equ HIDDEN,  0x0B8     # 8 float32 activations
.equ W1,      0x100     # 8 * 64 float32 words
.equ B1,      0x900     # 8 float32 words
.equ W2,      0x920     # 10 * 8 float32 words
.equ B2,      0xA60     # 10 float32 words
.equ CALC_BUF, 0xA90    # 96-byte expression buffer

.equ PONG_BX,    0x040
.equ PONG_BY,    0x044
.equ PONG_DX,    0x048
.equ PONG_DY,    0x04C
.equ PONG_PAD,   0x050
.equ PONG_OVER,  0x054
.equ PONG_SCORE, 0x058
.equ IRQ_SAVE_T0, 0x060
.equ IRQ_SAVE_T1, 0x064
.equ IRQ_SAVE_T2, 0x068
.equ IRQ_UART_COUNT, 0x070
.equ IRQ_KEY_COUNT,  0x074
.equ IRQ_TIMER_COUNT, 0x078
.equ PONG_TICKS,      0x07C
.equ PONG_MODE,       0x080
.equ PONG_KEY,        0x084
.equ PERF_SNAP,       0x088  # 9 words: 0x088..0x0A8
.equ SELFTEST_BASE,   0xC00  # m0..m9, never shared with CNN/app state
.equ SELFTEST_STATUS, 0xC28  # first failing test number, zero means pass
.equ SELFTEST_SCRATCH,0xC40

start:
    li   sp, 0xF00
    la   t0, irq_handler
    csrw mtvec, t0
    jal  ra, boot_selftest
    li   t0, 0x800
    csrw mie, t0
    # Shell/CNN/Paint poll UART_RX. Keep UART IRQ disabled outside Pong so a
    # command byte cannot trap in the middle of read_cmd and corrupt its state.
    li   t0, 2
    li   t1, 0x1014
    sw   t0, 0(t1)
    li   t0, 8
    csrw mstatus, t0
    .puts "\nRV32 shell 50M BRAM5 R16\n"
    j    shell_loop

irq_handler:
    sw   t0, IRQ_SAVE_T0(x0)
    sw   t1, IRQ_SAVE_T1(x0)
    sw   t2, IRQ_SAVE_T2(x0)
    li   t0, 0x1018
    lw   t1, 0(t0)
    andi t2, t1, 1
    beqz t2, irq_check_key
    lw   t2, IRQ_UART_COUNT(x0)
    addi t2, t2, 1
    sw   t2, IRQ_UART_COUNT(x0)
    # In Pong mode the interrupt handler consumes UART input and leaves a
    # one-byte command for the game loop. Newline is intentionally ignored.
    lw   t2, PONG_MODE(x0)
    beqz t2, irq_check_key
    li   t0, UART_RX
    lw   t2, 0(t0)
    sw   x0, 0(t0)
    li   t0, 10
    beq  t2, t0, irq_check_key
    li   t0, 13
    beq  t2, t0, irq_check_key
    sw   t2, PONG_KEY(x0)
irq_check_key:
    andi t2, t1, 2
    beqz t2, irq_check_timer
    lw   t2, IRQ_KEY_COUNT(x0)
    addi t2, t2, 1
    sw   t2, IRQ_KEY_COUNT(x0)
    li   t0, 0x100C
    sw   t2, 0(t0)
    li   t0, 0x1018
irq_check_timer:
    andi t2, t1, 4
    beqz t2, irq_ack
    lw   t2, IRQ_TIMER_COUNT(x0)
    addi t2, t2, 1
    sw   t2, IRQ_TIMER_COUNT(x0)
    lw   t2, PONG_TICKS(x0)
    addi t2, t2, 1
    sw   t2, PONG_TICKS(x0)
    li   t0, 0x1018
irq_ack:
    li   t0, IRQ_PENDING
    sw   t1, 0(t0)
    lw   t0, IRQ_SAVE_T0(x0)
    lw   t1, IRQ_SAVE_T1(x0)
    lw   t2, IRQ_SAVE_T2(x0)
    mret

shell_loop:
    .puts "cpu> "
    jal  ra, read_cmd

    li   t0, 'h'
    beq  a0, t0, shell_help
    li   t0, '?'
    beq  a0, t0, shell_help
    li   t0, 's'
    beq  a0, t0, s_cmd
    li   t0, 'v'
    beq  a0, t0, version_cmd
    li   t0, 'i'
    beq  a0, t0, irq_cmd
    li   t0, '0'
    beq  a0, t0, mem0_cmd
    li   t0, '1'
    beq  a0, t0, mem1_cmd
    li   t0, '2'
    beq  a0, t0, mem2_cmd
    li   t0, '3'
    beq  a0, t0, mem3_cmd
    li   t0, 'm'
    beq  a0, t0, mem_cmd
    li   t0, 'p'
    beq  a0, t0, p_cmd
    li   t0, 'l'
    beq  a0, t0, led_cmd
    li   t0, 'c'
    beq  a0, t0, cnn_cmd
    li   t0, 'q'
    beq  a0, t0, shell_idle_dispatch
    .puts "?\n"
    j    shell_loop
shell_idle_dispatch:
    j    idle

shell_help:
    .puts "h ver s m0-m9 irq sdram p ledX cnn calc pong paint q\n"
    j    shell_loop

version_cmd:
    .puts "build 50M ALL-SELFTEST SYNC-BRAM50 IRQ-PONG R16\n"
    j    shell_loop

s_cmd:
    li   t0, 'd'
    beq  a1, t0, sdram_cmd
status_cmd:
    li   t0, SELFTEST_BASE
    lw   t1, 40(t0)
    bnez t1, status_fail
    .puts "OK selftest\n"
    j    shell_loop
status_fail:
    .puts "FAIL selftest code=0x"
    mv   a0, t1
    jal  ra, print_hex32
    .puts "\n"
    j    shell_loop

irq_cmd:
    .puts "irq uart=0x"
    lw   a0, IRQ_UART_COUNT(x0)
    jal  ra, print_hex32
    .puts " key=0x"
    lw   a0, IRQ_KEY_COUNT(x0)
    jal  ra, print_hex32
    .puts " timer=0x"
    lw   a0, IRQ_TIMER_COUNT(x0)
    jal  ra, print_hex32
    .puts "\n"
    j    shell_loop

sdram_cmd:
    li   t0, 0x1040
    lw   t1, 0(t0)
    andi t1, t1, 1
    beqz t1, sdram_not_ready
    li   t0, 0x10000000
    li   t1, 0x12345678
    sw   t1, 0(t0)
    li   t2, 0xA55A3CC3
    sw   t2, 4(t0)
    lw   t3, 0(t0)
    bne  t3, t1, sdram_fail_0
    lw   t3, 4(t0)
    bne  t3, t2, sdram_fail_4
    .puts "SDRAM PASS 64MiB\n"
    j    shell_loop
sdram_not_ready:
    .puts "SDRAM INIT BUSY\n"
    j    shell_loop
sdram_fail_0:
    .puts "SDRAM FAIL @0 expected=0x12345678 read=0x"
    j    sdram_fail_value
sdram_fail_4:
    .puts "SDRAM FAIL @4 expected=0xA55A3CC3 read=0x"
sdram_fail_value:
    mv   a0, t3
    jal  ra, print_hex32
    .puts "\n"
    j    shell_loop

mem0_cmd:
    li   a0, 0
    jal  ra, print_mem_word
    j    shell_loop
mem1_cmd:
    li   a0, 1
    jal  ra, print_mem_word
    j    shell_loop
mem2_cmd:
    li   a0, 2
    jal  ra, print_mem_word
    j    shell_loop
mem3_cmd:
    li   a0, 3
    jal  ra, print_mem_word
    j    shell_loop

mem_cmd:
    mv   t0, a4
    bnez t0, mem_has_arg
    mv   t0, a3
    bnez t0, mem_has_arg
    mv   t0, a1
mem_has_arg:
    li   t1, '0'
    blt  t0, t1, mem_bad
    li   t1, '9'
    blt  t1, t0, mem_bad
    addi a0, t0, -48
    jal  ra, print_mem_word
    j    shell_loop
mem_bad:
    .puts "use m0..m9\n"
    j    shell_loop

p_cmd:
    li   t0, 'o'
    bne  a1, t0, p_not_pong
    li   t0, 'n'
    bne  a2, t0, p_bad
    li   t0, 'g'
    beq  a3, t0, pong_dispatch
p_not_pong:
    li   t0, 'a'
    bne  a1, t0, p_not_paint
    li   t0, 'i'
    bne  a2, t0, p_bad
    li   t0, 'n'
    beq  a3, t0, paint_dispatch
p_not_paint:
    bnez a1, p_bad
    jal  ra, print_perf
    j    shell_loop
p_bad:
    .puts "use p, pong or paint\n"
    j    shell_loop
pong_dispatch:
    j    pong_start
paint_dispatch:
    j    paint_start

led_cmd:
    mv   t0, a4
    bnez t0, led_has_arg
    mv   t0, a3
    bnez t0, led_has_arg
    mv   t0, a1
led_has_arg:
    mv   a0, t0
    jal  ra, hex_char_to_nibble
    bltz a0, led_bad
    mv   s0, a0
    li   t0, 0x100C
    sw   a0, 0(t0)
    .puts "led=0x"
    mv   a0, s0
    jal  ra, print_nibble
    .puts "\n"
    j    shell_loop
led_bad:
    .puts "use led0..ledf\n"
    j    shell_loop

cnn_cmd:
    li   t0, 'n'
    beq  a1, t0, cnn_start
    li   t0, 'a'
    beq  a1, t0, calc_cmd_check
    .puts "?\n"
    j    shell_loop
calc_cmd_check:
    li   t0, 'l'
    bne  a2, t0, calc_cmd_bad
    li   t0, 'c'
    beq  a3, t0, calc_start
calc_cmd_bad:
    .puts "?\n"
    j    shell_loop

# =============================================================== putc(a0)
putc:
    li   t0, 2
    li   t2, 0x1008
putc_w:
    lw   t1, 0(t2)
    and  t1, t1, t0
    bnez t1, putc_w
    li   t2, 0x1000
    sw   a0, 0(t2)
    ret

# =============================================================== read_key() -> a0
read_key:
    li   t0, 1
    li   t2, 0x1008
rk_w:
    lw   t1, 0(t2)
    and  t1, t1, t0
    beqz t1, rk_w
    li   t2, 0x1004
    lw   a0, 0(t2)
    sw   x0, 0(t2)
    ret

# =============================================================== read_cmd() -> a0..a4
# Returns first command token chars in a0..a3 and first argument char in a4.
# Examples: "pong" -> p,o,n,g,0; "mem 2" -> m,e,m,0,'2'; "m2" -> m,2,0,0,0.
read_cmd:
    addi sp, sp, -28
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    sw   s4, 20(sp)
    sw   s5, 24(sp)
    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s3, 0
    li   s4, 0          # token char count
    li   s5, 0          # first argument char
rc_loop:
    jal  ra, read_key
    li   t0, 0x0D
    beq  a0, t0, rc_done
    li   t0, 0x0A
    beq  a0, t0, rc_done
    li   t0, ' '
    beq  a0, t0, rc_space
    li   t0, 0x09
    beq  a0, t0, rc_space
    li   t0, 4
    bge  s4, t0, rc_arg
    beqz s4, rc_c0
    li   t0, 1
    beq  s4, t0, rc_c1
    li   t0, 2
    beq  s4, t0, rc_c2
    mv   s3, a0
    addi s4, s4, 1
    j    rc_loop
rc_c0:
    mv   s0, a0
    addi s4, s4, 1
    j    rc_loop
rc_c1:
    mv   s1, a0
    addi s4, s4, 1
    j    rc_loop
rc_c2:
    mv   s2, a0
    addi s4, s4, 1
    j    rc_loop
rc_space:
    bnez s4, rc_loop
    j    rc_loop
rc_arg:
    bnez s5, rc_loop
    mv   s5, a0
    j    rc_loop
rc_done:
    mv   a0, s0
    mv   a1, s1
    mv   a2, s2
    mv   a3, s3
    mv   a4, s5
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    lw   s5, 24(sp)
    addi sp, sp, 28
    ret

# =============================================================== hex/print helpers
hex_char_to_nibble:
    li   t0, '0'
    blt  a0, t0, hctn_bad
    li   t1, '9'
    blt  t1, a0, hctn_alpha
    addi a0, a0, -48
    ret
hctn_alpha:
    li   t0, 'a'
    blt  a0, t0, hctn_upper
    li   t1, 'f'
    blt  t1, a0, hctn_bad
    addi a0, a0, -87
    ret
hctn_upper:
    li   t0, 'A'
    blt  a0, t0, hctn_bad
    li   t1, 'F'
    blt  t1, a0, hctn_bad
    addi a0, a0, -55
    ret
hctn_bad:
    li   a0, -1
    ret

print_nibble:
    li   t0, 10
    blt  a0, t0, pn_digit
    addi a0, a0, 87
    j    putc
pn_digit:
    addi a0, a0, 48
    j    putc

print_hex32:
    mv   a5, a0
    mv   a6, ra
    srli a0, a5, 28
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 24
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 20
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 16
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 12
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 8
    andi a0, a0, 15
    jal  ra, print_nibble
    srli a0, a5, 4
    andi a0, a0, 15
    jal  ra, print_nibble
    andi a0, a5, 15
    jal  ra, print_nibble
    jalr x0, 0(a6)

# Send a0 as four little-endian raw bytes. Used only inside framed packets.
send_word_binary:
    mv   a5, a0
    mv   a6, ra
    andi a0, a5, 255
    jal  ra, putc
    srli a0, a5, 8
    andi a0, a0, 255
    jal  ra, putc
    srli a0, a5, 16
    andi a0, a0, 255
    jal  ra, putc
    srli a0, a5, 24
    andi a0, a0, 255
    jal  ra, putc
    jalr x0, 0(a6)

print_mem_word:
    mv   a3, a0
    mv   a4, ra
    .puts "mem"
    addi a0, a3, 48
    jal  ra, putc
    .puts "=0x"
    slli a3, a3, 2
    li   t0, SELFTEST_BASE
    add  a3, a3, t0
    lw   a0, 0(a3)
    jal  ra, print_hex32
    .puts "\n"
    jalr x0, 0(a4)

print_perf:
    # Fixed-address snapshot and fully unrolled output. There is no stack and
    # no branch back-edge, so this command cannot become an infinite printer.
    mv   a7, ra
    rdcycle t1
    nop
    sw   t1, 0x088(x0)
    rdinstret t1
    nop
    sw   t1, 0x08C(x0)
    li   t0, 0x1024
    lw   t1, 0(t0)
    nop
    sw   t1, 0x090(x0)
    lw   t1, 4(t0)
    nop
    sw   t1, 0x094(x0)
    lw   t1, 8(t0)
    nop
    sw   t1, 0x098(x0)
    lw   t1, 12(t0)
    nop
    sw   t1, 0x09C(x0)
    lw   t1, 16(t0)
    nop
    sw   t1, 0x0A0(x0)
    lw   t1, 20(t0)
    nop
    sw   t1, 0x0A4(x0)
    lw   t1, 24(t0)
    nop
    sw   t1, 0x0A8(x0)
    # Binary packet: A5 'P' 36, followed by 9 little-endian u32 values.
    .putc 0xA5
    .putc 'P'
    .putc 36
    lw   a0, 0x088(x0)
    jal  ra, send_word_binary
    lw   a0, 0x08C(x0)
    jal  ra, send_word_binary
    lw   a0, 0x090(x0)
    jal  ra, send_word_binary
    lw   a0, 0x094(x0)
    jal  ra, send_word_binary
    lw   a0, 0x098(x0)
    jal  ra, send_word_binary
    lw   a0, 0x09C(x0)
    jal  ra, send_word_binary
    lw   a0, 0x0A0(x0)
    jal  ra, send_word_binary
    lw   a0, 0x0A4(x0)
    jal  ra, send_word_binary
    lw   a0, 0x0A8(x0)
    jal  ra, send_word_binary
    jalr x0, 0(a7)

# =============================================================== boot_selftest
boot_selftest:
    mv   a7, ra
    li   s9, SELFTEST_BASE
    li   s10, 0            # first failure code; keep running every test

    # m0: RV32I arithmetic/logic/shift signature = 0x000000ff.
    li   t0, 0x0F
    li   t1, 0xF0
    or   t2, t0, t1
    slli t3, t2, 4
    srli t2, t3, 4
    sw   t2, 0(s9)
    li   t3, 0xFF
    beq  t2, t3, selftest_branch
    li   t6, 1
    jal  ra, selftest_mark

selftest_branch:
    # m1: branch/loop result = 1+...+10 = 55.
    li   t0, 0
    li   t1, 1
    li   t2, 11
selftest_sum_loop:
    add  t0, t0, t1
    addi t1, t1, 1
    blt  t1, t2, selftest_sum_loop
    sw   t0, 4(s9)
    li   t3, 55
    beq  t0, t3, selftest_ram
    li   t6, 2
    jal  ra, selftest_mark

selftest_ram:
    # m2: isolated on-chip RAM round trip = 0x13579bdf.
    li   t4, SELFTEST_SCRATCH
    li   t0, 0x13579BDF
    sw   t0, 0(t4)
    nop
    nop
    lw   t1, 0(t4)
    nop
    sw   t1, 8(s9)
    beq  t0, t1, selftest_mul
    li   t6, 3
    jal  ra, selftest_mark

selftest_mul:
    # m3: MUL 7*6 = 42.
    li   t0, 7
    li   t1, 6
    mul  t2, t0, t1
    nop
    sw   t2, 12(s9)
    li   t3, 42
    beq  t2, t3, selftest_div
    li   t6, 4
    jal  ra, selftest_mark

selftest_div:
    # m4: DIVU/REMU 7/3, packed as quotient:remainder = 0x00020001.
    li   t0, 7
    li   t1, 3
    divu t2, t0, t1
    remu t3, t0, t1
    slli t2, t2, 16
    or   t2, t2, t3
    sw   t2, 16(s9)
    li   t3, 0x00020001
    beq  t2, t3, selftest_fadd
    li   t6, 5
    jal  ra, selftest_mark

selftest_fadd:
    # m5: custom float32 1.0+1.0 = 2.0.
    li   t0, 0x3F800000
    fadd32 t2, t0, t0
    li   t3, 0x40000000
    sw   t2, 20(s9)
    beq  t2, t3, selftest_fmul
    li   t6, 6
    jal  ra, selftest_mark

selftest_fmul:
    # m6: custom float32 1.5*2.0 = 3.0 and FGT32(3.0,2.0)=1.
    li   t0, 0x3FC00000
    li   t1, 0x40000000
    fmul32 t2, t0, t1
    li   t3, 0x40400000
    sw   t2, 24(s9)
    bne  t2, t3, selftest_fmul_fail
    fgt32 t4, t2, t1
    li   t5, 1
    beq  t4, t5, selftest_custom
selftest_fmul_fail:
    li   t6, 7
    jal  ra, selftest_mark

selftest_custom:
    # m7: BITREV(0xabcd00ff)=0xff00b3d5; POPCOUNT must be 18.
    li   t0, 0xABCD00FF
    bitrev t2, t0
    popcount t3, t0
    sw   t2, 28(s9)
    li   t4, 0xFF00B3D5
    bne  t2, t4, selftest_custom_fail
    li   t4, 18
    beq  t3, t4, selftest_csr
selftest_custom_fail:
    li   t6, 8
    jal  ra, selftest_mark

selftest_csr:
    # m8: cycle CSR must be non-zero; mtvec must retain irq_handler.
    rdcycle t2
    sw   t2, 32(s9)
    beqz t2, selftest_csr_fail
    csrrs t3, mtvec, x0
    la   t4, irq_handler
    beq  t3, t4, selftest_sdram
selftest_csr_fail:
    li   t6, 9
    jal  ra, selftest_mark

selftest_sdram:
    # m9: wait for SDRAM initialization, then perform a real wait-state access.
    li   t0, SDRAM_STATUS
    li   t5, 100000
selftest_sdram_wait:
    lw   t1, 0(t0)
    andi t1, t1, 1
    bnez t1, selftest_sdram_ready
    addi t5, t5, -1
    bnez t5, selftest_sdram_wait
    li   t2, 0
    j    selftest_sdram_result
selftest_sdram_ready:
    li   t0, SDRAM_BASE
    li   t1, 0x5AA5C33C
    sw   t1, 0(t0)
    nop
    lw   t2, 0(t0)
    nop
selftest_sdram_result:
    sw   t2, 36(s9)
    li   t3, 0x5AA5C33C
    beq  t2, t3, selftest_finish
    li   t6, 10
    jal  ra, selftest_mark

selftest_finish:
    sw   s10, 40(s9)
    bnez s10, selftest_failed
    li   t0, 15
    li   t1, LED_OUT
    sw   t0, 0(t1)
    .puts "SELFTEST PASS\n"
    jalr x0, 0(a7)
selftest_failed:
    li   t1, LED_OUT
    sw   s10, 0(t1)
    .puts "SELFTEST FAIL\n"
    jalr x0, 0(a7)

selftest_mark:
    bnez s10, selftest_mark_return
    mv   s10, t6
selftest_mark_return:
    ret

# =============================================================== cnn_start
cnn_start:
    .puts "cnn 0-9/image, q exits\n"
cnn_loop:
    .puts "pixels64\n"
    jal  ra, recv_image
    bnez a0, cnn_exit
    jal  ra, infer_digit
    j    cnn_loop
cnn_exit:
    j    shell_loop

# =============================================================== recv_image() -> a0 (1=q, 0=image)
recv_image:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    li   s0, 0
ri_loop:
    jal  ra, read_key
    li   t1, 0x0A
    beq  a0, t1, ri_loop
    li   t1, 0x0D
    beq  a0, t1, ri_loop
    bnez s0, ri_pixel
    li   t1, 'q'
    beq  a0, t1, ri_quit
ri_pixel:
    li   t2, 0
    li   t1, '0'
    beq  a0, t1, ri_store
    li   t1, '.'
    beq  a0, t1, ri_store
    li   t2, 1
ri_store:
    sb   t2, IMG(s0)
    addi s0, s0, 1
    li   t1, 64
    blt  s0, t1, ri_loop
    li   a0, 0
    j    ri_return
ri_quit:
    # Consume q's trailing newline before returning to the normal shell.
    jal  ra, read_key
    li   t1, 0x0A
    beq  a0, t1, ri_quit_done
    li   t1, 0x0D
    bne  a0, t1, ri_quit
ri_quit_done:
    li   a0, 1
ri_return:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# =============================================================== infer_digit()
infer_digit:
    addi sp, sp, -40
    sw   ra, 0(sp)
    sw   s0, 4(sp)     # class index
    sw   s1, 8(sp)     # best digit
    sw   s2, 12(sp)    # best score (float bits)
    sw   s3, 16(sp)    # current score (float bits)
    sw   s4, 20(sp)    # weight pointer
    sw   s5, 24(sp)    # bias pointer
    sw   s6, 28(sp)    # pixel index
    sw   s7, 32(sp)    # hidden pointer/index
    sw   s8, 36(sp)    # second-layer weight pointer

    # First layer. Binary inputs turn pixel*weight into a conditional add.
    li   s0, 0
    li   s4, W1
    li   s5, B1
    li   s7, HIDDEN
hidden_loop:
    lw   s3, 0(s5)
    li   s6, 0
hidden_pixel_loop:
    lb   t0, IMG(s6)
    beqz t0, hidden_pixel_skip
    lw   t1, 0(s4)
    fadd32 s3, s3, t1
hidden_pixel_skip:
    addi s4, s4, 4
    addi s6, s6, 1
    li   t3, 64
    blt  s6, t3, hidden_pixel_loop
    fgt32 t0, s3, x0
    bnez t0, hidden_store
    li   s3, 0
hidden_store:
    sw   s3, 0(s7)
    addi s7, s7, 4
    addi s5, s5, 4
    addi s0, s0, 1
    li   t0, 8
    blt  s0, t0, hidden_loop

    # Second layer and signed-float argmax.
    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s5, B2
    li   s8, W2
class_loop:
    lw   s3, 0(s5)
    li   s6, 0
    li   s7, HIDDEN
class_hidden_loop:
    lw   t0, 0(s7)
    nop
    lw   t1, 0(s8)
    nop
    fmul32 t2, t0, t1
    fadd32 s3, s3, t2
    addi s7, s7, 4
    addi s8, s8, 4
    addi s6, s6, 1
    li   t3, 8
    blt  s6, t3, class_hidden_loop

    beqz s0, best_update
    fgt32 t0, s3, s2
    beqz t0, class_next
best_update:
    mv   s1, s0
    mv   s2, s3

class_next:
    addi s0, s0, 1
    addi s5, s5, 4
    li   t0, 10
    blt  s0, t0, class_loop

    li   t0, 0x100C
    sw   s1, 0(t0)
    .puts "pred "
    addi a0, s1, 48
    jal  ra, putc
    .puts "\n"

    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    lw   s5, 24(sp)
    lw   s6, 28(sp)
    lw   s7, 32(sp)
    lw   s8, 36(sp)
    addi sp, sp, 40
    ret

# =============================================================== float calculator
# Recursive descent grammar: expr -> term {(+|-) term}; term -> factor {(*|/) factor}
# factor -> number | -factor | (expr). Numeric literals are decimal float32.
calc_start:
    .puts "float calc: () +-*/, q exits\n"
calc_loop:
    .puts "calc> "
    jal  ra, calc_read_line
    bnez a0, calc_exit
    li   t0, CALC_BUF
    sw   t0, CALC_PTR(x0)
    sw   x0, CALC_ERR(x0)
    jal  ra, calc_parse_expr
    mv   s0, a0
    jal  ra, calc_skip_spaces
    lw   t0, CALC_PTR(x0)
    lbu  t1, 0(t0)
    beqz t1, calc_check_error
    li   t1, 1
    sw   t1, CALC_ERR(x0)
calc_check_error:
    lw   t0, CALC_ERR(x0)
    bnez t0, calc_bad
    .puts "= "
    mv   a0, s0
    jal  ra, print_float3
    .puts " (0x"
    mv   a0, s0
    jal  ra, print_hex32
    .puts ")\n"
    j    calc_loop
calc_bad:
    .puts "error\n"
    j    calc_loop
calc_exit:
    j    shell_loop

# Read at most 95 expression bytes. A line beginning with q exits.
calc_read_line:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    li   s0, CALC_BUF
    li   s1, 0
calc_read_loop:
    jal  ra, read_key
    li   t0, 13
    beq  a0, t0, calc_read_done
    li   t0, 10
    beq  a0, t0, calc_read_done
    li   t0, 95
    bge  s1, t0, calc_read_loop
    sb   a0, 0(s0)
    addi s0, s0, 1
    addi s1, s1, 1
    j    calc_read_loop
calc_read_done:
    sb   x0, 0(s0)
    li   a0, 0
    li   t0, 1
    bne  s1, t0, calc_read_return
    li   t2, CALC_BUF
    lbu  t1, 0(t2)
    li   t0, 'q'
    bne  t1, t0, calc_read_return
    li   a0, 1
calc_read_return:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

calc_skip_spaces:
    lw   t0, CALC_PTR(x0)
calc_space_loop:
    lbu  t1, 0(t0)
    li   t2, ' '
    beq  t1, t2, calc_space_advance
    li   t2, 9
    bne  t1, t2, calc_space_done
calc_space_advance:
    addi t0, t0, 1
    j    calc_space_loop
calc_space_done:
    sw   t0, CALC_PTR(x0)
    ret

calc_parse_expr:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    jal  ra, calc_parse_term
    mv   s0, a0
calc_expr_loop:
    jal  ra, calc_skip_spaces
    lw   t0, CALC_PTR(x0)
    lbu  s1, 0(t0)
    li   t1, '+'
    beq  s1, t1, calc_expr_op
    li   t1, '-'
    bne  s1, t1, calc_expr_done
calc_expr_op:
    addi t0, t0, 1
    sw   t0, CALC_PTR(x0)
    jal  ra, calc_parse_term
    li   t0, '-'
    bne  s1, t0, calc_expr_add
    li   t0, 0x80000000
    xor  a0, a0, t0
calc_expr_add:
    fadd32 s0, s0, a0
    j    calc_expr_loop
calc_expr_done:
    mv   a0, s0
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

calc_parse_term:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    jal  ra, calc_parse_factor
    mv   s0, a0
calc_term_loop:
    jal  ra, calc_skip_spaces
    lw   t0, CALC_PTR(x0)
    lbu  s1, 0(t0)
    li   t1, '*'
    beq  s1, t1, calc_term_op
    li   t1, '/'
    bne  s1, t1, calc_term_done
calc_term_op:
    addi t0, t0, 1
    sw   t0, CALC_PTR(x0)
    jal  ra, calc_parse_factor
    li   t0, '*'
    bne  s1, t0, calc_term_div
    fmul32 s0, s0, a0
    j    calc_term_loop
calc_term_div:
    mv   a1, a0
    mv   a0, s0
    jal  ra, soft_fdiv32
    mv   s0, a0
    j    calc_term_loop
calc_term_done:
    mv   a0, s0
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

calc_parse_factor:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    jal  ra, calc_skip_spaces
    lw   s0, CALC_PTR(x0)
    lbu  t0, 0(s0)
    li   t1, '-'
    beq  t0, t1, calc_factor_neg
    li   t1, '('
    beq  t0, t1, calc_factor_paren
    jal  ra, calc_parse_number
    j    calc_factor_return
calc_factor_neg:
    addi s0, s0, 1
    sw   s0, CALC_PTR(x0)
    jal  ra, calc_parse_factor
    li   t0, 0x80000000
    xor  a0, a0, t0
    j    calc_factor_return
calc_factor_paren:
    addi s0, s0, 1
    sw   s0, CALC_PTR(x0)
    jal  ra, calc_parse_expr
    mv   s0, a0
    jal  ra, calc_skip_spaces
    lw   t0, CALC_PTR(x0)
    lbu  t1, 0(t0)
    li   t2, ')'
    beq  t1, t2, calc_factor_close
    li   t1, 1
    sw   t1, CALC_ERR(x0)
    j    calc_factor_paren_done
calc_factor_close:
    addi t0, t0, 1
    sw   t0, CALC_PTR(x0)
calc_factor_paren_done:
    mv   a0, s0
calc_factor_return:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# Parse unsigned decimal into float32. Up to seven significant digits is safe.
calc_parse_number:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    sw   s4, 20(sp)
    lw   s0, CALC_PTR(x0)
    li   s1, 0
    li   s2, 1
    li   s3, 0
    li   s4, 0
calc_number_loop:
    lbu  t0, 0(s0)
    li   t1, '.'
    beq  t0, t1, calc_number_dot
    li   t1, '0'
    blt  t0, t1, calc_number_done
    li   t2, '9'
    blt  t2, t0, calc_number_done
    li   t3, 10
    mul  s1, s1, t3
    addi t0, t0, -48
    add  s1, s1, t0
    beqz s3, calc_number_digit_done
    mul  s2, s2, t3
calc_number_digit_done:
    li   s4, 1
    addi s0, s0, 1
    j    calc_number_loop
calc_number_dot:
    bnez s3, calc_number_done
    li   s3, 1
    addi s0, s0, 1
    j    calc_number_loop
calc_number_done:
    sw   s0, CALC_PTR(x0)
    bnez s4, calc_number_convert
    li   t0, 1
    sw   t0, CALC_ERR(x0)
    li   a0, 0
    j    calc_number_return
calc_number_convert:
    mv   a0, s1
    jal  ra, uint_to_float32
    mv   s4, a0
    li   t0, 1
    beq  s2, t0, calc_number_no_scale
    mv   a0, s2
    jal  ra, uint_to_float32
    mv   a1, a0
    mv   a0, s4
    jal  ra, soft_fdiv32
    mv   s4, a0
calc_number_no_scale:
    mv   a0, s4
calc_number_return:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    addi sp, sp, 24
    ret

uint_to_float32:
    beqz a0, uint_float_zero
    mv   t0, a0
    li   t1, 0
uint_float_msb:
    srli t2, t0, 1
    beqz t2, uint_float_pack
    mv   t0, t2
    addi t1, t1, 1
    j    uint_float_msb
uint_float_pack:
    li   t2, 23
    blt  t2, t1, uint_float_right
    sub  t3, t2, t1
    sll  t0, a0, t3
    j    uint_float_exp
uint_float_right:
    sub  t3, t1, t2
    srl  t0, a0, t3
uint_float_exp:
    addi t1, t1, 127
    slli t1, t1, 23
    li   t2, 0x007FFFFF
    and  t0, t0, t2
    or   a0, t1, t0
uint_float_zero:
    ret

# a0/a1 float32 division. Produces a normalized 24-bit quotient by long divide.
soft_fdiv32:
    beqz a1, soft_fdiv_zero
    beqz a0, soft_fdiv_return
    xor  t0, a0, a1
    li   t1, 0x80000000
    and  t0, t0, t1
    srli t1, a0, 23
    andi t1, t1, 255
    srli t2, a1, 23
    andi t2, t2, 255
    sub  t1, t1, t2
    addi t1, t1, 127
    li   t2, 0x007FFFFF
    and  t3, a0, t2
    and  t4, a1, t2
    li   t5, 0x00800000
    or   t3, t3, t5
    or   t4, t4, t5
    bgeu t3, t4, soft_fdiv_ready
    slli t3, t3, 1
    addi t1, t1, -1
soft_fdiv_ready:
    sub  t3, t3, t4
    mv   t6, t5
    li   a2, 22
soft_fdiv_loop:
    slli t3, t3, 1
    bltu t3, t4, soft_fdiv_next
    sub  t3, t3, t4
    li   a3, 1
    sll  a3, a3, a2
    or   t6, t6, a3
soft_fdiv_next:
    addi a2, a2, -1
    bgez a2, soft_fdiv_loop
    and  t6, t6, t2
    slli t1, t1, 23
    or   a0, t0, t1
    or   a0, a0, t6
soft_fdiv_return:
    ret
soft_fdiv_zero:
    li   t0, 1
    sw   t0, CALC_ERR(x0)
    li   a0, 0
    ret

print_uint:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    mv   s0, a0
    li   t0, 10
    bltu s0, t0, print_uint_digit
    divu a0, s0, t0
    jal  ra, print_uint
print_uint_digit:
    li   t0, 10
    remu a0, s0, t0
    addi a0, a0, 48
    jal  ra, putc
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# Print a practical calculator range as signed decimal with three digits.
print_float3:
    addi sp, sp, -28
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    sw   s4, 20(sp)
    sw   s5, 24(sp)
    mv   s0, a0
    bgez s0, print_float_abs
    li   a0, '-'
    jal  ra, putc
    li   t0, 0x7FFFFFFF
    and  s0, s0, t0
print_float_abs:
    beqz s0, print_float_zero
    srli s1, s0, 23
    andi s1, s1, 255
    addi s1, s1, -127
    li   t0, 0x007FFFFF
    and  s2, s0, t0
    li   t0, 0x00800000
    or   s2, s2, t0
    li   t0, 23
    blt  t0, s1, print_float_large
    bltz s1, print_float_less_one
    sub  s3, t0, s1
    srl  a0, s2, s3
    jal  ra, print_uint
    li   t1, 1
    sll  t1, t1, s3
    addi t1, t1, -1
    and  s4, s2, t1
    mv   s5, s3
    j    print_float_fraction
print_float_less_one:
    li   a0, '0'
    jal  ra, putc
    li   t0, 23
    sub  s5, t0, s1
    li   t0, 31
    blt  t0, s5, print_float_tiny
    mv   s4, s2
    j    print_float_fraction
print_float_large:
    addi t1, s1, -23
    sll  a0, s2, t1
    jal  ra, print_uint
    li   s4, 0
    li   s5, 1
print_float_fraction:
    li   a0, '.'
    jal  ra, putc
    li   s3, 3
print_float_frac_loop:
    li   t0, 10
    mul  s4, s4, t0
    srl  a0, s4, s5
    addi a0, a0, 48
    jal  ra, putc
    li   t0, 1
    sll  t0, t0, s5
    addi t0, t0, -1
    and  s4, s4, t0
    addi s3, s3, -1
    bnez s3, print_float_frac_loop
    j    print_float_return
print_float_zero:
    .puts "0.000"
    j    print_float_return
print_float_tiny:
    .puts ".000"
print_float_return:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    lw   s5, 24(sp)
    addi sp, sp, 28
    ret

# =============================================================== CPU pong demo
pong_start:
    jal  ra, pong_reset
    li   t0, 1
    sw   t0, PONG_MODE(x0)
    sw   x0, PONG_KEY(x0)
    sw   x0, PONG_TICKS(x0)
    li   t0, 7
    li   t1, IRQ_ENABLE
    sw   t0, 0(t1)
    .puts "pong auto, a/d move, n new, q exit\n"
    jal  ra, pong_render
pong_loop:
    .puts "pong> "
pong_wait:
    lw   a0, PONG_KEY(x0)
    bnez a0, pong_have_key
    lw   t0, PONG_TICKS(x0)
    beqz t0, pong_wait
    addi t0, t0, -1
    sw   t0, PONG_TICKS(x0)
    bnez s5, pong_wait
    jal  ra, pong_step
    jal  ra, pong_render
    j    pong_loop

pong_have_key:
    sw   x0, PONG_KEY(x0)
    li   t0, 'q'
    beq  a0, t0, pong_exit
    li   t0, 'n'
    beq  a0, t0, pong_new
    li   t0, 'a'
    beq  a0, t0, pong_left
    li   t0, 'd'
    beq  a0, t0, pong_right
    li   t0, 's'
    beq  a0, t0, pong_step_only
    j    pong_wait

pong_exit:
    sw   x0, PONG_MODE(x0)
    sw   x0, PONG_KEY(x0)
    li   t0, 2
    li   t1, IRQ_ENABLE
    sw   t0, 0(t1)
    j    shell_loop

pong_new:
    jal  ra, pong_reset
    jal  ra, pong_render
    j    pong_loop

pong_left:
    beqz s4, pong_move_done
    addi s4, s4, -1
    j    pong_move_done

pong_right:
    li   t1, 5
    bge  s4, t1, pong_move_done
    addi s4, s4, 1

pong_move_done:
    jal  ra, pong_render
    j    pong_loop
pong_step_only:
    jal  ra, pong_step
    jal  ra, pong_render
    j    pong_loop

pong_reset:
    li   s0, 3             # ball x
    li   s1, 1             # ball y
    li   s2, 1             # direction x
    li   s3, 1             # direction y
    li   s4, 2             # paddle left edge
    li   s5, 0             # game over
    li   s6, 0             # score
    ret

pong_step:
    bnez s5, pong_step_ret

    # Reflect direction before moving so coordinates always remain inside the
    # 0..7 by 0..5 play field. In particular, x=7 moving right becomes x=6.
    beqz s0, pong_face_right
    li   t4, 7
    bne  s0, t4, pong_check_top
    li   s2, -1
    j    pong_check_top
pong_face_right:
    li   s2, 1
pong_check_top:
    bnez s1, pong_move
    li   s3, 1
pong_move:
    add  s0, s0, s2
    add  s1, s1, s3

    # Defensive clamps protect the renderer even if state is corrupted.
    bltz s0, pong_bounce_x_low
    li   t4, 7
    blt  t4, s0, pong_bounce_x_high
    j    pong_check_y
pong_bounce_x_low:
    li   s0, 0
    li   s2, 1
    j    pong_check_y
pong_bounce_x_high:
    li   s0, 7
    li   s2, -1

pong_check_y:
    bltz s1, pong_bounce_y_top
    li   t4, 5
    blt  t4, s1, pong_miss
    blt  s1, t4, pong_step_ret

    blt  s0, s4, pong_miss
    addi t6, s4, 2
    blt  t6, s0, pong_miss
    li   s1, 4
    li   s3, -1
    addi s6, s6, 1
    j    pong_step_ret

pong_bounce_y_top:
    li   s1, 0
    li   s3, 1
    j    pong_step_ret

pong_miss:
    li   s5, 1
    li   t4, 15
    li   t5, 0x100C
    sw   t4, 0(t5)
pong_step_ret:
    ret

pong_render:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .puts "P "
    mv   a0, s0
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    mv   a0, s1
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    mv   a0, s4
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    mv   a0, s5
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    mv   a0, s6
    andi a0, a0, 15
    jal  ra, print_nibble
    .puts "\n"
    mv   a0, s6
    andi a0, a0, 15
    li   t0, 0x100C
    sw   a0, 0(t0)
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# =============================================================== SDRAM paint
# 512x256 byte-per-pixel canvas at SDRAM_BASE (131072 bytes). The 16x8 viewport
# is read back from SDRAM for every frame; no on-chip shadow copy exists.
paint_start:
    li   t0, SDRAM_STATUS
    lw   t1, 0(t0)
    andi t1, t1, 1
    beqz t1, paint_no_sdram
    li   s0, 0             # cursor x: 0..511
    li   s1, 0             # cursor y: 0..255
    li   s2, SDRAM_BASE
    sw   x0, PONG_MODE(x0) # Paint uses polling; UART IRQ is reserved for Pong.
    sw   x0, PONG_KEY(x0)
    li   t0, 2             # KEY IRQ only; UART remains available to read_key.
    li   t1, IRQ_ENABLE
    sw   t0, 0(t1)
    .puts "SDRAM paint 512x256 (128KiB): wasd move, x draw, c clear, q exit\n"
    jal  ra, paint_clear
    jal  ra, paint_render
paint_loop:
    jal  ra, read_key
    li   t0, 'q'
    beq  a0, t0, paint_exit
    li   t0, 'a'
    beq  a0, t0, paint_left
    li   t0, 'd'
    beq  a0, t0, paint_right
    li   t0, 'w'
    beq  a0, t0, paint_up
    li   t0, 's'
    beq  a0, t0, paint_down
    li   t0, 'x'
    beq  a0, t0, paint_toggle
    li   t0, ' '
    beq  a0, t0, paint_toggle
    li   t0, 'c'
    beq  a0, t0, paint_clear_render
    j    paint_loop

paint_left:
    beqz s0, paint_update
    addi s0, s0, -1
    j    paint_update
paint_right:
    li   t0, 511
    bge  s0, t0, paint_update
    addi s0, s0, 1
    j    paint_update
paint_up:
    beqz s1, paint_update
    addi s1, s1, -1
    j    paint_update
paint_down:
    li   t0, 255
    bge  s1, t0, paint_update
    addi s1, s1, 1
    j    paint_update

paint_toggle:
    slli t0, s1, 9
    add  t0, t0, s0
    add  t0, t0, s2
    lbu  t1, 0(t0)
    xori t1, t1, 1
    sb   t1, 0(t0)
    j    paint_update

paint_clear_render:
    jal  ra, paint_clear
paint_update:
    jal  ra, paint_render
    j    paint_loop

paint_exit:
    sw   x0, PONG_MODE(x0)
    sw   x0, PONG_KEY(x0)
    li   t0, 2
    li   t1, IRQ_ENABLE
    sw   t0, 0(t1)
    j    shell_loop
paint_no_sdram:
    .puts "SDRAM not ready\n"
    j    shell_loop

paint_clear:
    mv   t0, s2
    li   t1, 32768         # 32768 words = 131072-byte canvas
paint_clear_loop:
    sw   x0, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, paint_clear_loop
    ret

# Binary frame: A5 'D' 131, x_lo, x_hi, y, then 128 cells (0/1/2).
paint_render:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .putc 0xA5
    .putc 'D'
    .putc 131
    andi a0, s0, 255
    jal  ra, putc
    srli a0, s0, 8
    andi a0, a0, 255
    jal  ra, putc
    mv   a0, s1
    jal  ra, putc

    andi s5, s0, -16      # viewport x origin
    andi s6, s1, -8       # viewport y origin
    li   s3, 0
paint_row_loop:
    add  t0, s6, s3
    slli t0, t0, 9
    add  t0, t0, s5
    add  s7, s2, t0
    li   s4, 0
paint_col_loop:
    add  t0, s5, s4
    bne  t0, s0, paint_cell
    add  t1, s6, s3
    bne  t1, s1, paint_cell
    li   a0, 2
    j    paint_put_cell
paint_cell:
    lbu  t2, 0(s7)
    beqz t2, paint_cell_off
    li   a0, 1
    j    paint_put_cell
paint_cell_off:
    li   a0, 0
paint_put_cell:
    jal  ra, putc
    addi s7, s7, 1
    addi s4, s4, 1
    li   t0, 16
    blt  s4, t0, paint_col_loop
    addi s3, s3, 1
    li   t0, 8
    blt  s3, t0, paint_row_loop
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

idle:
    j    idle2
idle2:
    j    idle
