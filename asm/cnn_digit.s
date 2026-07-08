# asm/cnn_digit.s — MNIST 8x8 float32 inference on the RV32 CPU.
#
# The model is trained offline by scripts/train_mnist8.py:
#   score[k] = bias[k] + sum(pixel[i] * weight[k][i])
#
# Pixels are 8x8 binary ASCII values sent over UART. Weights and bias live in
# data RAM via src/cnn_weights.vh. The CPU performs inference with custom
# float32 instructions fmul32/fadd32/fgt32.

.equ UART_TX,   0x1000
.equ UART_RX,   0x1004
.equ UART_STAT, 0x1008
.equ LED_OUT,   0x100C

.equ IMG,     0x000
.equ WEIGHT,  0x100     # 10 * 64 float32 words
.equ BIAS,    0xB00     # 10 float32 words
.equ FONE,    0xB28     # float32 1.0

.equ PONG_BX,    0x040
.equ PONG_BY,    0x044
.equ PONG_DX,    0x048
.equ PONG_DY,    0x04C
.equ PONG_PAD,   0x050
.equ PONG_OVER,  0x054
.equ PONG_SCORE, 0x058

start:
    li   sp, 0xF00
    .puts "\nRV32 shell\n"

shell_loop:
    .puts "cpu> "
    jal  ra, read_cmd

    li   t0, 'h'
    beq  a0, t0, shell_help
    li   t0, '?'
    beq  a0, t0, shell_help
    li   t0, 's'
    beq  a0, t0, status_cmd
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
    beq  a0, t0, idle
    .puts "?\n"
    j    shell_loop

shell_help:
    .puts "h/? s 0-3 mN p ledX cnn pong q\n"
    j    shell_loop

status_cmd:
    .puts "OK rv32 uart\n"
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
    li   t1, '3'
    blt  t1, t0, mem_bad
    addi a0, t0, -48
    jal  ra, print_mem_word
    j    shell_loop
mem_bad:
    .puts "use m0..m3\n"
    j    shell_loop

p_cmd:
    li   t0, 'o'
    beq  a1, t0, pong_start
    jal  ra, print_perf
    j    shell_loop

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
    li   t0, 0x100C
    sw   a0, 0(t0)
    .puts "led=0x"
    jal  ra, print_nibble
    .puts "\n"
    j    shell_loop
led_bad:
    .puts "use led0..ledf\n"
    j    shell_loop

cnn_cmd:
    li   t0, 'n'
    beq  a1, t0, cnn_start
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
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    mv   s0, a0
    li   t0, 10
    blt  s0, t0, pn_digit
    addi a0, s0, 87
    j    pn_put
pn_digit:
    addi a0, s0, 48
pn_put:
    jal  ra, putc
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

print_hex32:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    mv   s0, a0
    li   s1, 28
ph_loop:
    srl  a0, s0, s1
    andi a0, a0, 15
    jal  ra, print_nibble
    addi s1, s1, -4
    bgez s1, ph_loop
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

print_mem_word:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    mv   s0, a0
    .puts "mem"
    addi a0, s0, 48
    jal  ra, putc
    .puts "=0x"
    slli s1, s0, 2
    lw   a0, 0(s1)
    jal  ra, print_hex32
    .puts "\n"
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

print_perf:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .puts "cycle=0x"
    rdcycle a0
    jal  ra, print_hex32
    .puts "\n"
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# =============================================================== cnn_start
cnn_start:
    .puts "pixels64\n"
    jal  ra, recv_image
    jal  ra, infer_digit
    j    shell_loop

# =============================================================== recv_image()
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
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# =============================================================== infer_digit()
infer_digit:
    addi sp, sp, -36
    sw   ra, 0(sp)
    sw   s0, 4(sp)     # class index
    sw   s1, 8(sp)     # best digit
    sw   s2, 12(sp)    # best score (float bits)
    sw   s3, 16(sp)    # current score (float bits)
    sw   s4, 20(sp)    # weight pointer
    sw   s5, 24(sp)    # bias pointer
    sw   s6, 28(sp)    # pixel index
    sw   s7, 32(sp)    # float one

    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s4, 0x100
    li   s5, 0xB00
    li   t0, 0xB28
    lw   s7, 0(t0)

class_loop:
    lw   s3, 0(s5)         # score = bias[class]
    li   s6, 0

pixel_loop:
    lb   t0, IMG(s6)
    beqz t0, pixel_skip
    lw   t1, 0(s4)         # weight[class][pixel]
    fmul32 t2, t1, s7      # pixel is 1.0 for set bits
    fadd32 s3, s3, t2
pixel_skip:
    addi s4, s4, 4
    addi s6, s6, 1
    li   t3, 64
    blt  s6, t3, pixel_loop

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
    addi sp, sp, 36
    ret

# =============================================================== CPU pong demo
pong_start:
    jal  ra, pong_reset
    .puts "pong a/d/s/n/q\n"
    jal  ra, pong_render
pong_loop:
    .puts "pong> "
    jal  ra, read_cmd
    li   t0, 'q'
    beq  a0, t0, shell_loop
    li   t0, 'n'
    beq  a0, t0, pong_new
    li   t0, 'a'
    beq  a0, t0, pong_left
    li   t0, 'd'
    beq  a0, t0, pong_right
    li   t0, 's'
    beq  a0, t0, pong_step_only
    .puts "?\n"
    j    pong_loop

pong_new:
    jal  ra, pong_reset
    jal  ra, pong_render
    j    pong_loop

pong_left:
    lw   t0, PONG_PAD(x0)
    beqz t0, pong_move_done
    addi t0, t0, -1
    sw   t0, PONG_PAD(x0)
    j    pong_move_done

pong_right:
    lw   t0, PONG_PAD(x0)
    li   t1, 5
    bge  t0, t1, pong_move_done
    addi t0, t0, 1
    sw   t0, PONG_PAD(x0)

pong_move_done:
pong_step_only:
    jal  ra, pong_step
    jal  ra, pong_render
    j    pong_loop

pong_reset:
    li   t0, 3
    sw   t0, PONG_BX(x0)
    li   t0, 1
    sw   t0, PONG_BY(x0)
    sw   t0, PONG_DX(x0)
    sw   t0, PONG_DY(x0)
    li   t0, 2
    sw   t0, PONG_PAD(x0)
    sw   x0, PONG_OVER(x0)
    sw   x0, PONG_SCORE(x0)
    ret

pong_step:
    lw   t0, PONG_OVER(x0)
    bnez t0, pong_step_ret

    lw   t0, PONG_BX(x0)
    lw   t1, PONG_BY(x0)
    lw   t2, PONG_DX(x0)
    lw   t3, PONG_DY(x0)
    add  t0, t0, t2
    add  t1, t1, t3

    bltz t0, pong_bounce_x_low
    li   t4, 7
    blt  t4, t0, pong_bounce_x_high
    j    pong_check_y
pong_bounce_x_low:
    li   t0, 0
    li   t2, 1
    sw   t2, PONG_DX(x0)
    j    pong_check_y
pong_bounce_x_high:
    li   t0, 7
    li   t2, -1
    sw   t2, PONG_DX(x0)

pong_check_y:
    bltz t1, pong_bounce_y_top
    li   t4, 5
    blt  t4, t1, pong_miss
    blt  t1, t4, pong_store_pos

    lw   t5, PONG_PAD(x0)
    blt  t0, t5, pong_miss
    addi t6, t5, 2
    blt  t6, t0, pong_miss
    li   t1, 4
    li   t3, -1
    sw   t3, PONG_DY(x0)
    lw   t4, PONG_SCORE(x0)
    addi t4, t4, 1
    sw   t4, PONG_SCORE(x0)
    j    pong_store_pos

pong_bounce_y_top:
    li   t1, 0
    li   t3, 1
    sw   t3, PONG_DY(x0)
    j    pong_store_pos

pong_miss:
    li   t4, 1
    sw   t4, PONG_OVER(x0)
    li   t4, 15
    li   t5, 0x100C
    sw   t4, 0(t5)

pong_store_pos:
    sw   t0, PONG_BX(x0)
    sw   t1, PONG_BY(x0)
pong_step_ret:
    ret

pong_render:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .puts "P "
    lw   a0, PONG_BX(x0)
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    lw   a0, PONG_BY(x0)
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    lw   a0, PONG_PAD(x0)
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    lw   a0, PONG_OVER(x0)
    addi a0, a0, 48
    jal  ra, putc
    .puts " "
    lw   a0, PONG_SCORE(x0)
    andi a0, a0, 15
    jal  ra, print_nibble
    .puts "\n"
    lw   a0, PONG_SCORE(x0)
    andi a0, a0, 15
    li   t0, 0x100C
    sw   a0, 0(t0)
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

idle:
    j    idle2
idle2:
    j    idle
