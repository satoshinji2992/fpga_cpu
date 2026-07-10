# all_features_riscv.s
#
# 综合演示当前 CPU 已实现的主要功能:
# - RV32I 算术/逻辑/移位/比较
# - load/store, byte store, word load/store
# - load-use hazard stall
# - 分支循环, 可体现 BHT 分支预测
# - RV32M: MUL/DIV/REM
# - custom-0: POPCOUNT/BITREVERSE
# - CSR read: RDCYCLE
# - ECALL halt
#
# 当前 CPU 没有实现浮点数, 所以本程序不包含浮点指令。
#                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   
# 预期内存结果:
# Mem[0]  = 42          # MUL 7*6
# Mem[1]  = 1           # DIV 7/6
# Mem[2]  = 1           # REM 7%6
# Mem[3]  = 18          # POPCOUNT(0xABCD00FF)
# Mem[4]  = 0xFF00B3D5  # BITREVERSE(0xABCD00FF)
# Mem[5]  = 55          # 1+2+...+10
# Mem[6]  = 0x34801200  # SB/LW 访存拼接
# Mem[7]  = cycle       # RDCYCLE, 大于 0
# Mem[8]  = 43          # LW 后立即 ADDI, 验证 load-use stall
# Mem[9]  = 255         # OR/ANDI/XORI/SLLI/SRLI
# Mem[10] = 1           # SLT/SLTU/ADD 比较结果
#
# 下面使用 GNU/LLVM 风格汇编助记符描述。custom 指令若汇编器不认识,
# 可直接参考 src/tb_all_features.v 中的机器码。

    .section .text
    .globl _start

_start:
    addi x1,  x0, 7
    addi x2,  x0, 6
    mul  x3,  x1, x2
    div  x4,  x1, x2
    rem  x5,  x1, x2
    sw   x3,  0(x0)
    sw   x4,  4(x0)
    sw   x5,  8(x0)

    lui  x6,  0xABCD0
    addi x6,  x6, 0x0FF
    # custom-0 POPCOUNT x7, x6   machine code: 0x0003138B
    # custom-0 BITREV   x8, x6   machine code: 0x0003240B
    sw   x7,  12(x0)
    sw   x8,  16(x0)

    addi x9,  x0, 0      # sum
    addi x10, x0, 1      # i
    addi x11, x0, 11     # bound
loop:
    add  x9,  x9, x10
    addi x10, x10, 1
    blt  x10, x11, loop
    sw   x9,  20(x0)

    addi x12, x0, 0x12
    sb   x12, 25(x0)
    addi x13, x0, -128
    sb   x13, 26(x0)
    addi x14, x0, 0x34
    sb   x14, 27(x0)
    lw   x15, 24(x0)
    sw   x15, 24(x0)

    rdcycle x16
    sw   x16, 28(x0)

    lw   x17, 0(x0)
    addi x18, x17, 1
    sw   x18, 32(x0)

    addi x19, x0, 0x0F
    addi x20, x0, 0x0F0
    or   x21, x19, x20
    andi x22, x21, 0x0AA
    xori x23, x22, 0x055
    slli x24, x23, 1
    srli x25, x24, 1
    sw   x25, 36(x0)

    slt  x26, x1, x2
    sltu x27, x2, x1
    add  x28, x26, x27
    sw   x28, 40(x0)

    ecall
