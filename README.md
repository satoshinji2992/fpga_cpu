# FPGA RISC-V CPU

面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 的 RISC-V CPU 课程设计。工程包含可仿真的基础 CPU、可上板的五级流水线 CPU、片上内存、I-Cache、LED/KEY、真正由 CPU 访问的 UART MMIO，以及 CPU 自己运行的串口 shell、8x8 手写数字推理和 Pong demo。

## 当前实现

### 基础层次

- RV32I 子集单周期 CPU：`src/cpu_core.v`
- 支持算术逻辑、移位比较、访存、跳转分支、立即数等基本指令
- 仿真 testbench：`src/tb_cpu_core.v`
- 可运行固化测试程序，仿真结果为 `PASS`

### 进阶层次

- 五级流水线 CPU：`src/riscv_pipeline_core.v`
- 流水线阶段：IF / ID / EX / MEM / WB
- EX 阶段数据转发
- load-use 数据冒险暂停
- 分支/跳转冲刷流水线
- 16 项 2-bit BHT 动态分支预测，可用参数关闭对比 baseline
- 片上指令 ROM 和片上数据 RAM
- 8 行直接映射 I-Cache：`src/icache_direct_mapped.v`
- LED / KEY / UART memory-mapped I/O
- CPU 通过 MMIO 自己读 UART 输入、写 UART 输出
- CPU 自己运行串口 shell、8x8 数字推理和 Pong 程序：`asm/cnn_digit.s`
- Python 串口终端：`scripts/serial_shell.py`
- 硬件性能计数器：cycle、instret、branch、flush、load-use stall、branch miss、mdu inst
- 最小 CSR 读取：`RDCYCLE` / `RDINSTRET`
- `ECALL` / `EBREAK` 作为 halt

### 拓展层次

- RV32M 乘除法扩展：`MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU`
- 自定义 custom-0 指令：
  - `POPCOUNT`
  - `BITREVERSE`
  - `FADD32`
  - `FMUL32`
  - `FGT32`
- 2 路组相联 I-Cache + LRU 对比模块：`src/icache_2way.v`
- 集成分析脚本：`scripts/analyze.py`
- 小型汇编器：`scripts/rvasm.py`
- 新增专项 testbench：
  - `src/tb_loaduse.v`
  - `src/tb_branchpredict.v`
  - `src/tb_cache.v`
  - `src/tb_muldiv.v`
  - `src/tb_float.v`
  - `src/tb_custom.v`
  - `src/tb_csr.v`
  - `src/tb_demo.v`
  - `src/tb_cnn.v`
  - `src/tb_shell.v`

### 未实现或部分实现

- 未使用 SDRAM，当前只使用片上 ROM/RAM
- 未实现完整异常、中断和特权架构
- 未实现 MMU / 虚拟内存
- 未实现完整 RV32F；当前只实现面向推理演示的 custom float32 `FADD32/FMUL32/FGT32`
- 当前顶层仍使用直接映射 I-Cache；2 路组相联 cache 主要用于仿真对比
- PPA 多方案对比需要在 Windows / ISE 14.7 综合后填写真实面积、时序和功耗数据

## 目录结构

```text
src/
  cpu_core.v              单周期 RV32I 子集 CPU
  riscv_pipeline_core.v   五级流水线 CPU
  icache_direct_mapped.v  直接映射 I-Cache
  icache_2way.v           2 路组相联 I-Cache 对比模块
  top.v                   FPGA 顶层
  top.ucf                 TEC-PLUS 核心板引脚约束
  uart_rx.v / uart_tx.v   UART 收发
  cnn_prog.vh             由 asm/cnn_digit.s 生成的指令 ROM 初始化
  tb_cpu_core.v           单周期 CPU 仿真
  tb_pipeline_core.v      流水线 CPU 仿真
  tb_all_features.v       综合功能演示仿真
  tb_cnn.v                CPU 自主 UART MMIO 数字推理仿真
  tb_shell.v              CPU shell / Pong UART 仿真
  tb_float.v              custom float32 加法/乘法仿真
  tb_*.v                  拓展功能专项仿真

asm/
  cnn_digit.s             CPU 自己运行的 shell / CNN / Pong 程序

scripts/
  serial_shell.py         PC 端串口终端 / 8x8 数字图像发送 / Pong 控制
  train_mnist8.py         MNIST -> 8x8 离线训练并导出 float32 权重
  rvasm.py                RV32I/M + CSR + custom 小型汇编器
  test_rvasm.py           汇编器单元测试
  analyze.py              集成回归和指标展示脚本

data/
  mnist8_model.json       训练后导出的模型元数据和 8x8 演示模板

xilinx.xise              ISE 14.7 工程
```

## 系统结构

```text
TEC-PLUS 50MHz 时钟 / RESET
        |
        v
五级流水线 CPU
        |
        +-- I-Cache -- 片上指令 ROM
        |
        +-- 片上数据 RAM
        |
        +-- MMIO LED / KEY
        |
        +-- MMIO UART -- Python 终端
```

当前 `top.v` 没有使用 SDRAM，也没有实例化 SDRAM 控制器。

## 板端功能

烧录当前 `top.bit` 后，FPGA 板端运行的是一个完整的 RISC-V 小系统：

```text
五级流水线 RISC-V CPU
片上指令 ROM / data RAM
直接映射 I-Cache
UART / LED / KEY MMIO
RV32M 整数乘除法
custom float32: FADD32 / FMUL32 / FGT32
custom bit ops: POPCOUNT / BITREVERSE
MNIST8 float32 数字推理程序
CPU Pong 交互 demo
```

CPU 端程序流程：

```text
1. 复位后进入 CPU shell，显示 cpu> prompt
2. shell 解析 help/status/mem/perf/led/cnn/pong 等命令
3. cnn 命令接收 PC 端发送的 8x8 二值数字图像
4. CPU 从片上 data RAM 读取离线训练得到的 float32 权重和 bias
5. CPU 使用 FADD32/FMUL32/FGT32 完成推理和 argmax
6. pong 命令进入 CPU Pong，小球/挡板/得分状态由 RISC-V 指令计算
7. 所有输出通过 UART_TX MMIO 打印，LED 显示预测值或 Pong 分数低 4 位
```

## MMIO 地址

CPU 通过普通 `LW/SW` 访问外设：

```text
0x000-0xFFF  data RAM，含 8x8 图像、MNIST float32 权重和 bias
0x1000       UART_TX    写低 8 位发送 1 字节
0x1004       UART_RX    读低 8 位接收字节；写任意值清 rx_pending
0x1008       UART_STAT  bit0=rx_pending, bit1=tx_busy
0x100C       LED_OUT    写低 4 位控制 LED
0x1010       KEY_IN     读 KEY1..KEY4，按下为 1
```

## 支持的指令

- 算术逻辑：`ADD`, `SUB`, `ADDI`, `AND`, `OR`, `XOR`, `ANDI`, `ORI`, `XORI`
- 移位比较：`SLL`, `SRL`, `SRA`, `SLT`, `SLTU`, `SLTI`, `SLTIU`
- 访存：`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`
- 跳转分支：`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `JAL`, `JALR`
- 立即数：`LUI`, `AUIPC`
- 乘除法：`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`
- 最小 CSR：`RDCYCLE`, `RDINSTRET`
- 系统停止：`ECALL`, `EBREAK`
- 自定义：`POPCOUNT`, `BITREVERSE`, `FADD32`, `FMUL32`, `FGT32`

## 浮点扩展说明

当前没有实现完整 RISC-V `F` 扩展，而是在 custom-0 opcode 下实现了面向推理任务的轻量浮点指令：

```text
fadd32 rd, rs1, rs2   rd = float32(rs1) + float32(rs2)
fmul32 rd, rs1, rs2   rd = float32(rs1) * float32(rs2)
fgt32  rd, rs1, rs2   rd = float32(rs1) > float32(rs2) ? 1 : 0
```

浮点数以 IEEE-754 single precision 的 32-bit bit pattern 存在普通整数寄存器 `x0-x31` 中，不单独实现 `f0-f31` 浮点寄存器堆。该实现支持 zero、normalized number、符号位和规格化，省略 NaN/Inf/subnormal、舍入模式和异常标志，因此不能等同于完整 RV32F。

## 仿真验证

单周期 CPU：

```bash
iverilog -o cpu_sim src/cpu_core.v src/tb_cpu_core.v
vvp cpu_sim
```

预期结果：

```text
PASS
```

流水线 CPU：

```bash
iverilog -o pipe_sim src/riscv_pipeline_core.v src/tb_pipeline_core.v
vvp pipe_sim
```

预期结果：

```text
PIPELINE PASS
```

顶层语法检查：

```bash
iverilog -tnull src/riscv_pipeline_core.v src/icache_direct_mapped.v \
  src/uart_tx.v src/uart_rx.v src/top.v
```

集成回归和指标展示：

```bash
python scripts/analyze.py
```

当前应看到 10/10 个 testbench 通过，并输出 CPI、分支预测准确率、I-Cache 命中率、RV32M、custom float32、自定义指令、CNN 推理和 shell/Pong 结果。

8x8 数字推理端到端仿真：

```bash
iverilog -I src -o tb_cnn src/top.v src/riscv_pipeline_core.v \
  src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_cnn.v
vvp tb_cnn
```

预期结果为 `CNN ALL-DIGIT PASS (10/10)`。该测试只进入一次 CNN 模式，再用真实 UART bit frame 连续发送 0-9 的十张 8x8 图像，检查每次预测和 LED，最后发送 `q` 返回 shell。

CPU shell / Pong 端到端仿真：

```bash
iverilog -I src -o tb_shell src/top.v src/riscv_pipeline_core.v \
  src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_shell.v
vvp tb_shell
```

预期结果为 `SHELL PASS`。该测试通过真实 UART bit frame 发送 `h/s/m1/p/led a/pong/d/q`，验证 shell、性能计数器读取、LED MMIO 和 Pong 状态更新都在 CPU 端执行。

重新汇编 CNN 程序：

```bash
python scripts/rvasm.py asm/cnn_digit.s --vh src/cnn_prog.vh
```

综合功能演示程序：

```bash
iverilog -o all_features_sim src/riscv_pipeline_core.v src/tb_all_features.v
vvp all_features_sim
```

预期结果为 `ALL FEATURES PASS`。对应汇编说明在 `asm/all_features_riscv.s`，覆盖 RV32I 基础指令、访存、load-use、分支循环、RV32M 乘除法、custom 指令、CSR 读和 ECALL halt。

custom float32 扩展专项测试：

```bash
iverilog -o float_sim src/riscv_pipeline_core.v src/tb_float.v
vvp float_sim
```

预期结果为 `FLOAT PASS`，其中 `1.5 + 2.25 = 3.75`、`1.5 * 2.0 = 3.0` 均以 float32 bit pattern 验证。

## ISE 上板

1. 在 Windows / ISE 14.7 中打开 `xilinx.xise`
2. 确认顶层模块为 `top`
3. 运行 `Synthesize - XST`
4. 运行 `Implement Design`
5. 运行 `Generate Programming File`
6. 使用 iMPACT 下载 `top.bit`

核心板引脚：

```text
CLK    T8
RESET  L3
KEY1   T13
KEY2   R12
KEY3   T12
KEY4   P11
LED1   M14
LED2   M13
LED3   L13
LED4   L12
RXD    D5
TXD    D6
```

## 上板现象

FPGA 上电后，CPU 执行固化在 `top.v` 指令 ROM 中的 shell 程序。串口进入 CPU shell，输入 `cnn` 后，CPU 等待 PC 端发送 64 个像素并完成分类；输入 `pong` 后，CPU 维护 Pong 状态并通过串口输出画面状态。

```text
LED 显示预测数字的低 4 位
```

这些输出来自 CPU 执行 RISC-V 指令后通过 MMIO 读 UART、写 UART/LED，不是固定组合逻辑直接生成。

## UART 交互

串口参数：

```text
115200 baud, 8N1
```

PC 端：

```bash
python -m pip install pyserial
python scripts/serial_shell.py --list
python scripts/serial_shell.py -p COM5
```

打开后会进入 CPU 串口 shell：

```text
RV32 shell
cpu>
```

常用命令：

```text
help 或 h       显示命令列表
status 或 s     打印 CPU/串口状态
mem N / mN      读取 data RAM word 0..3
0 / 1 / 2 / 3   旧版短命令，读取对应 data RAM word
perf 或 p       读取 cycle 计数器
ledX            设置 LED，X 为 0..f
cnn             进入连续 8x8 数字推理，模式内 q 返回 shell
pong            进入自动渲染的 CPU Pong，模式内 q 返回 shell
q               在主 shell 中让板端程序进入 idle
```

输入 `cnn` 后，Python 会循环提示选择 0-9 或图像路径；可连续推理，输入 `q` 才返回 CPU shell。也可以直接启动一次推理：

```bash
python scripts/serial_shell.py -p COM5 --cnn 7
```

也可以发送自己画的 8x8 文本图，`#`/`1` 表示亮点，`.`/`0` 表示暗点：

```bash
python scripts/serial_shell.py -p COM5 --cnn 0 --image image.txt
```

Pong 从交互 shell 进入：

```text
cpu> pong
```

Python 会根据 CPU 输出的状态自动绘制 8x6 球场，不需要额外启动参数。

Pong 控制：

```text
a / d   移动挡板
s 或空格 走一步
n       重新开始
q       退出 Pong，回到 CPU shell
```

如果打开串口后没有看到 `cpu>`，按一次开发板 `RESET`，因为上电时打印的第一屏可能已经在串口打开前丢失。

## 快速演示

重新综合并烧录最新版 bitstream 后：

```bash
python scripts/serial_shell.py --list
python scripts/serial_shell.py -p /dev/cu.usbserial-130 --cnn 7
```

预期串口输出包含：

```text
RV32 shell
cpu> pixels64
pred 7
cpu>
```

也可以进入交互 shell：

```bash
python scripts/serial_shell.py -p /dev/cu.usbserial-130
```

然后输入：

```text
cnn
```

Python 会提示选择 `0-9`，并把 `data/mnist8_model.json` 中的 8x8 演示模板发给 FPGA；输入 `pong` 会进入键盘控制的 Pong。
如果想自己画图，直接编辑仓库根目录的 `image.txt`，然后用 `--image image.txt` 发送。

## 8x8 数字推理说明

数字识别不是 Python 端计算的。Python 只负责生成/发送 8x8 像素，并把 FPGA 串口输出显示出来；真正的 shell、图像接收、float32 推理、argmax 分类和结果输出都在 `asm/cnn_digit.s` 中，由 RISC-V CPU 执行。

模型由 `scripts/train_mnist8.py` 在电脑上离线训练：MNIST 28x28 图像先缩放并二值化为 8x8，再训练一个 `64 -> 10` 的 float32 线性分类器。训练脚本导出：

```text
src/cnn_weights.vh       FPGA data RAM 初始化，包含 weights[10][64] 和 bias[10]
data/mnist8_model.json   Python 端演示模板和训练元数据
```

当前硬件时序友好的非负 float32 权重和偏置，在板端逐位浮点模型上的测试集准确率为 `82.37%`。FPGA 上只运行推理，不进行训练。

开机或复位后，CPU 先进入串口 shell：

```text
RV32 shell
cpu>
```

shell 命令：

```text
h/? s 0-3 mN p ledX cnn pong q
```

输入图像示例，`#` 表示像素 1，`.` 表示像素 0：

```text
........
........
..####..
..####..
....##..
...##...
...##...
...#....
```

CPU 输出：

```text
pred 7
cpu>
```

推理流程：

```text
1. CPU 通过 UART_RX 接收 64 个 ASCII 像素
2. CPU 将图像写入片上 data RAM
3. CPU 从 data RAM 读取离线训练得到的 float32 weights/bias
4. CPU 使用 FMUL32/FADD32 计算 10 个类别分数
5. CPU 使用 FGT32 做 argmax，得到 prediction
6. CPU 通过 UART_TX 输出 prediction，并将预测数字写入 LED_OUT
```

该 demo 覆盖的 CPU/SoC 功能：

```text
UART RX/TX   CPU 通过 MMIO 接收图像、打印预测结果
数据 RAM     保存 8x8 输入图像、float32 weights/bias 和中间分数
LED_OUT      显示预测数字低 4 位
Load/Store   读写像素、权重、bias 和 MMIO 寄存器
FADD32/FMUL32 执行 float32 乘加推理
FGT32        执行 float32 分数比较和 argmax
分支跳转     shell 命令解析、循环、像素跳过、分类决策
I-Cache      推理循环从指令 ROM 取指，经 I-Cache 缓存
```

## CPU Pong 说明

Pong 不是 Python 端模拟的游戏。Python 只发送 `a/d/s/n/q` 按键，并把 CPU 状态行自动渲染成球场；CPU 在 `asm/cnn_digit.s` 中维护小球位置、速度、挡板、得分和 game-over 状态。每次输入后，CPU 输出一行状态：

```text
P bx by pad over score
```

例如 `P 4 2 3 0 0` 表示小球在 `(4,2)`，挡板左端在 `3`，未结束，得分为 `0`。该 demo 主要用于直观看到 UART RX/TX、分支、访存、算术、状态机和 LED MMIO 都由 CPU 指令驱动。

## 报告表述

可以概括为：

> 本设计完成了 RISC-V CPU 的基础实现，并在此基础上扩展为包含片上内存、MMIO UART/LED/KEY、五级流水线、直接映射 I-Cache、load-use 冒险处理、动态分支预测、RV32M 乘除法、custom float32、最小 CSR 和自定义指令的小型可运行计算机系统。系统可通过仿真、LED、CPU shell、CPU 自主 8x8 数字推理和 CPU Pong demo 进行验证；PPA 多方案对比需要结合 ISE 综合报告进一步补充。
