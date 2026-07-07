# RISC-V CPU架构设计指南

> 从处理器架构角度理解RISC-V指令集和扩展模块

## 🏗️ RISC-V指令集架构

### 模块化设计理念

RISC-V采用模块化指令集设计，允许根据需求选择不同的扩展：

```
RV32I (基础整数)
  ├─ RV32M (乘法除法)
  ├─ RV32A (原子操作)
  ├─ RV32F (单精度浮点)
  ├─ RV32D (双精度浮点)
  ├─ RV32C (压缩指令)
  └─ 其他扩展...
```

### 基础指令集 - RV32I

**必须实现的指令**（这是CPU的基础）

#### 1. 整数算术运算
```verilog
// 加法类
ADD  rd, rs1, rs2    // rd = rs1 + rs2
SUB  rd, rs1, rs2    // rd = rs1 - rs2
ADDI rd, rs1, imm    // rd = rs1 + imm

// 逻辑运算
AND  rd, rs1, rs2    // rd = rs1 & rs2
OR   rd, rs1, rs2    // rd = rs1 | rs2
XOR  rd, rs1, rs2    // rd = rs1 ^ rs2
ANDI rd, rs1, imm
ORI  rd, rs1, imm
XORI rd, rs1, imm

// 移位
SLL  rd, rs1, rs2    // 逻辑左移
SRL  rd, rs1, rs2    // 逻辑右移
SRA  rd, rs1, rs2    // 算术右移
SLLI rd, rs1, shamt
SRLI rd, rs1, shamt
SRAI rd, rs1, shamt
```

#### 2. 比较和跳转
```verilog
SLT  rd, rs1, rs2    // rd = (rs1 < rs2) ? 1 : 0  (有符号)
SLTU rd, rs1, rs2    // 无符号比较
SLTI rd, rs1, imm
SLTIU rd, rs1, imm

BEQ  rs1, rs2, offset    // if (rs1 == rs2) branch
BNE  rs1, rs2, offset    // if (rs1 != rs2) branch
BLT  rs1, rs2, offset    // if (rs1 <  rs2) branch
BGE  rs1, rs2, offset    // if (rs1 >= rs2) branch
BLTU rs1, rs2, offset    // 无符号比较跳转
BGEU rs1, rs2, offset
```

#### 3. 访存指令
```verilog
LB   rd, offset(rs1)  // 加载字节
LH   rd, offset(rs1)  // 加载半字
LW   rd, offset(rs1)  // 加载字
LBU  rd, offset(rs1)  // 加载字节(无符号)
LHU  rd, offset(rs1)

SB   rs2, offset(rs1) // 存储字节
SH   rs2, offset(rs1) // 存储半字
SW   rs2, offset(rs1) // 存储字
```

#### 4. 跳转指令
```verilog
JAL   rd, offset      // rd = PC+4, PC = PC + offset
JALR  rd, rs1, imm    // rd = PC+4, PC = rs1 + imm
```

#### 5. 特权指令 (CSR)
```verilog
CSRRW rd, csr, rs1    // atomic: rd = csr, csr = rs1
CSRRS rd, csr, rs1    // atomic: rd = csr, csr = csr | rs1
CSRRC rd, csr, rs1    // atomic: rd = csr, csr = csr & ~rs1
CSRRWI rd, csr, imm
CSRRSI rd, csr, imm
CSRRCI rd, csr, imm
```

### 扩展M - 乘法除法

**硬件实现成本：高**

```verilog
// 乘法
MUL   rd, rs1, rs2    // rd = rs1 * rs2 (低32位)
MULH  rd, rs1, rs2    // rd = (rs1 * rs2) >> 32 (有符号)
MULHU rd, rs1, rs2    // rd = (rs1 * rs2) >> 32 (无符号)
MULHSU rd, rs1, rs2   // 有符号 × 无符号

// 除法
DIV   rd, rs1, rs2    // rd = rs1 / rs2 (有符号)
DIVU  rd, rs1, rs2    // 无符号除法
REM   rd, rs1, rs2    // rd = rs1 % rs2 (有符号)
REMU  rd, rs1, rs2    // 无符号取余
```

**硬件实现考虑：**
- 乘法器资源消耗：约1000-2000 LUT
- 除法器资源消耗：约2000-4000 LUT
- 流水线深度：乘法通常2-4周期，除法10-30周期

### 扩展A - 原子操作

**用于多核同步**

```verilog
// LR/SC (Load-Reserved / Store-Conditional)
LR.W   rd, (rs1)          // 加载保留
SC.W   rd, rs2, (rs1)     // 条件存储

// AMO (Atomic Memory Operations)
AMOSWAP.W rd, rs2, (rs1)  // 原子交换
AMOADD.W  rd, rs2, (rs1)  // 原子加
AMOXOR.W  rd, rs2, (rs1)  // 原子异或
AMOAND.W  rd, rs2, (rs1)  // 原子与
AMOOR.W   rd, rs2, (rs1)  // 原子或
AMOMIN.W  rd, rs2, (rs1)  // 原子最小值
AMOMAX.W  rd, rs2, (rs1)  // 原子最大值
```

**硬件实现：**
- 需要缓存一致性协议
- 通常用于多核系统
- 单核可以简化或不实现

### 扩展F/D - 浮点运算

**RV32F (单精度)**
```verilog
FLW    ft, offset(rs1)       // 加载浮点数
FSW    ft2, offset(rs1)      // 存储浮点数
FMADD.S fd, fs1, fs2, fs3    // fd = fs1 * fs2 + fs3
FMSUB.S fd, fs1, fs2, fs3    // fd = fs1 * fs2 - fs3
FNMSUB.S fd, fs1, fs2, fs3   // fd = -fs1 * fs2 + fs3
FNMADD.S fd, fs1, fs2, fs3   // fd = -fs1 * fs2 - fs3
FADD.S  fd, fs1, fs2
FSUB.S  fd, fs1, fs2
FMUL.S  fd, fs1, fs2
FDIV.S  fd, fs1, fs2
FSQRT.S fd, fs1
FMIN.S  fd, fs1, fs2
FMAX.S  fd, fs1, fs2
FCVT.S  ...
```

**RV32D (双精度)** - 类似指令，操作64位浮点数

**硬件资源：**
- 单精度FPU：约2000-4000 LUT
- 双精度FPU：约4000-8000 LUT

### 扩展C - 压缩指令

**16位指令，节省代码空间**

```verilog
C.ADD   rd, rs2    // 等价于 ADD rd, rd, rs2
C.LW    rd, offset(rs1)
C.SW    rs2, offset(rs1)
C.J     offset     // 无条件跳转
C.BEQZ  rs1, offset
C.BNEZ  rs1, offset
...
```

## 🎯 CPU实现阶段

### 阶段1: RV32I核心（最简实现）

**目标：** 实现基础整数指令集

**必需模块：**
```verilog
module riscv_core (
    input  wire        clk,
    input  wire        rst,
    // 指令接口
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_data,
    // 数据接口
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    input  wire [31:0] data_rdata,
    output wire        data_we
);

    // 程序计数器
    reg [31:0] pc;

    // 指令译码
    wire [6:0] opcode = instr_data[6:0];
    wire [4:0] rd     = instr_data[11:7];
    wire [4:0] rs1    = instr_data[19:15];
    wire [4:0] rs2    = instr_data[24:20];
    wire [2:0] funct3 = instr_data[14:12];

    // 寄存器堆
    reg [31:0] regfile [0:31];

    // ALU
    wire [31:0] alu_result;
    wire        alu_zero;

    // TODO: 实现取指、译码、执行逻辑

endmodule
```

**RV32I资源估算（Spartan-6 XC6SLX9）：**
- LUT: 约1500-2000
- FF: 约500-800
- BRAM: 用于指令缓存（可选）

### 阶段2: 添加M扩展

**乘法器实现：**
```verilog
// 简单乘法器（组合逻辑，延迟大）
module multiplier (
    input  [31:0] a,
    input  [31:0] b,
    output [63:0] product
);
    assign product = a * b;  // 使用综合器的乘法器
endmodule

// 或者流水线乘法器（多周期）
module pipelined_multiplier (
    input  wire        clk,
    input  wire        rst,
    input  wire        valid_in,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg         valid_out,
    output reg  [63:0] product
);
    // 3级流水线实现
    // TODO
endmodule
```

**除法器实现：**
```verilog
// 恢复余数除法器（多周期）
module divider (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  [31:0] dividend,
    input  [31:0] divisor,
    output reg         ready,
    output reg [31:0] quotient,
    output reg [31:0] remainder
);
    // 状态机实现
    // TODO
endmodule
```

### 阶段3: 添加特权支持

**CSR寄存器：**
```verilog
module csr_file (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] csr_addr,
    input  wire        csr_write,
    input  wire        csr_read,
    input  wire [31:0] csr_wdata,
    output reg  [31:0] csr_rdata
);
    // mstatus, mtvec, mepc, mcause等
    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;
    // ...
endmodule
```

### 阶段4: 添加中断和异常

```verilog
module exception_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire        timer_irq,
    input  wire        software_irq,
    input  wire        external_irq,
    input  wire        illegal_instr,
    input  wire        misaligned_fetch,
    input  wire        misaligned_access,
    output reg         trap,
    output reg  [31:0] trap_vector
);
    // 中断优先级和异常处理
endmodule
```

## 📊 指令实现优先级

### 第1批：RV32I基础（必需）
| 类别 | 指令 | 复杂度 |
|------|------|--------|
| ALU | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA + 立即数版本 | 低 |
| 分支 | BEQ, BNE, BLT, BGE | 低 |
| 跳转 | JAL, JALR | 低 |
| 访存 | LB, LH, LW, SB, SH, SW | 中 |
| 比较 | SLT, SLTU + 立即数版本 | 低 |

### 第2批：M扩展（推荐）
| 类别 | 指令 | 复杂度 |
|------|------|--------|
| 乘法 | MUL, MULH, MULHU, MULHSU | 中 |
| 除法 | DIV, DIVU, REM, REMU | 高 |

### 第3批：特权支持（运行OS必需）
| 类别 | 指令 | 复杂度 |
|------|------|--------|
| CSR | CSRRW, CSRRS, CSRRC + 立即数版本 | 中 |
| 特权 | MRET, SRET, ECALL, EBREAK | 低 |
| 中断 | 定时器、软件、外部中断 | 高 |

### 第4批：其他扩展（可选）
| 扩展 | 资源消耗 | 优先级 |
|------|----------|--------|
| C (压缩) | 低（译码逻辑） | 中 |
| A (原子) | 中（需缓存一致性） | 低（单核） |
| F (浮点) | 高（FPU） | 低 |
| D (双精度) | 很高 | 低 |

## 🔧 实现建议

### 对于Spartan-6 XC6SLX9：

1. **最小配置：** RV32I + CSR
   - 可以运行C代码
   - 资源：约2000 LUT
   - 适合裸机程序

2. **推荐配置：** RV32I + M + CSR
   - 更好的性能
   - 资源：约3000-4000 LUT
   - 可以运行简单RTOS

3. **完整配置：** RV32I + M + C + CSR
   - 较好的代码密度
   - 资源：约4000 LUT
   - 可以考虑运行Linux

## 📖 学习路径调整

### 第1-2周：RV32I基础指令
- 理解指令格式
- 实现简单ALU
- 实现寄存器堆

### 第3-4周：完成RV32I
- 添加访存单元
- 添加分支跳转
- 整合为简单处理器

### 第5-6周：M扩展
- 实现乘法器
- 实现除法器
- 性能优化

### 第7-8周：特权支持
- CSR寄存器
- 中断处理
- 异常处理

### 第9周+：操作系统准备
- MMU（如果需要）
- 缓存
- 多核（如果需要）

## 🎯 立即开始

建议从分析现有实现开始：

1. **PicoRV32** (最简)
   - 只实现RV32I
   - 约600 LUT
   - 代码简洁易懂

2. **VexRiscv** (灵活)
   - 可配置扩展
   - 性能优秀
   - 文档完善

3. **自研实现**
   - 从单周期开始
   - 逐步添加功能
   - 深入理解每个模块
