# RISC-V Assembly - Hello World Program
# 这是您的第一个RISC-V汇编程序

    .section .text
    .globl _start

# 程序入口点
_start:
    # 初始化寄存器
    addi x1, x0, 10     # x1 = 10
    addi x2, x0, 20     # x2 = 20
    addi x3, x0, 0      # x3 = 0 (将存储结果)

    # 执行加法
    add  x3, x1, x2     # x3 = x1 + x2 = 30

    # 执行减法
    addi x4, x0, 50     # x4 = 50
    sub  x5, x4, x1     # x5 = x4 - x1 = 40

    # 执行乘法 (通过重复加法模拟)
    addi x6, x0, 0      # x6 = 0 (结果)
    addi x7, x0, 5      # x7 = 5 (计数器)
    addi x8, x0, 7      # x8 = 7 (被乘数)

mult_loop:
    beq  x7, x0, mult_end    # if (x7 == 0) goto mult_end
    add  x6, x6, x8          # x6 += x8
    addi x7, x7, -1          # x7--
    j    mult_loop

mult_end:
    # 结果: x6 = 5 * 7 = 35

    # 简单的循环计数
    addi x9, x0, 0      # x9 = 0 (计数器)
    addi x10, x0, 10    # x10 = 10 (循环次数)

count_loop:
    beq  x10, x0, count_end   # if (x10 == 0) goto end
    addi x9, x9, 1            # x9++
    addi x10, x10, -1         # x10--
    j    count_loop

count_end:
    # 结果: x9 = 10

    # 程序结束 (无限循环)
    j    _start

# 寄存器使用说明:
# x0-x3: 基础计算
# x4-x5: 减法结果
# x6-x8: 乘法循环
# x9-x10: 计数循环
