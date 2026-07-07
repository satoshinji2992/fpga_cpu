# RISC-V Assembly - Fibonacci Sequence# 计算斐波那契数列: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55...    .section .text    .globl __start
_start:
    # === 初始化 ===
    addi t0, zero, 0        # t0 = fib(n-2) = 0
    addi t1, zero, 1        # t1 = fib(n-1) = 1
    addi t2, zero, 10       # t2 = n (计算fib(10))
    addi t3, zero, 2        # t3 = 当前计数器    # === 检查特殊情况 ===    addi t4, zero, 0        # t4 = 0    beq  t2, t4, done       # if n == 0, result = 0
    addi t4, zero, 1
    beq  t2, t4, one_case   # if n == 1, result = 1
    j    loop               # else goto loopone_case:
    addi t0, zero, 1        # result = 1    j    done
    # === 斐波那契循环 ===# t0 = fib(i-2), t1 = fib(i-1), t2 = nloop:
    bge  t3, t2, done       # if i >= n, goto done    # 计算下一个斐波那契数
    add  t4, t0, t1         # t4 = fib(i) = fib(i-2) + fib(i-1)    # 更新寄存器
    addi t0, t1, zero       # fib(i-2) = old fib(i-1)
    addi t1, t4, zero       # fib(i-1) = fib(i)    addi t3, t3, 1         # i++    j    loopdone:    # === 结果 ===    # t1 包含 fib(n) 的值    # 对于 n=10, t1 应该 = 55    # === 调试信息 ===    # 在仿真器中可以观察以下寄存器:    # t1: 最终结果 (应该是 55)    # t2: 输入参数 (10)    # t3: 最终计数器 (10)    # === 程序结束 ===    # 在实际硬件上，这里可以添加:    # 1. 输出到UART    # 2. 写入GPIO    # 3. 触发中断    # 为了演示，我们进入无限循环end_loop:    j end_loop
    # === 数据段 (用于存储结果) ===    .section .dataresults:    .word 0              # 存储最终结果    .word 1              # fib(1)    .word 1              # fib(2)    .word 2              # fib(3)    .word 3              # fib(4)    .word 5              # fib(5)    .word 8              # fib(6)    .word 13             # fib(7)    .word 21             # fib(8)    .word 34             # fib(9)
    .word 55              # fib(10)# === 预期结果表 ===# n   | fib(n)  # 0   | 0# 1   | 1# 2   | 1  # 3   | 2# 4   | 3# 5   | 5# 6   | 8# 7   | 13# 8   | 21# 9   | 34# 10  | 55
