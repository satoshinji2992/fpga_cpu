# RISC-V CPU 课程设计简要说明

## 项目目标

本项目面向 TEC-PLUS / Xilinx Spartan-6 XC6SLX9 FPGA，实现一个可仿真、可综合、可上板运行的 RV32I 子集 CPU 系统。当前工程重点覆盖基础层次与进阶层次：CPU 核心、片上内存、I/O 接口、流水线和简单 I-Cache。

## 已实现内容

### 基础层次

- 实现 RV32I 子集单周期 CPU：`src/cpu_core.v`
- 支持算术逻辑、移位比较、访存、跳转分支、立即数等基本指令
- 提供寄存器堆、ALU、乘法器等基础模块文件
- 提供 testbench：`src/tb_cpu_core.v`
- 可通过 Icarus Verilog 仿真，结果为 `PASS`

### 进阶层次

- 实现五级流水线 CPU：`src/riscv_pipeline_core.v`
- 流水线阶段包括 IF / ID / EX / MEM / WB
- 实现 EX 阶段数据转发
- 实现分支和跳转后的流水线冲刷
- 集成片上指令 ROM 和片上数据 RAM
- 集成 8 行直接映射 I-Cache：`src/icache_direct_mapped.v`
- 集成 LED / KEY / UART 基本 I/O
- 实现 FPGA 端串口 shell：`src/serial_shell.v`
- 实现 Python 串口交互工具：`scripts/serial_shell.py`
- 实现 UART Ping-Pong 小型交互程序
- 可输出理想性能指标：`freq=50MHz CPI=1 T=50MIPS`

## 未实现或部分实现内容

- 未使用 SDRAM，当前只使用片上 ROM/RAM
- 未实现完整 RV32I 特权架构、异常、中断和 CSR
- 未实现完整 load-use 冒险暂停机制
- 未实现分支预测
- I-Cache 没有硬件 hit/miss 计数器，当前版本为节省 FPGA 资源已移除
- 未将乘除法扩展指令接入 CPU 指令通路
- 未实现浮点运算
- 未实现自定义 ISA 扩展
- 未完成多方案 PPA 系统性对比

## 上板系统结构

当前 `top.v` 顶层结构如下：

```text
TEC-PLUS 时钟/复位
        |
        v
五级流水线 CPU
        |
        +-- 指令 I-Cache -- 片上指令 ROM
        |
        +-- 片上数据 RAM
        |
        +-- LED / KEY 验证接口
        |
        +-- UART Shell
```

## 验证方式

### 单周期 CPU 仿真

```bash
iverilog -o cpu_sim src/cpu_core.v src/tb_cpu_core.v
vvp cpu_sim
```

预期结果：

```text
PASS
```

### 流水线 CPU 仿真

```bash
iverilog -o pipe_sim src/riscv_pipeline_core.v src/tb_pipeline_core.v
vvp pipe_sim
```

预期结果：

```text
PIPELINE PASS
```

### 上板验证

- ISE 顶层模块：`top`
- 约束文件：`src/top.ucf`
- 4 个 LED 全亮表示固化 CPU 测试程序通过
- KEY1 至 KEY4 可查看关键内存结果
- UART 可通过 PC 端 Python 工具交互

## 报告表述建议

可以概括为：

> 本设计完成了 RV32I 子集 CPU 的基础实现，并在此基础上扩展为包含片上内存、基本 I/O、五级流水线和直接映射 I-Cache 的小型可运行计算机系统。系统可通过仿真、LED/KEY 和 UART shell 进行验证。拓展层次中的分支预测、完整 Cache 统计、浮点/乘除法扩展和 PPA 多方案对比尚未深入实现。
