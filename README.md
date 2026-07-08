# FPGA RISC-V CPU

面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 的 RISC-V CPU 课程设计。工程包含可仿真的基础 CPU、可上板的五级流水线 CPU、片上内存、I-Cache、LED/KEY 验证接口、UART 交互程序和一组拓展功能验证 testbench。

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
- LED / KEY / UART 基本 I/O
- FPGA 端串口 shell：`src/serial_shell.v`
- Python 串口工具：`scripts/serial_shell.py`
- UART Ping-Pong 小型交互程序
- 硬件性能计数器：cycle、instret、branch、flush、load-use stall、branch miss、mdu inst
- 最小 CSR 读取：`RDCYCLE` / `RDINSTRET`
- `ECALL` / `EBREAK` 作为 halt

### 拓展层次

- RV32M 乘除法扩展：`MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU`
- 自定义 custom-0 指令：
  - `POPCOUNT`
  - `BITREVERSE`
- 2 路组相联 I-Cache + LRU 对比模块：`src/icache_2way.v`
- 集成分析脚本：`scripts/analyze.py`
- 新增专项 testbench：
  - `src/tb_loaduse.v`
  - `src/tb_branchpredict.v`
  - `src/tb_cache.v`
  - `src/tb_muldiv.v`
  - `src/tb_custom.v`
  - `src/tb_csr.v`
  - `src/tb_demo.v`

### 未实现或部分实现

- 未使用 SDRAM，当前只使用片上 ROM/RAM
- 未实现完整异常、中断和特权架构
- 未实现 MMU / 虚拟内存
- 未实现浮点运算
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
  serial_shell.v          FPGA 端串口 shell
  tb_cpu_core.v           单周期 CPU 仿真
  tb_pipeline_core.v      流水线 CPU 仿真
  tb_*.v                  拓展功能专项仿真

scripts/
  serial_shell.py         PC 端串口交互工具
  analyze.py              集成回归和指标展示脚本

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
- 乘除法：`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`
- 最小 CSR：`RDCYCLE`, `RDINSTRET`
- 系统停止：`ECALL`, `EBREAK`
- 自定义：`POPCOUNT`, `BITREVERSE`

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

集成回归和指标展示：

```bash
python scripts/analyze.py
```

当前应看到 6/6 个专项 testbench 通过，并输出 CPI、分支预测准确率、I-Cache 命中率、RV32M 和自定义指令结果。

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
KEY1 -> Mem[0][3:0] = A  (MUL 7*6 = 42)
KEY2 -> Mem[1][3:0] = 7  (sum 1+...+10 = 55)
KEY3 -> Mem[2][3:0] = 8  (POPCOUNT 0xFF = 8)
KEY4 -> halt 状态
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

`p` 命令可打印硬件性能计数器：

```text
c=cycle i=instret b=branch f=flush m=bp_miss
```

Ping-Pong 演示：

```bash
python scripts/serial_shell.py -p COM5 --pong
```

漏接小球后，FPGA 通过串口输出：

```text
freq=50MHz CPI=1 T=50MIPS
```

`p` 命令输出的是硬件计数器；Ping-Pong 结束时输出的 `freq=50MHz CPI=1 T=50MIPS` 是基于 50MHz 时钟和理想流水线 CPI=1 的展示指标。

## 报告表述

可以概括为：

> 本设计完成了 RISC-V CPU 的基础实现，并在此基础上扩展为包含片上内存、基本 I/O、五级流水线、直接映射 I-Cache、load-use 冒险处理、动态分支预测、RV32M 乘除法、最小 CSR 和自定义指令的小型可运行计算机系统。系统可通过仿真、LED/KEY 和 UART shell 进行验证；PPA 多方案对比需要结合 ISE 综合报告进一步补充。
