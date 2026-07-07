# RISC-V 软核学习路径

> 从零开始学习RISC-V处理器设计，最终在FPGA上运行Linux

## 📚 学习路径概览

```
阶段1: RISC-V基础 (1-2周)
   ↓
阶段2: 简单处理器核心 (2-3周)
   ↓
阶段3: 完整处理器实现 (3-4周)
   ↓
阶段4: SoC构建 (4-6周)
   ↓
阶段5: 操作系统移植 (持续学习)
```

---

## 🔰 阶段1: RISC-V基础

### 学习目标
- 理解RISC-V指令集架构
- 掌握基本的汇编语言
- 了解处理器工作原理

### 学习资源

1. **RISC-V官方文档**
   - [RISC-V用户级ISA](https://github.com/riscv/riscv-isa-manual)
   - [RISC-V特权级架构](https://github.com/riscv/riscv-isa-manual)

2. **推荐书籍**
   - 《Digital Design and Computer Architecture》
   - 《Computer Organization and Design RISC-V Edition》

3. **在线工具**
   - [RISC-V汇编器模拟器](https://www.chipverify.com/risc-v-simulator)
   - [编译器浏览器 (Compiler Explorer)](https://godbolt.org/)

### 实践练习
```riscv
# 示例: 简单的RISC-V汇编程序
addi x1, x0, 5      # x1 = 5
addi x2, x0, 10     # x2 = 10
add  x3, x1, x2     # x3 = x1 + x2 = 15
```

---

## 🚀 阶段2: 简单处理器核心

### 学习目标
- 实现一个简单的RISC-V处理器
- 理解流水线的基本概念
- 掌握Verilog硬件描述语言

### 参考实现

1. **PicoRV32** (推荐入门)
   - 项目地址: https://github.com/cliffordwolf/picorv32
   - 特点: 简单小巧，适合学习
   - 资源占用: 约600-800 LUT

2. **自研学习用核心**
   - 从单周期实现开始
   - 逐步添加流水线
   - 只实现RV32I基础指令集

### 实践项目
```verilog
// 示例: 简单的RISC-V处理器框架
module riscv_core (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] instr,
    output reg  [31:0] pc,
    output wire [31:0] alu_result
);
    // 取指、译码、执行逻辑
    // TODO: 实现处理器核心逻辑
endmodule
```

---

## 🔧 阶段3: 完整处理器实现

### 学习目标
- 实现RV32IM指令集
- 添加中断和异常处理
- 实现MMU(如需要)

### 参考项目

1. **VexRiscv** (推荐深入)
   - 项目地址: https://github.com/SpinalHDL/VexRiscv
   - 特点: 用SpinalHDL编写，灵活可配置
   - 支持: RV32IM + Linux

2. **DarkRISC-V** (针对Spartan-6优化)
   - 项目地址: https://github.com/darklife/darkriscv
   - 特点: 专门针对Spartan-6优化
   - 适合: 小型FPGA

### 关键模块
- 指令获取单元
- 指令译码器
- ALU运算单元
- 寄存器堆
- 内存接口
- CSR寄存器

---

## 🏗️ 阶段4: SoC构建

### 学习目标
- 构建完整的片上系统
- 添加总线互联
- 集成各种外设

### SoC架构
```
┌─────────────────────────────────────────┐
│              RISC-V CPU                 │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┴─────────┐
        │    Interconnect   │ (Wishbone/Axi)
        └─────────┬─────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───┴───┐    ┌───┴───┐    ┌───┴───┐
│ BRAM  │    │ SDRAM │    │ UART  │
└───────┘    └───────┘    └───────┘
```

### 参考框架

1. **LiteX** (推荐)
   - 自动化SoC生成
   - 丰富的外设库
   - 项目地址: https://github.com/enjoy-digital/litex

2. **自研SoC**
   - 从简单开始
   - 逐步添加功能

### 必需组件
1. **CPU**: RISC-V核心
2. **总线**: Wishbone或AXI
3. **内存**:
   - 片上BRAM (用于BIOS)
   - 外部SDRAM (主内存)
4. **外设**:
   - UART (控制台)
   - GPIO (LED/按键)
   - 定时器

---

## 🐧 阶段5: 操作系统移植

### 学习目标
- 移植RTOS
- 尝试运行Linux
- 理解boot流程

### 实践步骤

1. **裸机程序** (Hello World)
2. **RTOS移植** (FreeRTOS)
3. **Linux移植**
   - U-Boot
   - Linux内核
   - RootFS

### 参考项目
- linux-on-litex-vexriscv
- riscv-linux

---

## 🛠️ 推荐工具链

### 硬件开发
- **仿真**: Verilator, GTKWave
- **综合**: Xilinx ISE 14.7
- **调试**: OpenOCD + GDB

### 软件开发
- **编译器**: RISC-V GCC
- **调试器**: GDB
- **构建系统**: Make, CMake

---

## 📖 推荐学习顺序

### 第1-2周: RISC-V基础
- [ ] 学习RISC-V汇编
- [ ] 使用模拟器运行程序
- [ ] 理解计算机体系结构基础

### 第3-4周: Verilog基础
- [ ] 学习Verilog语法
- [ ] 实现简单的组合/时序逻辑
- [ ] 仿真验证

### 第5-7周: 简单处理器
- [ ] 研究PicoRV32
- [ ] 实现基础指令集
- [ ] 仿真测试

### 第8-11周: 完整处理器
- [ ] 研究VexRiscv
- [ ] 添加更多指令
- [ ] 流水线优化

### 第12-17周: SoC构建
- [ ] 设计总线架构
- [ ] 添加内存控制器
- [ ] 集成UART等外设

### 第18周+: 操作系统
- [ ] 运行裸机程序
- [ ] 移植FreeRTOS
- [ ] 尝试Linux

---

## 🎯 立即开始

### 今天可以做的事
1. 访问 https://godbolt.org/ 选择RISC-V编译器
2. 写一段简单的RISC-V汇编程序
3. 在模拟器中运行它

### 下一步
选择一个参考项目开始学习：
- **快速入门**: 研究PicoRV32源码
- **深入学习**: 研究VexRiscv
- **实用导向**: 直接使用LiteX生成SoC

---

## 📞 获取帮助

- RISC-V国际论坛
- GitHub讨论区
- FPGA相关论坛
- Hackaday FPGA社区

祝学习顺利！🚀
