# asm/sdram_diag.s -- interactive UART SDRAM diagnostic program.
#
# Usage assumptions:
# - UART MMIO follows the current top.v mapping.
# - SDRAM is mapped into the CPU address space as normal memory.
# - SDRAM_BASE below should be changed to match the final top-level decode.
#
# Shell commands:
#   h/?  show help
#   r    dump first 8 words from SDRAM_BASE
#   w    write 8 demo words to SDRAM_BASE
#   i    fill first 64 words with incremental pattern 1..64
#   c    check first 64 words against incremental pattern
#   t    run read/write smoke test with a few fixed patterns
#   l    run walking-1 single-word test
#   q    idle loop

.equ UART_TX,    0x1000
.equ UART_RX,    0x1004
.equ UART_STAT,  0x1008
.equ LED_OUT,    0x100C

.equ SDRAM_BASE, 0x20000000
.equ DUMP_WORDS, 8
.equ TEST_WORDS, 64
.equ TEST_WORDS_P1, 65

start:
    li   sp, 0xF00
    .puts "\nSDRAM diag\n"

shell_loop:
    .puts "sdram> "
    jal  ra, read_cmd

    li   t0, 'h'
    beq  a0, t0, shell_help
    li   t0, '?'
    beq  a0, t0, shell_help
    li   t0, 'r'
    beq  a0, t0, dump_cmd
    li   t0, 'w'
    beq  a0, t0, write_demo_cmd
    li   t0, 'i'
    beq  a0, t0, fill_incr_cmd
    li   t0, 'c'
    beq  a0, t0, check_incr_cmd
    li   t0, 't'
    beq  a0, t0, smoke_cmd
    li   t0, 'l'
    beq  a0, t0, walk_cmd
    li   t0, 'q'
    beq  a0, t0, idle
    .puts "?\n"
    j    shell_loop

shell_help:
    .puts "h/? r w i c t l q\n"
    j    shell_loop

dump_cmd:
    jal  ra, dump_words
    j    shell_loop

write_demo_cmd:
    jal  ra, write_demo_words
    .puts "demo written\n"
    li   t0, 1
    li   t1, LED_OUT
    sw   t0, 0(t1)
    j    shell_loop

fill_incr_cmd:
    jal  ra, fill_incremental
    .puts "fill done\n"
    li   t0, 2
    li   t1, LED_OUT
    sw   t0, 0(t1)
    j    shell_loop

check_incr_cmd:
    jal  ra, check_incremental
    j    shell_loop

smoke_cmd:
    jal  ra, smoke_test
    j    shell_loop

walk_cmd:
    jal  ra, walk1_test
    j    shell_loop

# =============================================================== putc(a0)
putc:
    li   t0, 2
    li   t2, UART_STAT
putc_w:
    lw   t1, 0(t2)
    and  t1, t1, t0
    bnez t1, putc_w
    li   t2, UART_TX
    sw   a0, 0(t2)
    ret

# =============================================================== read_key() -> a0
read_key:
    li   t0, 1
    li   t2, UART_STAT
rk_w:
    lw   t1, 0(t2)
    and  t1, t1, t0
    beqz t1, rk_w
    li   t2, UART_RX
    lw   a0, 0(t2)
    sw   x0, 0(t2)
    ret

# =============================================================== read_cmd() -> a0
# Returns first non-space command character before CR/LF.
read_cmd:
rc_loop:
    jal  ra, read_key
    li   t0, 0x0D
    beq  a0, t0, rc_loop
    li   t0, 0x0A
    beq  a0, t0, rc_loop
    li   t0, ' '
    beq  a0, t0, rc_loop
    ret

# =============================================================== print helpers
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

print_word_line:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    mv   s0, a0          # word index
    mv   s1, a1          # address
    .puts "["
    mv   a0, s0
    jal  ra, print_nibble
    .puts "] @0x"
    mv   a0, s1
    jal  ra, print_hex32
    .puts " = 0x"
    lw   a0, 0(s1)
    jal  ra, print_hex32
    .puts "\n"
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    addi sp, sp, 16
    ret

print_fail_idx:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    mv   s0, a0          # index
    mv   s1, a1          # expected
    mv   s2, a2          # got
    .puts "FAIL idx="
    mv   a0, s0
    jal  ra, print_hex32
    .puts " exp=0x"
    mv   a0, s1
    jal  ra, print_hex32
    .puts " got=0x"
    mv   a0, s2
    jal  ra, print_hex32
    .puts "\n"
    li   t0, 15
    li   t1, LED_OUT
    sw   t0, 0(t1)
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    addi sp, sp, 20
    ret

# =============================================================== dump first 8 words
dump_words:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    li   s0, SDRAM_BASE
    li   s1, 0
dw_loop:
    mv   a0, s1
    mv   a1, s0
    jal  ra, print_word_line
    addi s0, s0, 4
    addi s1, s1, 1
    li   t0, DUMP_WORDS
    blt  s1, t0, dw_loop
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

# =============================================================== write fixed demo words
write_demo_words:
    li   s0, SDRAM_BASE
    li   t0, 0x01010101
    sw   t0, 0(s0)
    li   t0, 0x11111111
    sw   t0, 4(s0)
    li   t0, 0x22222222
    sw   t0, 8(s0)
    li   t0, 0x33333333
    sw   t0, 12(s0)
    li   t0, 0x44444444
    sw   t0, 16(s0)
    li   t0, 0x55555555
    sw   t0, 20(s0)
    li   t0, 0xAAAAAAAA
    sw   t0, 24(s0)
    li   t0, 0x12345678
    sw   t0, 28(s0)
    ret

# =============================================================== fill 64 words with 1..64
fill_incremental:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    li   s0, SDRAM_BASE
    li   s1, 1
fi_loop:
    sw   s1, 0(s0)
    addi s0, s0, 4
    addi s1, s1, 1
    li   t0, TEST_WORDS_P1
    blt  s1, t0, fi_loop
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

# =============================================================== check 64 words against 1..64
check_incremental:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    li   s0, SDRAM_BASE
    li   s1, 1
ci_loop:
    lw   s2, 0(s0)
    bne  s2, s1, ci_fail
    addi s0, s0, 4
    addi s1, s1, 1
    li   t0, TEST_WORDS_P1
    blt  s1, t0, ci_loop
    .puts "CHECK PASS\n"
    li   t0, 3
    li   t1, LED_OUT
    sw   t0, 0(t1)
    j    ci_ret
ci_fail:
    addi a0, s1, -1
    mv   a1, s1
    mv   a2, s2
    jal  ra, print_fail_idx
ci_ret:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    addi sp, sp, 16
    ret

# =============================================================== smoke read/write test
smoke_test:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    li   s0, SDRAM_BASE

    li   s1, 0x12345678
    sw   s1, 0(s0)
    lw   s2, 0(s0)
    bne  s2, s1, st_fail0

    li   s1, 0xA5A5A5A5
    sw   s1, 4(s0)
    lw   s2, 4(s0)
    bne  s2, s1, st_fail1

    li   s1, 0x5A5A5A5A
    sw   s1, 8(s0)
    lw   s2, 8(s0)
    bne  s2, s1, st_fail2

    .puts "SMOKE PASS\n"
    li   t0, 4
    li   t1, LED_OUT
    sw   t0, 0(t1)
    j    st_ret

st_fail0:
    li   a0, 0
    mv   a1, s1
    mv   a2, s2
    jal  ra, print_fail_idx
    j    st_ret
st_fail1:
    li   a0, 1
    mv   a1, s1
    mv   a2, s2
    jal  ra, print_fail_idx
    j    st_ret
st_fail2:
    li   a0, 2
    mv   a1, s1
    mv   a2, s2
    jal  ra, print_fail_idx
st_ret:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    addi sp, sp, 20
    ret

# =============================================================== walking-1 single-word test
walk1_test:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    sw   s2, 12(sp)
    sw   s3, 16(sp)
    li   s0, SDRAM_BASE
    li   s1, 1
    li   s2, 0
w1_loop:
    sw   s1, 0(s0)
    lw   s3, 0(s0)
    bne  s3, s1, w1_fail
    slli s1, s1, 1
    addi s2, s2, 1
    li   t0, 32
    blt  s2, t0, w1_loop
    .puts "WALK1 PASS\n"
    li   t0, 5
    li   t1, LED_OUT
    sw   t0, 0(t1)
    j    w1_ret
w1_fail:
    mv   a0, s2
    mv   a1, s1
    mv   a2, s3
    jal  ra, print_fail_idx
w1_ret:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    lw   s2, 12(sp)
    lw   s3, 16(sp)
    addi sp, sp, 20
    ret

idle:
    j    idle2
idle2:
    j    idle
