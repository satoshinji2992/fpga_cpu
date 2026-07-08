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

start:
    li   sp, 0xF00
    .puts "\nRV32 mnist8-float shell\n"
    .puts "type cnn or h\n"

shell_loop:
    .puts "cpu> "
    jal  ra, read_cmd
    li   t0, 'c'
    beq  a0, t0, cnn_start
    li   t0, 'h'
    beq  a0, t0, shell_help
    li   t0, 'q'
    beq  a0, t0, idle
    .puts "commands: cnn help quit\n"
    j    shell_loop

shell_help:
    .puts "cnn: receive 8x8 binary digit\n"
    .puts "host: python scripts/serial_shell.py -p PORT --cnn 7\n"
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

# =============================================================== read_cmd() -> a0
read_cmd:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    li   s0, 0
rc_loop:
    jal  ra, read_key
    li   t0, 0x0D
    beq  a0, t0, rc_done
    li   t0, 0x0A
    beq  a0, t0, rc_done
    bnez s0, rc_loop
    mv   s0, a0
    j    rc_loop
rc_done:
    mv   a0, s0
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# =============================================================== cnn_start
cnn_start:
    .puts "send 64 pixels\n"
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
    .puts "prediction: "
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

idle:
    j    idle2
idle2:
    j    idle
