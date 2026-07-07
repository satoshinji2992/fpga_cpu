# RISC-V Assembly - Array Operations# 演示数组访问和内存操作    .section .data
# === 测试数组 ===array:  .word 10, 20, 30, 40, 50, 60, 70, 80, 90, 100len:    .word 10              # 数组长度    .section .text    .globl _start_start:
    # === 数组求和 ===
    # 加载数组地址和长度    la   t0, array           # t0 = &array[0]
    lw   t1, len, 0          # t1 = 长度 = 10    addi t2, zero, 0         # t2 = sum = 0
    addi t3, zero, 0         # t3 = 索引 = 0sum_loop:
    beq  t3, t1, sum_end     # if (index == length) goto end    lw   t4, 0(t0)            # t4 = array[index]
    add  t2, t2, t4          # sum += array[index]    addi t0, t0, 4           # &array[index+1]
    addi t3, t3, 1           # index++    j    sum_loopsum_end:    # t2 现在包含总和 = 550    # === 查找最大值 ===    la   t0, array           # 重置数组指针
    lw   t1, len, 0          # 重置长度
    lw   t5, 0(t0)           # t5 = max = array[0]
    addi t3, zero, 1         # t3 = 索引 = 1 (从第二个开始)max_loop:
    beq  t3, t1, max_end     # if (index == length) goto end    addi t0, t0, 4           # &array[index]
    lw   t4, 0(t0)           # t4 = array[index]    blt  t5, t4, update_max  # if (max < current) update    j    continue_maxupdate_max:
    addi t5, t4, zero        # max = currentcontinue_max:
    addi t3, t3, 1           # index++    j    max_loopmax_end:    # t5 现在包含最大值 = 100    # === 计算平均值 ===    # 平均值 = sum / length    # 这里使用简单的除法(假设能整除)
    div  t6, t2, t1          # t6 = average = 550 / 10 = 55# 注意: div 需要M扩展，如果不可用可以用循环实现# === 数组反转 (原地) ===    la   t0, array           # t0 = &array[0] (左指针)
    lw   t1, len, 0          # t1 = 长度
    addi t1, t1, -1          # t1 = 长度 - 1
    slli t1, t1, 2          # t1 = (长度-1) * 4 (字节偏移)
    add  t1, t0, t1          # t1 = &array[length-1] (右指针)
    addi t2, zero, 0         # t2 = 计数器 = 0
    lw   t3, len, 0          # t3 = 循环次数 = length/2    addi t4, zero, 2
    div  t3, t3, t4reverse_loop:
    beq  t2, t3, reverse_end # if (计数 >= length/2) goto end    # 交换 array[left] 和 array[right]
    lw   t5, 0(t0)           # t5 = array[left]
    lw   t6, 0(t1)           # t6 = array[right]    sw   t6, 0(t0)           # array[left] = array[right]
    sw   t5, 0(t1)           # array[right] = array[left]    addi t0, t0, 4           # left++    addi t1, t1, -4          # right--
    addi t2, t2, 1           # 计数器++    j    reverse_loopreverse_end:    # 数组现在已反转: [100, 90, 80, 70, 60, 50, 40, 30, 20, 10]    # === 程序结束 ===    end_loop:
    j    end_loop           # 无限循环# === 寄存器使用总结 ===# t0: 数组指针# t1: 数组长度/右指针# t2: 总和/计数器
# t3: 索引/循环次数# t4: 临时存储# t5: 最大值/临时存储# t6: 平均值/临时存储# === 预期结果 ===# 原始数组: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]# 总和: 550# 最大值: 100
# 平均值: 55# 反转后: [100, 90, 80, 70, 60, 50, 40, 30, 20, 10]# === 扩展练习 ===# 1. 实现冒泡排序# 2. 实现二分查找# 3. 计算数组的标准差# 4. 实现矩阵乘法# 5. 实现字符串处理函数
