# FPGA RISC-V CPU

面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 的 RISC-V CPU 课程设计。工程包含可仿真的基础 CPU、带同步取指前端的五级流水线 CPU、片上 BRAM、I-Cache、LED/KEY、真正由 CPU 访问的 UART MMIO，以及 CPU 自己运行的串口 shell、8x8 手写数字推理和 Pong demo。

## 当前实现

### 基础层次

- RV32I 子集单周期 CPU：`src/cpu_core.v`
- 支持算术逻辑、移位比较、访存、跳转分支、立即数等基本指令
- 仿真 testbench：`src/tb_cpu_core.v`
- 可运行固化测试程序，仿真结果为 `PASS`

### 进阶层次

- 五级执行流水线 + 同步取指前端：`src/riscv_pipeline_core.v`
- 流水线阶段：IF / ID / EX / MEM / WB
- EX 阶段数据转发
- load-use 数据冒险暂停
- 分支/跳转冲刷流水线
- 16 项 2-bit BHT 动态分支预测，可用参数关闭对比 baseline
- 同步片上指令 BRAM ROM 和按字节写入的数据 BRAM
- 8 行 I-Cache：顶层默认 2 路组相联 + LRU，也保留直接映射版本用于对照：`src/icache_2way.v` / `src/icache_direct_mapped.v`
- LED / KEY / UART memory-mapped I/O
- 两片 HY57V2562 x16 并行组成 64 MiB x32 SDRAM，支持初始化、刷新、字节掩码和 wait-state
- UART RX / KEY 机器态外部中断，支持 `mstatus/mie/mtvec/mepc/mcause/mip` 和 `MRET`
- CPU 通过 MMIO 自己读 UART 输入、写 UART 输出
- CPU 自己运行串口 shell、8x8 数字推理、Pong 和 128 KiB SDRAM Paint：`asm/soc_firmware.s`
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
  - `src/tb_interrupt.v`
  - `src/tb_sdram_controller.v`
  - `src/tb_soc_io.v`

### 未实现或部分实现

- 已实现机器态外部中断，但未实现完整异常、嵌套中断和完整特权架构
- 未实现 MMU / 虚拟内存
- 未实现完整 RV32F；当前只实现面向推理演示的 custom float32 `FADD32/FMUL32/FGT32`
- 当前顶层默认使用 2 路组相联 I-Cache + LRU，设置 `USE_2WAY_ICACHE=0` 可切换为直接映射
- R15真板已在50 MHz稳定通过十项开机自检；R16加入浮点两层MLP与表达式计算器，17项Icarus回归全部通过
- 当前发布版本：`2.0.0`（硬件/固件标识R16）
- R16把指令ROM扩展为16 KiB；ISE实现后最短周期19.349 ns（51.682 MHz），LUT 77%、Slice 95%、RAMB16 25%，满足50 MHz；XPower估算总功耗91.30 mW

## 目录结构

```text
src/
  cpu_core.v              单周期 RV32I 子集 CPU
  riscv_pipeline_core.v   五级执行流水线与同步取指控制
  icache_direct_mapped.v  直接映射 I-Cache
  icache_2way.v           2 路组相联 I-Cache 对比模块
  top.v                   FPGA 顶层
  top.ucf                 TEC-PLUS 核心板引脚约束
  uart_rx.v / uart_tx.v   UART 收发
  sdram_controller.v      双 HY57V2562 SDRAM 控制器
  soc_firmware.vh         由 asm/soc_firmware.s 生成的指令 ROM 初始化
  tb_cpu_core.v           单周期 CPU 仿真
  tb_pipeline_core.v      流水线 CPU 仿真
  tb_all_features.v       综合功能演示仿真
  tb_cnn.v                CPU 自主 UART MMIO 数字推理仿真
  tb_shell.v              CPU shell / Pong UART 仿真
  tb_interrupt.v          机器态外部中断仿真
  tb_sdram_controller.v   SDRAM 命令/掩码/刷新仿真
  tb_soc_io.v             UART shell + SDRAM + KEY IRQ 集成仿真
  tb_float.v              custom float32 加法/乘法仿真
  tb_*.v                  拓展功能专项仿真

asm/
  soc_firmware.s          CPU 板端固件：自检 / shell / CNN / Pong / Paint

scripts/
  serial_shell.py         PC 端串口终端 / 8x8 数字图像发送 / Pong 控制
  train_mnist8.py         MNIST -> 8x8 离线训练并导出 float32 权重
  rvasm.py                RV32I/M + CSR + custom 小型汇编器
  test_rvasm.py           汇编器单元测试
  analyze.py              集成回归和指标展示脚本

data/
  mnist8_model.json       训练后导出的模型元数据和 8x8 演示模板

image.txt                 自定义 8x8 数字输入示例
experiment.md            当前进度、验证结果与待办记录
计算机组成原理课程设计报告.docx  课程设计报告（R13，含最新 PPA、消融实验和配图）
xilinx.xise              ISE 14.7 工程
```

## 系统结构

```text
TEC-PLUS 50MHz 输入时钟 / RESET（BUFG 后单一 50MHz SoC 时钟域）
        |
        v
同步取指前端 + 五级执行流水线 CPU
        |
        +-- I-Cache -- 片上指令 ROM
        |
        +-- 片上数据 RAM
        +-- 双 HY57V2562 SDRAM (64 MiB)
        |
        +-- MMIO LED / KEY / IRQ
        |
        +-- MMIO UART -- Python 终端
```

核心板的 U2/SH 与 U3/SL 均为 HY57V2562（4 Banks x 4M x 16 bit）。控制器让两片接收相同命令和地址，分别提供高/低 16 位，形成 64 MiB 的 32-bit 外部存储器。系统按 50 MHz 参数使用 burst length 1、CAS latency 2、auto-precharge 和周期刷新。

## 板端功能

烧录当前 `top.bit` 后，FPGA 板端运行的是一个完整的 RISC-V 小系统：

```text
五级流水线 RISC-V CPU
片上指令 ROM / data RAM
直接映射 I-Cache
UART / LED / KEY MMIO
双 HY57V2562 SDRAM 控制器
UART RX / KEY 机器态外部中断
RV32M 整数乘除法
custom float32: FADD32 / FMUL32 / FGT32
custom bit ops: POPCOUNT / BITREVERSE
MNIST8 float32 数字推理程序
CPU Pong 交互 demo
SDRAM Paint 512x256 交互画布（128 KiB）
```

CPU 端程序流程：

```text
1. 复位后执行 RV32I、分支、片内 RAM、RV32M、float32、自定义指令、CSR、SDRAM 开机自检
2. shell 解析 help/status/irq/sdram/perf/led/cnn/pong/paint 等命令
3. cnn 命令接收 PC 端发送的 8x8 二值数字图像
4. CPU 从片上 data RAM 读取离线训练得到的 float32 权重和 bias
5. CPU 使用 FADD32/FMUL32/FGT32 完成推理和 argmax
6. pong 命令进入 CPU Pong，小球/挡板/得分状态由 RISC-V 指令计算
7. paint 命令清零并读写 SDRAM 中的 512x256 字节画布，串口显示 16x8 视窗
8. 所有输出通过 UART_TX MMIO 打印，LED 显示预测值或 Pong 分数低 4 位
```

指令 ROM 容量为 2048 words（8 KiB）；数据 RAM 仍为 1024 words（4 KiB）。

## MMIO 地址

CPU 通过普通 `LW/SW` 访问外设：

```text
0x000-0xFFF  data RAM，含 8x8 图像、MNIST float32 权重和 bias
0x1000       UART_TX    写低 8 位发送 1 字节
0x1004       UART_RX    读低 8 位接收字节；写任意值清 rx_pending
0x1008       UART_STAT  bit0=rx_pending, bit1=tx_busy
0x100C       LED_OUT    写低 4 位控制 LED
0x1010       KEY_IN     读 KEY1..KEY4，按下为 1
0x1014       IRQ_ENABLE bit0=UART RX，bit1=KEY
0x1018       IRQ_PENDING bit0=UART RX，bit1=KEY；写 1 清除
0x101C       PERF_CYCLE     CPU cycle
0x1020       PERF_INSTRET   退休指令数
0x1024       PERF_BRANCH    条件分支数
0x1028       PERF_FLUSH     流水线 flush 数
0x102C       PERF_STALL     数据相关 stall 数
0x1030       PERF_BP_MISS   分支预测错误数
0x1034       PERF_MDU       乘除法指令数
0x1038       ICACHE_HIT     I-Cache hit 数
0x103C       ICACHE_MISS    I-Cache miss 数
0x1040       SDRAM_STATUS   bit0=初始化完成，高 31 位为 refresh count
0x10000000-0x13FFFFFF  双 HY57V2562 SDRAM，64 MiB
```

## 支持的指令

- 算术逻辑：`ADD`, `SUB`, `ADDI`, `AND`, `OR`, `XOR`, `ANDI`, `ORI`, `XORI`
- 移位比较：`SLL`, `SRL`, `SRA`, `SLT`, `SLTU`, `SLTI`, `SLTIU`
- 访存：`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`
- 跳转分支：`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `JAL`, `JALR`
- 立即数：`LUI`, `AUIPC`
- 乘除法：`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`
- CSR：`RDCYCLE`, `RDINSTRET`, `MSTATUS`, `MIE`, `MTVEC`, `MEPC`, `MCAUSE`, `MIP`
- 中断返回：`MRET`
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
iverilog -tnull src/riscv_pipeline_core.v src/sdram_controller.v \
  src/icache_direct_mapped.v src/icache_2way.v src/uart_tx.v src/uart_rx.v src/top.v
```

集成回归和指标展示：

```bash
python scripts/analyze.py
```

当前应看到 17/17 个 testbench 通过，并输出 CPI、分支预测准确率、I-Cache 命中率、RV32M边界、custom float32、中断、SDRAM、CNN、计算器和 shell/Pong 结果。

8x8 数字推理端到端仿真：

```bash
iverilog -I src -o tb_cnn src/top.v src/sdram_controller.v src/riscv_pipeline_core.v \
  src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_cnn.v
vvp tb_cnn
```

预期结果为 `CNN ALL-DIGIT PASS (10/10)`。该测试只进入一次 CNN 模式，再用真实 UART bit frame 连续发送 0-9 的十张 8x8 图像，检查每次预测和 LED，最后发送 `q` 返回 shell。

CPU shell / Pong 端到端仿真：

```bash
iverilog -I src -o tb_shell src/top.v src/sdram_controller.v src/riscv_pipeline_core.v \
  src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_shell.v
vvp tb_shell
```

预期结果为 `SHELL PASS`。该测试通过真实 UART bit frame 发送 `h/s/m1/p/led a/pong/d/q`，验证 shell、性能计数器读取、LED MMIO 和 Pong 状态更新都在 CPU 端执行。

SDRAM 与中断集成仿真：

```bash
iverilog -I src -o tb_soc_io src/top.v src/sdram_controller.v \
  src/riscv_pipeline_core.v src/icache_direct_mapped.v src/icache_2way.v \
  src/uart_rx.v src/uart_tx.v src/tb_soc_io.v
vvp tb_soc_io
```

预期结果为 `SOC SDRAM/INTERRUPT PASS`。

重新汇编 CNN 程序：

```bash
python scripts/rvasm.py asm/soc_firmware.s --vh src/soc_firmware.vh
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

打开后会进入 CPU 串口 shell。R15 已在50 MHz真板稳定得到 `SELFTEST PASS`；R16功能仿真已通过，烧录后应显示：

```text
SELFTEST PASS
RV32 shell 50M BRAM5 R16
cpu>
```

常用命令：

```text
help 或 h       显示命令列表
status 或 s     打印 CPU/串口状态
irq             打印 UART RX 和 KEY 中断次数
sdram           对外部 SDRAM 写入并读回两组 32-bit 测试数据
mem N / mN      读取固定自检结果 m0..m9（CNN 和游戏不会覆盖）
0 / 1 / 2 / 3   `m0` 到 `m3` 的短命令
perf 或 p       打印全部性能计数器、CPI、吞吐量和命中率
ledX            设置 LED，X 为 0..f
cnn             进入连续 8x8 数字推理，模式内 q 返回 shell
calc            浮点表达式计算器，支持括号、十进制数和 + - * /，单独输入 q 返回
pong            进入定时中断自动推进的 CPU Pong；a/d 移动，n 重开，q 返回（s 可单步）
paint           进入 512x256 SDRAM 画布；wasd 移动，x/空格绘制，c 清空，q 返回
q               在主 shell 中让板端程序进入 idle
```

`sdram` 成功时输出 `SDRAM PASS 64MiB`。按下任一核心板 KEY 后输入 `irq`，`key` 计数应增加；UART 中断只在 Pong 模式启用，普通 shell、CNN 和 Paint 使用轮询输入。KEY 中断同时把计数低 4 位写到 LED。

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
a / d    移动挡板
s 或空格 调试时额外走一步
n        重新开始
q        退出 Pong，回到 CPU shell
```

小球由 4 Hz 定时中断自动推进（每 250 ms 一格）；UART 接收中断缓存控制键，用户不需要连续按 `s`。

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

数字识别不是 Python 端计算的。Python 只负责生成/发送 8x8 像素，并把 FPGA 串口输出显示出来；真正的 shell、图像接收、float32 推理、argmax 分类和结果输出都在 `asm/soc_firmware.s` 中，由 RISC-V CPU 执行。

模型由 `scripts/train_mnist8.py` 在 WSL/PyTorch 中离线训练：MNIST 28x28 图像先缩放并二值化为 8x8，再训练一个 `64 -> 8 -> 10` 的 float32 两层MLP，中间层使用ReLU。训练脚本导出：

```text
src/cnn_weights.vh       FPGA data RAM 初始化，包含 W1/b1/W2/b2
data/mnist8_model.json   Python 端演示模板和训练元数据
```

当前模型在板端逐位一致的 custom-float32 模型上测试集准确率为 `82.84%`，十个串口演示原型为 `10/10`。第一层利用二值输入省略乘法，第二层执行80次 `FMUL32`；FPGA只运行推理，不进行训练。

开机或复位后，CPU 先执行自检，再进入串口 shell。全部通过时应输出：

```text
SELFTEST PASS
RV32 shell 50M BRAM5 R16
cpu>
```

shell 命令：

```text
h ver s m0-m9 irq sdram p ledX cnn calc pong paint q
```

自检通过时四个LED全亮。R15真板已经逐项确认十个结果；R16继续把它们保存在不会被CNN、计算器或游戏覆盖的固定区域：

```text
m0 = 0x000000ff  RV32I 算术/逻辑/移位
m1 = 0x00000037  分支循环求和 1+...+10
m2 = 0x13579bdf  片内 RAM 写入读回
m3 = 0x0000002a  MUL 7*6
m4 = 0x00020001  DIVU/REMU 7/3（商:余数）
m5 = 0x40000000  FADD32 1.0+1.0 = 2.0
m6 = 0x40400000  FMUL32 1.5*2.0 = 3.0，同时检查 FGT32
m7 = 0xff00b3d5  BITREVERSE，同时检查 POPCOUNT=18
m8 = 非零          RDCYCLE/CSR
m9 = 0x5aa5c33c  SDRAM 写入读回
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

Pong 不是 Python 端模拟的游戏。CPU 使用 4 Hz 定时中断自动推进小球，UART 中断接收 `a/d/n/q`，Python 只发送按键并把 CPU 状态行渲染成球场。CPU 在 `asm/soc_firmware.s` 中维护小球位置、速度、挡板、得分和 game-over 状态，每次状态变化后输出一行：

```text
P bx by pad over score
```

例如 `P 4 2 3 0 0` 表示小球在 `(4,2)`，挡板左端在 `3`，未结束，得分为 `0`。该 demo 主要用于直观看到 UART RX/TX、分支、访存、算术、状态机和 LED MMIO 都由 CPU 指令驱动。

## SDRAM Paint 说明

输入 `paint` 后，CPU 会清零 `0x10000000` 开始的 131072 字节，并把它作为 512x256、每像素一字节的画布。XC6SLX9 有 72 KiB Block RAM 和最多约 11.25 KiB 分布式 RAM，理论片内存储总量仍小于这块 128 KiB 画布，因此该程序必须通过 SDRAM wait-state 总线完成清空、像素翻转和 16x8 视窗读取。

CPU 每帧输出定长二进制包 `A5 44 83 <x_lo> <x_hi> <y> <128 cells>`，Python 只负责把它渲染成画面。`W/A/S/D` 移动光标，`X` 或空格翻转像素，`C` 清空画布，`Q` 返回 shell。端到端仿真会检查至少 32768 次 SDRAM 清零写入、128 次视窗读取以及绘制后的完整二进制帧。

`p` 命令同样使用定长二进制包传送 9 个 32 位计数器，避免板端十六进制字符串被中断破坏。`serial_shell.py` 会为 cycle、instret、CPI、吞吐量、分支预测、stall、MDU 和 I-Cache 命中率加上标签并计算派生指标。

## 报告表述

可以概括为：

> 本设计完成了 RISC-V CPU 的基础实现，并在此基础上扩展为包含同步片上 BRAM、MMIO UART/LED/KEY、五级执行流水线、2 路组相联 I-Cache、load-use 冒险处理、动态分支预测、多周期 RV32M、custom float32、最小 CSR、自定义指令、浮点MLP和表达式计算器的小型可运行计算机系统。2.0.0/R16已通过17项RTL回归、ISE综合与时序、XPower分析及50 MHz真板全部功能验收。
