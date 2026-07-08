# asm/dungeon.s — turn-based dungeon running on the RV32I/M CPU.
#
# The CPU does ALL IO itself via memory-mapped peripherals (see top.v):
#   0x400 UART_TX  (write a byte -> send)
#   0x404 UART_RX  (read -> byte; write -> ack, clears rx_pending)
#   0x408 UART_STAT(read -> {30'b0, tx_busy, rx_pending})
#   0x40C LED_OUT  (write -> LED[3:0])
#
# Data RAM layout (byte addresses):
#   0x00-0x1F  GRID  8x4 cells: '.'(0x2E) floor, '#'(0x23) wall, 'M'(0x4D) monster
#   0x20 PHP   player HP        0x24 PX  player x        0x28 PY  player y
#   0x2C MHP   monster HP
#   0x30       decimal-print scratch buffer
#   ~0x300-0x3F0  stack (sp set at init)
#
# Features exercised:
#   - data RAM (grid + state)        - MUL (crit damage)
#   - UART MMIO (render + W/A/S/D)   - DIVU/REMU (counter-attack, decimal print)
#   - branches (bounds, win/lose)    - RDCYCLE (PRNG seed)
#   - POPCOUNT (crit coin-flip)      - LED_OUT (HP bar)

.equ UART_TX,   0x400
.equ UART_RX,   0x404
.equ UART_STAT, 0x408
.equ LED_OUT,   0x40C

.equ PHP,    0x20
.equ PX,     0x24
.equ PY,     0x28
.equ MHP,    0x2C
.equ DECBUF, 0x30

# ---------------------------------------------------------------- start / init
start:
    li   sp, 0x3F0                 # stack near top of data RAM
    # fill 32 grid cells with floor '.'
    li   t0, 0
    li   t1, 32
    li   t2, 0x2E
fill:
    sb   t2, 0(t0)
    addi t0, t0, 1
    blt  t0, t1, fill
    # one wall at (3,2) = cell 19, monster at (6,2) = cell 22
    li   t0, 0x23
    li   t1, 19
    sb   t0, 0(t1)
    li   t0, 0x4D
    li   t1, 22
    sb   t0, 0(t1)
    # stats: player HP=20 at (1,1), monster HP=12
    li   t0, 20
    sw   t0, PHP(x0)
    li   t0, 1
    sw   t0, PX(x0)
    sw   t0, PY(x0)
    li   t0, 12
    sw   t0, MHP(x0)

main_loop:
    jal  ra, render
    jal  ra, check_end
    .puts "cmd> "
    jal  ra, read_key
    jal  ra, process_key
    j    main_loop

# =============================================================== putc(a0)
putc:
    li   t0, 2                     # tx_busy bit
putc_w:
    lw   t1, UART_STAT(x0)
    and  t1, t1, t0
    bnez t1, putc_w
    sw   a0, UART_TX(x0)
    ret

# =============================================================== read_key() -> a0
read_key:
    li   t0, 1                     # rx_pending bit
rk_w:
    lw   t1, UART_STAT(x0)
    and  t1, t1, t0
    beqz t1, rk_w
    lw   a0, UART_RX(x0)
    sw   x0, UART_RX(x0)           # ack: clears rx_pending
    ret

# =============================================================== print_decimal(a0)
print_decimal:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    li   t2, 10
    li   t3, DECBUF                # write ptr (LSB first); div loop has no calls
    beqz a0, pd_zero
pd_div:
    divu t1, a0, t2                # n / 10
    remu t0, a0, t2                # n % 10
    addi t0, t0, 0x30
    sb   t0, 0(t3)
    addi t3, t3, 1
    mv   a0, t1
    bnez a0, pd_div
    j    pd_emit
pd_zero:
    li   t0, 0x30
    sb   t0, 0(t3)
    addi t3, t3, 1
pd_emit:
    addi t3, t3, -1
    mv   s0, t3                    # emit ptr in s0 (survives putc calls)
pd_emit_l:
    lb   a0, 0(s0)
    jal  ra, putc
    li   t4, DECBUF
    beq  s0, t4, pd_done
    addi s0, s0, -1
    j    pd_emit_l
pd_done:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# =============================================================== render()
render:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    sw   s4, 20(sp)
    li   a0, 0x0A
    jal  ra, putc
    li   s0, 0                     # y
rend_y:
    li   s1, 0                     # x
rend_x:
    li   s2, 8
    mul  s2, s0, s2                # y*8  (MUL)
    add  s2, s2, s1                # cell = y*8 + x
    lw   s3, PX(x0)
    lw   s4, PY(x0)
    bne  s1, s3, rend_np           # x != PX
    bne  s0, s4, rend_np           # y != PY
    li   a0, 0x40                  # '@' player overlay
    j    rend_p
rend_np:
    lb   a0, 0(s2)                 # grid cell
rend_p:
    jal  ra, putc
    addi s1, s1, 1
    li   t0, 8
    blt  s1, t0, rend_x
    li   a0, 0x0A
    jal  ra, putc
    addi s0, s0, 1
    li   t0, 4
    blt  s0, t0, rend_y
    .puts "HP "
    lw   a0, PHP(x0)
    jal  ra, print_decimal
    .puts "  M "
    lw   a0, MHP(x0)
    jal  ra, print_decimal
    li   a0, 0x0A
    jal  ra, putc
    # LED HP bar (4 thresholds)
    lw   s0, PHP(x0)
    li   s1, 0xF
    li   t0, 15
    bge  s0, t0, rend_led
    li   s1, 0x7
    li   t0, 10
    bge  s0, t0, rend_led
    li   s1, 0x3
    li   t0, 5
    bge  s0, t0, rend_led
    li   s1, 0x1
rend_led:
    sw   s1, LED_OUT(x0)
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    addi sp, sp, 24
    ret

# =============================================================== check_end()
check_end:
    lw   t0, MHP(x0)
    blez t0, ce_win
    lw   t0, PHP(x0)
    blez t0, ce_lose
    ret
ce_win:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .puts "\nYOU WIN\n"
    lw   ra, 0(sp)
    addi sp, sp, 4
    j    idle
ce_lose:
    addi sp, sp, -4
    sw   ra, 0(sp)
    .puts "\nYOU DIED\n"
    lw   ra, 0(sp)
    addi sp, sp, 4
    j    idle

# =============================================================== process_key(a0)
process_key:
    addi sp, sp, -32
    sw   ra, 0(sp)
    sw   s0, 4(sp)                 # dx
    sw   s1, 8(sp)                 # dy
    sw   s2, 12(sp)                # nx
    sw   s3, 16(sp)                # ny
    sw   s4, 20(sp)                # target cell
    sw   s5, 24(sp)                # new MHP (survives print calls)
    sw   s6, 28(sp)                # damage (survives print calls)
    li   t0, 'w'
    beq  a0, t0, pk_up
    li   t0, 's'
    beq  a0, t0, pk_dn
    li   t0, 'a'
    beq  a0, t0, pk_lf
    li   t0, 'd'
    beq  a0, t0, pk_rt
    j    pk_ret                    # ignore other chars
pk_up: li s0, 0;  li s1, -1; j pk_mov
pk_dn: li s0, 0;  li s1, 1;  j pk_mov
pk_lf: li s0, -1; li s1, 0;  j pk_mov
pk_rt: li s0, 1;  li s1, 0;  j pk_mov
pk_mov:
    lw   t0, PX(x0)
    lw   t1, PY(x0)
    add  s2, t0, s0                # nx = PX + dx
    add  s3, t1, s1                # ny = PY + dy
    bltz s2, pk_ret                # bounds (signed)
    bltz s3, pk_ret
    li   t0, 8
    bge  s2, t0, pk_ret
    li   t0, 4
    bge  s3, t0, pk_ret
    li   s4, 8
    mul  s4, s3, s4                # cell = ny*8  (MUL)
    add  s4, s4, s2
    lb   t0, 0(s4)                 # terrain at target
    li   t1, 0x23
    beq  t0, t1, pk_wall           # '#'
    li   t1, 0x4D
    beq  t0, t1, pk_combat         # 'M'
    sw   s2, PX(x0)                # floor -> move
    sw   s3, PY(x0)
    j    pk_ret
pk_wall:
    .puts "wall\n"
    j    pk_ret
pk_combat:
    # player attack: dmg = ATK(4) * (1 + crit), crit = popcount(rdcycle) & 1
    li   t0, 4
    rdcycle t1
    popcount t1, t1
    andi t1, t1, 1
    addi t1, t1, 1                 # crit_mul = 1 or 2
    mul  t0, t0, t1                # dmg  (MUL)
    lw   t2, MHP(x0)
    sub  t2, t2, t0
    sw   t2, MHP(x0)
    mv   s5, t2                    # new MHP
    mv   s6, t0                    # dmg
    .puts "hit "
    mv   a0, s6
    jal  ra, print_decimal
    li   a0, 0x0A
    jal  ra, putc
    bgtz s5, pk_counter
    li   t0, 0x2E                  # monster dead -> clear 'M'
    sb   t0, 0(s4)
    j    pk_ret
pk_counter:
    # monster hits back: mdmg = MATK(3) / PDEF(2)  (DIVU)
    li   t0, 3
    li   t1, 2
    divu t0, t0, t1
    lw   t2, PHP(x0)
    sub  t2, t2, t0
    sw   t2, PHP(x0)
    mv   s6, t0                    # mdmg
    .puts "ouch "
    mv   a0, s6
    jal  ra, print_decimal
    li   a0, 0x0A
    jal  ra, putc
pk_ret:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    lw   s4, 20(sp)
    lw   s5, 24(sp)
    lw   s6, 28(sp)
    addi sp, sp, 32
    ret

# -------------------------------------------------------------- halt-free idle
# (a plain `j self` would encode to 0x0000006F and trigger the core's halt,
#  so we bounce between two instructions with non-zero offsets)
idle:
    j    idle2
idle2:
    j    idle
