# FPGA RISC-V CPU

基于 Xilinx Spartan-6 XC6SLX9-2FTG256 / TEC-PLUS 核心板的 RV32I 子集单周期 CPU 课程设计。

项目实现了一个可综合、可仿真、可上板运行的简单处理器系统：

- RV32I 子集单周期 CPU
- RV32I 子集五级流水线 CPU
- 直接映射指令 Cache
- 片内指令 ROM 和数据 RAM
- 核心板 LED/KEY 验证接口
- UART 串口交互 shell
- UART Ping-Pong 小型测试程序
- Python PC 端串口工具

## 目录结构

```text
.
├── src/
│   ├── cpu_core.v        # RISC-V CPU核心
│   ├── riscv_pipeline_core.v # 五级流水线CPU核心
│   ├── icache_direct_mapped.v # 直接映射I-Cache
│   ├── top.v             # FPGA顶层: CPU + 内存 + LED/KEY + UART shell
│   ├── top.ucf           # TEC-PLUS核心板引脚约束
│   ├── uart_rx.v         # UART接收
│   ├── uart_tx.v         # UART发送
│   ├── serial_shell.v    # FPGA端串口shell
│   ├── tb_cpu_core.v     # CPU仿真testbench
│   ├── alu.v
│   ├── regfile.v
│   └── multiplier.v
├── scripts/
│   └── serial_shell.py   # PC端串口交互工具
├── doc/                  # 设计与学习文档
├── asm/                  # RISC-V汇编示例
├── reference/            # 课程题目和ISE辅助脚本
├── xilinx.xise           # ISE 14.7工程
└── TASK_STATUS.md
```

## 功能

支持的 RV32I 指令类型包括：

- 算术逻辑: `ADD`, `SUB`, `ADDI`, `AND`, `OR`, `XOR`, `ANDI`, `ORI`, `XORI`
- 移位比较: `SLL`, `SRL`, `SRA`, `SLT`, `SLTU`, `SLTI`, `SLTIU`
- 访存: `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`
- 跳转分支: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `JAL`, `JALR`
- 立即数: `LUI`, `AUIPC`

## 仿真

需要安装 Icarus Verilog。

单周期 CPU 回归：

```bash
iverilog -o cpu_sim src/cpu_core.v src/tb_cpu_core.v
vvp cpu_sim
```

通过时会看到：

```text
Mem[0] = 34801200 (expected 34801200)
Mem[1] = 0000fffe (expected 0000fffe)
Mem[2] = 2 (expected 2)
PASS
```

生成的 `cpu_core.vcd` 可用 GTKWave 查看。

流水线 CPU 回归：

```bash
iverilog -o pipe_sim src/riscv_pipeline_core.v src/tb_pipeline_core.v
vvp pipe_sim
```

通过时会看到：

```text
PIPELINE PASS
```

## ISE 上板

1. 在 Windows / ISE 14.7 中打开 `xilinx.xise`
2. 确认顶层模块是 `top`
3. 运行 `Synthesize - XST`
4. 运行 `Implement Design`
5. 运行 `Generate Programming File`
6. 用 iMPACT 下载生成的 `top.bit`

当前顶层使用五级流水线 CPU 和直接映射 I-Cache，只使用 TEC-PLUS 核心板自带外设：

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

## LED/KEY 验证

FPGA 上电后 CPU 运行固化测试程序。测试通过时：

```text
4 个 LED 全亮 = PASS
```

按键可查看关键结果：

```text
KEY1 -> 显示 Mem[0][31:28] = 3
KEY2 -> 显示 Mem[0][23:20] = 8
KEY3 -> 显示 Mem[1][3:0]   = E
KEY4 -> 显示 Mem[2][3:0]   = 2
```

## 串口 Shell

核心板 CP2102 USB 串口参数：

```text
115200 baud, 8N1
```

PC 端工具：

```bash
python -m pip install pyserial
python scripts/serial_shell.py --list
python scripts/serial_shell.py -p COM5
```

把 `COM5` 换成实际串口号。

支持命令：

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

预期输出：

```text
cpu> s
PASS halt=1
cpu> 0
mem0=0x34801200
cpu> 1
mem1=0x0000FFFE
cpu> 2
mem2=0x00000002
```

Ping-Pong 演示：

```bash
python scripts/serial_shell.py -p COM5 --pong
```

键盘控制：

```text
A/D move paddle
Space step
N reset
G redraw
Q quit
```

漏接小球结束后，FPGA 会通过串口打印进阶层次性能指标：

```text
freq=50MHz
CPI=1.00 ideal pipeline
throughput=50 MIPS ideal
```

## 说明

本项目的 LED 和串口输出不是固定组合逻辑直接生成的，而是来自 CPU 执行 RISC-V 机器指令后写入的数据 RAM。通过更换指令 ROM 内容，同一 CPU 核心可以执行不同程序。

## 进阶层次说明

当前进阶版顶层包含：

- `riscv_pipeline_core.v`: IF/ID/EX/MEM/WB 五级流水线，包含 EX 阶段转发和分支/跳转冲刷。
- `icache_direct_mapped.v`: 8 行直接映射 I-Cache，带 hit/miss 计数器，可用于性能分析。
- `serial_shell.v`: UART I/O shell，可查看 CPU 内存结果并运行轻量 Ping-Pong 演示。

流水线相对单周期版本的可讲指标：

- 理想 CPI 接近 1。
- 分支和跳转在 EX 阶段解析，会冲刷年轻指令，产生控制相关开销。
- I-Cache 命中时直接返回缓存指令；首次访问或冲突时记录 miss 并填充缓存行。
