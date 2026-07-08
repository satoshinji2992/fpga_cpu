# FPGA RISC-V CPU

面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 的 RISC-V CPU 课程设计。工程包含可仿真的基础 CPU、可上板的五级流水线 CPU、片上内存、I-Cache、LED/KEY、真正由 CPU 访问的 UART MMIO，以及一个 CPU 自己运行的交互式地牢游戏。

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
- CPU 自己运行回合制地牢游戏：`asm/dungeon.s`
- Python 串口终端：`scripts/serial_shell.py`
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
- 小型汇编器：`scripts/rvasm.py`
- 新增专项 testbench：
  - `src/tb_loaduse.v`
  - `src/tb_branchpredict.v`
  - `src/tb_cache.v`
  - `src/tb_muldiv.v`
  - `src/tb_custom.v`
  - `src/tb_csr.v`
  - `src/tb_demo.v`
  - `src/tb_dungeon.v`

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
  dungeon_prog.vh         由 asm/dungeon.s 生成的指令 ROM 初始化
  tb_cpu_core.v           单周期 CPU 仿真
  tb_pipeline_core.v      流水线 CPU 仿真
  tb_all_features.v       综合功能演示仿真
  tb_dungeon.v            CPU 自主 UART MMIO 地牢游戏仿真
  tb_*.v                  拓展功能专项仿真

asm/
  dungeon.s               CPU 自己运行的交互式地牢游戏

scripts/
  serial_shell.py         PC 端串口终端 / WASD 控制
  rvasm.py                RV32I/M + CSR + custom 小型汇编器
  test_rvasm.py           汇编器单元测试
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
        +-- MMIO LED / KEY
        |
        +-- MMIO UART -- Python 终端
```

当前 `top.v` 没有使用 SDRAM，也没有实例化 SDRAM 控制器。

## MMIO 地址

CPU 通过普通 `LW/SW` 访问外设：

```text
0x000-0x3FF  data RAM
0x400        UART_TX    写低 8 位发送 1 字节
0x404        UART_RX    读低 8 位接收字节；写任意值清 rx_pending
0x408        UART_STAT  bit0=rx_pending, bit1=tx_busy
0x40C        LED_OUT    写低 4 位控制 LED
0x410        KEY_IN     读 KEY1..KEY4，按下为 1
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
  src/uart_tx.v src/uart_rx.v src/top.v
```

集成回归和指标展示：

```bash
python scripts/analyze.py
```

当前应看到 8/8 个 testbench 通过，并输出 CPI、分支预测准确率、I-Cache 命中率、RV32M、自定义指令和 dungeon 结果。

地牢游戏端到端仿真：

```bash
iverilog -I src -o tb_dungeon src/top.v src/riscv_pipeline_core.v \
  src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_dungeon.v
vvp tb_dungeon
```

预期结果为 `DUNGEON PASS`。该测试用真实 UART bit frame 向 FPGA 输入 `W/A/S/D`，并捕获 CPU 通过 UART MMIO 打印的地图、战斗和胜利文本。

重新汇编地牢程序：

```bash
python scripts/rvasm.py asm/dungeon.s --vh src/dungeon_prog.vh
```

综合功能演示程序：

```bash
iverilog -o all_features_sim src/riscv_pipeline_core.v src/tb_all_features.v
vvp all_features_sim
```

预期结果为 `ALL FEATURES PASS`。对应汇编说明在 `asm/all_features_riscv.s`，覆盖 RV32I 基础指令、访存、load-use、分支循环、RV32M 乘除法、custom 指令、CSR 读和 ECALL halt。当前 CPU 不支持浮点指令。

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

FPGA 上电后，CPU 执行固化在 `top.v` 指令 ROM 中的地牢游戏程序。串口会打印地图，玩家用 `W/A/S/D` 移动，撞到怪物后 CPU 自己执行战斗逻辑。

```text
LED 显示玩家 HP 档位
```

这些输出来自 CPU 执行 RISC-V 指令后通过 MMIO 写 UART/LED，不是固定组合逻辑直接生成。

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
cpu> dungeon
```

输入 `dungeon` 后进入游戏控制模式：

```text
W/A/S/D  移动
Q        退出游戏并回到 CPU shell
```

如果打开串口后没有看到 `cpu>`，按一次开发板 `RESET`，因为上电时打印的第一屏可能已经在串口打开前丢失。

也可以直接启动游戏：

```bash
python scripts/serial_shell.py -p COM5 --dungeon
```

## 报告表述

可以概括为：

> 本设计完成了 RISC-V CPU 的基础实现，并在此基础上扩展为包含片上内存、MMIO UART/LED/KEY、五级流水线、直接映射 I-Cache、load-use 冒险处理、动态分支预测、RV32M 乘除法、最小 CSR 和自定义指令的小型可运行计算机系统。系统可通过仿真、LED 和 CPU 自主串口地牢游戏进行验证；PPA 多方案对比需要结合 ISE 综合报告进一步补充。
