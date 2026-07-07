# RISC-V 汇编入门教程

> 在开始设计处理器之前，先理解它执行的指令

## 📚 RISC-V 寄存器

RISC-V有32个通用寄存器 (x0-x31)：

| 寄存器 | 名字    | 用途              | 保存者 |
|--------|---------|-------------------|--------|
| x0     | zero   | 常零值            | -      |
| x1     | ra     | 返回地址          | 调用者 |
| x2     | sp     | 栈指针            | 被调用者|
| x3     | gp     | 全局指针          | -      |
| x4     | tp     | 线程指针          | -      |
| x5-x7  | t0-t2  | 临时寄存器        | 调用者 |
| x8     | s0/fp  | 保存寄存器/帧指针  | 被调用者|
| x9     | s1     | 保存寄存器        | 被调用者|
| x10-x11| a0-a1  | 函数参数/返回值   | 调用者 |
| x12-x17| a2-a7  | 函数参数          | 调用者 |
| x18-x27| s2-s11 | 保存寄存器        | 被调用者|
| x28-x31| t3-t6  | 临时寄存器        | 调用者 |

## 🔢 基础指令格式

RISC-V指令是32位宽，主要分为R型、I型、S型、B型、U型、J型：

```
R型 (寄存器-寄存器):
|31-25|   24-20   |19-15|14-12|11-7|6-0|
| rs2 |   rs1    |funct3| rd |opcode|
  7      5         5     3    5    7

I型 (立即数):
|31-20|   19-15   |14-12|11-7|6-0|
| imm  |   rs1    |funct3| rd |opcode|
  12      5         3     5    7
```

## 📖 基础指令

### 算术运算

```riscv
# 加法
add x1, x2, x3    # x1 = x2 + x3
addi x1, x2, 5    # x1 = x2 + 5  (立即数加法)

# 减法
sub x1, x2, x3    # x1 = x2 - x3

# 逻辑运算
and x1, x2, x3    # x1 = x2 & x3  (与)
or  x1, x2, x3    # x1 = x2 | x3  (或)
xor x1, x2, x3    # x1 = x2 ^ x3  (异或)

# 移位
sll x1, x2, x3    # x1 = x2 << x3  (左移)
srl x1, x2, x3    # x1 = x2 >> x3  (逻辑右移)
sra x1, x2, x3    # x1 = x2 >> x3  (算术右移)
```

### 访问内存

```riscv
# 加载字 (32位)
lw x1, 0(x2)      # x1 = MEM[x2 + 0]
lh x1, 4(x2)      # x1 = MEM[x2 + 4] (16位)
lb x1, 8(x2)      # x1 = MEM[x2 + 8] (8位)

# 存储字
sw x1, 0(x2)      # MEM[x2 + 0] = x1
sh x1, 4(x2)      # MEM[x2 + 4] = x1 (16位)
sb x1, 8(x2)      # MEM[x2 + 8] = x1 (8位)
```

### 分支跳转

```riscv
# 无条件跳转
jal x1, label     # x1 = return_addr, PC = label
jalr x1, x2, 4    # x1 = return_addr, PC = x2 + 4

# 条件分支
beq x1, x2, label # if (x1 == x2) PC = label
bne x1, x2, label # if (x1 != x2) PC = label
blt x1, x2, label # if (x1 <  x2) PC = label
bge x1, x2, label # if (x1 >= x2) PC = label
```

### 比较指令

```riscv
slt x1, x2, x3    # x1 = (x2 < x3) ? 1 : 0
slti x1, x2, 5    # x1 = (x2 <  5) ? 1 : 0
sltu x1, x2, x3   # 无符号比较
```

## 💡 示例程序

### 示例1: Hello World (计算斐波那契数列)

```riscv# 斐波那契数列计算# 计算 fib(10) = 55    .section .text
    .globl _start_start:    # 初始化
    addi t0, zero, 0        # t0 = 0  (当前值)
    addi t1, zero, 1        # t1 = 1  (下一个值)
    addi t2, zero, 10       # t2 = 10 (循环计数)loop:
    beq  t2, zero, end     # if (t2 == 0) goto end    add  t3, t0, t1        # t3 = t0 + t1
    addi t0, t1, zero       # t0 = t1
    addi t1, t3, zero       # t1 = t3
    addi t2, t2, -1         # t2--    j    loop                # 重复end:
    # 结果在 t0 中，应该是 55    # 这里可以添加输出或停止代码
    nop                     # 空操作    .end
```

### 示例2: 数组求和

```riscv# 数组求和
    .section .data
array:  .word 1, 2, 3, 4, 5  # 5个元素的数组len:    .word 5              # 数组长度    .section .text    .globl _start
_start:
    la   t0, array           # t0 = &array[0]
    lw   t1, len, 0          # t1 = 长度 = 5
    addi t2, zero, 0         # t2 = sum = 0loop:
    beq  t1, zero, end       # if (t1 == 0) goto end
    lw   t3, 0(t0)           # t3 = array[i]    add  t2, t2, t3          # sum += t3
    addi t0, t0, 4           # &array[i++]
    addi t1, t1, -1          # count--    j    loopend:
    # 结果在 t2 中，应该是 15    nop
```

### 示例3: 函数调用

```riscv# 函数调用示例    .section .text    .globl _start_start:    addi a0, zero, 5       # 参数: n = 5    jal  ra, factorial     # 调用函数
    # 返回值在 a0 中，应该是 120    nop                     # 函数: 计算阶乘 n! = n * (n-1) * ... * 1# 参数: a0 = n# 返回: a0 = n!
factorial:
    addi sp, sp, -8         # 分配栈帧
    sw   ra, 4(sp)          # 保存返回地址
    sw   s0, 0(sp)          # 保存寄存器    addi s0, a0, zero       # s0 = n
    addi t0, zero, 1        # t0 = 1
    ble  s0, t0, return     # if (n <= 1) return    addi a0, s0, -1         # a0 = n - 1
    jal  ra, factorial      # 递归调用
    mulw a0, s0, a0         # a0 = n * (n-1)!
    j    end_funcreturn:
    addi a0, zero, 1        # return 1end_func:
    lw   s0, 0(sp)          # 恢复寄存器
    lw   ra, 4(sp)          # 恢复返回地址
    addi sp, sp, 8          # 释放栈帧    ret                      # 返回
```

## 🎯 练习任务

### 简单练习
1. 计算 1+2+3+...+100
2. 找出数组中的最大值
3. 实现字符串长度计算

### 中级练习
1. 实现冒泡排序
2. 实现二分查找
3. 计算最大公约数 (GCD)

### 高级练习
1. 实现简单的malloc/free
2. 实现链表操作
3. 实现递归算法

## 🛠️ 在线工具

### RISC-V 汇编器/模拟器

1. **Compiler Explorer (godbolt.org)**
   - 选择 RISC-V 编译器
   - 可以看到C代码对应的汇编

2. **RISC-V Simulator**
   - https://www.chipverify.com/risc-v-simulator
   - 在线运行RISC-V汇编

3. **本地工具链**
   ```bash
   # 安装RISC-V工具链
   sudo apt install gcc-riscv64-unknown-elf

   # 汇编
   riscv64-unknown-elf-as -o test.o test.s

   # 链接
   riscv64-unknown-elf-ld -o test test.o

   # 反汇编
   riscv64-unknown-elf-objdump -d test
   ```

## 📝 伪指令

汇编器提供了一些伪指令方便编程：

```riscv
# 伪指令         # 实际指令
mv x1, x2      # addi x1, x2, 0
nop            # addi x0, x0, 0
not x1, x2     # xori x1, x2, -1
neg x1, x2     # sub x1, x0, x2
ret            # jalr x0, x1, 0
li x1, 100     # addi x1, x0, 100 (小立即数)
               # lui x1, 100 >> 12; addiw x1, x1, 100 & 0xFFF (大立即数)
```

## 🚀 下一步

完成这些练习后，您将：
1. 理解RISC-V指令集
2. 理解程序执行流程
3. 为设计处理器做好准备

接下来可以：
- 研究PicoRV32源码
- 开始设计简单的处理器核心
- 在Verilog中实现您理解的指令

祝学习愉快！🎉
