# Minimal custom float32 extension demo.
# Float32 bit patterns are stored in normal integer registers.

start:
    li      x1, 0x3fc00000      # 1.5
    li      x2, 0x40100000      # 2.25
    li      x3, 0x40000000      # 2.0
    fadd32  x4, x1, x2          # 3.75 -> 0x40700000
    fmul32  x5, x1, x3          # 3.0  -> 0x40400000
    fgt32   x6, x2, x1          # 2.25 > 1.5 -> 1
    sw      x4, 0(x0)
    sw      x5, 4(x0)
    sw      x6, 8(x0)
    ebreak
