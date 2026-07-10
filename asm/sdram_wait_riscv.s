# Variable-latency memory / SDRAM-style wait-state demo.
#
# The CPU must hold the MEM stage while data_ready=0. The testbench backs the
# data bus with sdram_latency_model.v and checks dependent loads/stores.

start:
    li   t0, 0x12345678
    sw   t0, 0(x0)
    lw   t1, 0(x0)
    addi t2, t1, 1
    sw   t2, 4(x0)
    lw   t3, 4(x0)
    sw   t3, 8(x0)
halt:
    j    halt
