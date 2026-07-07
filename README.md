# FPGA RISC-V CPU

面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 的 RV32I 子集 CPU 课程设计。工程包含可仿真的基础 CPU、可上板的五级流水线 CPU、片上内存、I-Cache、LED/KEY 验证接口和 UART 交互程序。

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
- 分支/跳转冲刷流水线
- 片上指令 ROM 和片上数据 RAM
- 8 行直接映射 I-Cache：`src/icache_direct_mapped.v`
- LED / KEY / UART 基本 I/O
- FPGA 端串口 shell：`src/serial_shell.v`
- Python 串口工具：`scripts/serial_shell.py`
- UART Ping-Pong 小型交互程序

### 未实现或部分实现

- 未使用 SDRAM，当前只使用片上 ROM/RAM
- 未实现异常、中断、CSR 和特权架构
- 未实现完整 load-use 冒险暂停机制
- 未实现分支预测
- I-Cache 没有硬件 hit/miss 计数器，当前版本为节省资源已移除
- `src/multiplier.v` 未接入 CPU 指令通路，因此不算支持乘法指令
- 未实现除法、浮点、自定义 ISA 扩展和多方案 PPA 对比

## 目录结构

```text
src/
  cpu_core.v              单周期 RV32I 子集 CPU
  riscv_pipeline_core.v   五级流水线 CPU
  icache_direct_mapped.v  直接映射 I-Cache
  top.v                   FPGA 顶层
  top.ucf                 TEC-PLUS 核心板引脚约束
  uart_rx.v / uart_tx.v   UART 收发
  serial_shell.v          FPGA 端串口 shell
  tb_cpu_core.v           单周期 CPU 仿真
  tb_pipeline_core.v      流水线 CPU 仿真

scripts/
  serial_shell.py         PC 端串口交互工具

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
        +-- LED / KEY
        |
        +-- UART Shell -- Python PC 工具
```

当前 `top.v` 没有使用 SDRAM，也没有实例化 SDRAM 控制器。

## 支持的指令

- 算术逻辑：`ADD`, `SUB`, `ADDI`, `AND`, `OR`, `XOR`, `ANDI`, `ORI`, `XORI`
- 移位比较：`SLL`, `SRL`, `SRA`, `SLT`, `SLTU`, `SLTI`, `SLTIU`
- 访存：`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`
- 跳转分支：`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `JAL`, `JALR`
- 立即数：`LUI`, `AUIPC`

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
  src/uart_tx.v src/uart_rx.v src/serial_shell.v src/top.v
```

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

FPGA 上电后，CPU 执行固化在 `top.v` 指令 ROM 中的测试程序。测试通过时：

```text
4 个 LED 全亮 = PASS
```

按键显示关键内存结果：

```text
KEY1 -> Mem[0][31:28] = 3
KEY2 -> Mem[0][23:20] = 8
KEY3 -> Mem[1][3:0]   = E
KEY4 -> Mem[2][3:0]   = 2
```

这些结果来自 CPU 执行 RISC-V 指令后写入的数据 RAM，不是固定组合逻辑直接生成。

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

常用命令：

```text
h    help
s    status
0    print Mem[0]
1    print Mem[1]
2    print Mem[2]
g    show Pong state
a/d  move paddle and step
x    step ball
n    reset Pong
q    quit Python client
```

Ping-Pong 演示：

```bash
python scripts/serial_shell.py -p COM5 --pong
```

漏接小球后，FPGA 通过串口输出：

```text
freq=50MHz CPI=1 T=50MIPS
```

该性能值是基于 50MHz 时钟和理想流水线 CPI=1 的展示指标，不是硬件实时性能计数器统计值。

## 报告表述

可以概括为：

> 本设计完成了 RV32I 子集 CPU 的基础实现，并在此基础上扩展为包含片上内存、基本 I/O、五级流水线和直接映射 I-Cache 的小型可运行计算机系统。系统可通过仿真、LED/KEY 和 UART shell 进行验证。拓展层次中的分支预测、完整 Cache 统计、浮点/乘除法扩展和 PPA 多方案对比尚未深入实现。
