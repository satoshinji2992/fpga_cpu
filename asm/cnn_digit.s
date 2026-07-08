# asm/cnn_digit.s — 8x8 fixed-weight digit inference on the RV32 CPU.
#
# Host sends 64 ASCII pixels ('0'/'1' or '.'/'#') over UART. The CPU stores the
# image in data RAM, extracts seven fixed convolution-like stroke features, and
# classifies the digit by the resulting segment mask. Python is only the UART
# terminal; inference runs here on the CPU.

.equ UART_TX,   0x400
.equ UART_RX,   0x404
.equ UART_STAT, 0x408
.equ LED_OUT,   0x40C

.equ IMG, 0x00
.equ SEG, 0x50

start:
    li   sp, 0x3F0
    .puts "\nRV32 tiny-cnn shell\n"
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
    .puts "cnn: receive 8x8 digit, infer 0-9\n"
    .puts "host: python scripts/serial_shell.py -p PORT --cnn 7\n"
    j    shell_loop

# =============================================================== putc(a0)
putc:
    li   t0, 2
putc_w:
    lw   t1, UART_STAT(x0)
    and  t1, t1, t0
    bnez t1, putc_w
    sw   a0, UART_TX(x0)
    ret

# =============================================================== read_key() -> a0
read_key:
    li   t0, 1
rk_w:
    lw   t1, UART_STAT(x0)
    and  t1, t1, t0
    beqz t1, rk_w
    lw   a0, UART_RX(x0)
    sw   x0, UART_RX(x0)
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
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)

    # clear seven feature counters
    li   t0, 0
    li   t1, 0
clr_seg:
    sb   t1, SEG(t0)
    addi t0, t0, 1
    li   t2, 7
    blt  t0, t2, clr_seg

    li   s0, 0                     # y
    li   s2, 0                     # linear image index
iy_loop:
    li   s1, 0                     # x
ix_loop:
    lb   t0, IMG(s2)
    beqz t0, pix_next

    # segment 0: top, y<2 and 2<=x<6
    li   t1, 2
    bge  s0, t1, chk_mid
    blt  s1, t1, chk_mid
    li   t1, 6
    bge  s1, t1, chk_mid
    lb   t2, SEG(x0)
    addi t2, t2, 1
    sb   t2, SEG(x0)

chk_mid:
    # segment 1: middle, 3<=y<5 and 2<=x<6
    li   t1, 3
    blt  s0, t1, chk_bot
    li   t1, 5
    bge  s0, t1, chk_bot
    li   t1, 2
    blt  s1, t1, chk_bot
    li   t1, 6
    bge  s1, t1, chk_bot
    lb   t2, 0x51(x0)
    addi t2, t2, 1
    sb   t2, 0x51(x0)

chk_bot:
    # segment 2: bottom, y>=6 and 2<=x<6
    li   t1, 6
    blt  s0, t1, chk_ul
    li   t1, 2
    blt  s1, t1, chk_ul
    li   t1, 6
    bge  s1, t1, chk_ul
    lb   t2, 0x52(x0)
    addi t2, t2, 1
    sb   t2, 0x52(x0)

chk_ul:
    # segment 3: upper-left, 1<=y<4 and x<2
    li   t1, 1
    blt  s0, t1, chk_ur
    li   t1, 4
    bge  s0, t1, chk_ur
    li   t1, 2
    bge  s1, t1, chk_ur
    lb   t2, 0x53(x0)
    addi t2, t2, 1
    sb   t2, 0x53(x0)

chk_ur:
    # segment 4: upper-right, 1<=y<4 and x>=6
    li   t1, 1
    blt  s0, t1, chk_ll
    li   t1, 4
    bge  s0, t1, chk_ll
    li   t1, 6
    blt  s1, t1, chk_ll
    lb   t2, 0x54(x0)
    addi t2, t2, 1
    sb   t2, 0x54(x0)

chk_ll:
    # segment 5: lower-left, 4<=y<7 and x<2
    li   t1, 4
    blt  s0, t1, chk_lr
    li   t1, 7
    bge  s0, t1, chk_lr
    li   t1, 2
    bge  s1, t1, chk_lr
    lb   t2, 0x55(x0)
    addi t2, t2, 1
    sb   t2, 0x55(x0)

chk_lr:
    # segment 6: lower-right, 4<=y<7 and x>=6
    li   t1, 4
    blt  s0, t1, pix_next
    li   t1, 7
    bge  s0, t1, pix_next
    li   t1, 6
    blt  s1, t1, pix_next
    lb   t2, 0x56(x0)
    addi t2, t2, 1
    sb   t2, 0x56(x0)

pix_next:
    addi s2, s2, 1
    addi s1, s1, 1
    li   t0, 8
    blt  s1, t0, ix_loop
    addi s0, s0, 1
    li   t0, 8
    blt  s0, t0, iy_loop

    # Convert counters to a 7-bit mask. Horizontal threshold=4, vertical=3.
    li   s0, 0
    lb   t0, SEG(x0)
    li   t1, 4
    blt  t0, t1, m1
    ori  s0, s0, 1
m1:
    lb   t0, 0x51(x0)
    li   t1, 4
    blt  t0, t1, m2
    ori  s0, s0, 2
m2:
    lb   t0, 0x52(x0)
    li   t1, 4
    blt  t0, t1, m3
    ori  s0, s0, 4
m3:
    lb   t0, 0x53(x0)
    li   t1, 3
    blt  t0, t1, m4
    ori  s0, s0, 8
m4:
    lb   t0, 0x54(x0)
    li   t1, 3
    blt  t0, t1, m5
    ori  s0, s0, 16
m5:
    lb   t0, 0x55(x0)
    li   t1, 3
    blt  t0, t1, m6
    ori  s0, s0, 32
m6:
    lb   t0, 0x56(x0)
    li   t1, 3
    blt  t0, t1, classify
    ori  s0, s0, 64

classify:
    li   t0, 125
    beq  s0, t0, pred0
    li   t0, 80
    beq  s0, t0, pred1
    li   t0, 55
    beq  s0, t0, pred2
    li   t0, 87
    beq  s0, t0, pred3
    li   t0, 90
    beq  s0, t0, pred4
    li   t0, 79
    beq  s0, t0, pred5
    li   t0, 111
    beq  s0, t0, pred6
    li   t0, 81
    beq  s0, t0, pred7
    li   t0, 127
    beq  s0, t0, pred8
    li   t0, 95
    beq  s0, t0, pred9
    li   a0, '?'
    j    pred_emit
pred0: li a0, '0'; j pred_emit
pred1: li a0, '1'; j pred_emit
pred2: li a0, '2'; j pred_emit
pred3: li a0, '3'; j pred_emit
pred4: li a0, '4'; j pred_emit
pred5: li a0, '5'; j pred_emit
pred6: li a0, '6'; j pred_emit
pred7: li a0, '7'; j pred_emit
pred8: li a0, '8'; j pred_emit
pred9: li a0, '9'; j pred_emit

pred_emit:
    addi t0, a0, -48
    sw   t0, LED_OUT(x0)
    mv   s1, a0
    .puts "prediction: "
    mv   a0, s1
    jal  ra, putc
    .puts "\n"
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    addi sp, sp, 16
    ret

idle:
    j    idle2
idle2:
    j    idle
