# Minimal machine-mode interrupt demo.
#
# Main program enables machine external interrupts, then spins. The testbench
# pulses irq_external; the handler records:
#   Mem[0] = 1
#   Mem[1] = mcause (0x8000000B)
#   Mem[2] = mepc   (non-zero return PC)
#   Mem[3] = main loop counter

start:
    la   t0, handler
    csrw mtvec, t0
    li   t0, 0x800
    csrw mie, t0
    li   t0, 0x8
    csrw mstatus, t0
    li   t1, 0

main_loop:
    addi t1, t1, 1
    sw   t1, 12(x0)
    j    main_loop

handler:
    li    t2, 1
    sw    t2, 0(x0)
    csrrs t3, mcause, x0
    sw    t3, 4(x0)
    csrrs t4, mepc, x0
    sw    t4, 8(x0)
    mret
