# RISC-V CPU模块文档

## 模块架构图

```
┌────────────────────────────────────────────────────────────┐
│                     riscv_core (cpu_core.v)                 │
│                   单周期RISC-V处理器核心                     │
└──────────────┬──────────────────────────────────┬───────────┘
               │                                  │
       ┌───────┴──────┐                  ┌───────┴────────┐
       │   取指单元    │                  │    译码单元     │
       │ (PC生成器)    │                  │  (指令译码)    │
       └──────────────┘                  └───────┬────────┘
                                                 │
                  ┌──────────────────────────────┼──────────┐
                  │                              │          │
          ┌───────┴────────┐          ┌─────────┴──┐  ┌─────┴─────┐
          │   控制单元      │          │  ALU单元   │  │  寄存器堆   │
          │ (控制信号生成)   │          │  (alu.v)   │  │(regfile.v) │
          └────────────────┘          └────────────┘  └───────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───┴───┐    ┌───┴───┐    ┌───┴────┐
│乘法器  │    │除法器  │    │ CSR单元 │
│(可选)  │    │(可选)  │    │ (特权级) │
└───────┘    └───────┘    └─────────┘
```

## 模块说明

### 1. cpu_core.v - 主CPU核心

**功能：**
- 单周期RISC-V处理器
- RV32I基础指令集
- 程序计数器和跳转控制

**参数：**
- `PC_INIT`: PC初始值

**接口：**
```verilog
input  wire        clk, rst_n              // 时钟和复位
output wire [31:0] instr_addr             // 指令地址
input  wire [31:0] instr_data             // 指令数据
output wire [31:0] data_addr              // 数据地址
output wire [31:0] data_wdata             // 写数据
output wire        data_we                // 写使能
output wire        halt                   // 停机信号
```

**支持指令：**
- RV32I基础指令集（除CSR外）
- 不支持M/A/F/D/C扩展（可添加）

**资源估算：**
- LUT: 1500-2000
- FF: 500-800

---

### 2. alu.v - 算术逻辑单元

**功能：**
- 整数算术运算
- 逻辑运算
- 移位操作
- 比较运算

**操作码：**
| 操作码 | 指令 | 描述 |
|--------|------|------|
| 0 | ADD | 加法 |
| 1 | SUB | 减法 |
| 2 | SLL | 逻辑左移 |
| 3 | SRL | 逻辑右移 |
| 4 | SRA | 算术右移 |
| 5 | AND | 与运算 |
| 6 | OR | 或运算 |
| 7 | XOR | 异或运算 |
| 8 | SLT | 有符号比较 |
| 9 | SLTU | 无符号比较 |
| 10 | EQ | 等于比较 |
| 11 | NE | 不等于比较 |
| 12 | GE | 大于等于比较 |
| 13 | GEU | 无符号大于等于比较 |

---

### 3. regfile.v - 寄存器堆

**功能：**
- 32个32位通用寄存器
- 双读端口，单写端口
- x0寄存器硬编码为0

**接口：**
```verilog
input  wire        clk, we     // 写使能
input  wire [4:0]  ra1, ra2    // 读地址
input  wire [4:0]  wa          // 写地址
input  wire [31:0] wd         // 写数据
output wire [31:0] rd1, rd2    // 读数据
```

**特点：**
- 异步读取（组合逻辑）
- 同步写入（时钟沿有效）
- 写x0无效（保持为0）

---

### 4. multiplier.v - 乘法器（M扩展）

**功能：**
- 32位乘法运算
- 支持有符号/无符号乘法
- 返回高32位或低32位

**操作类型：**
| 操作 | 描述 | 返回值 |
|------|------|--------|
| MUL | 有符号×有符号 | 低32位 |
| MULH | 有符号×有符号 | 高32位 |
| MULHU | 无符号×无符号 | 高32位 |
| MULHSU | 有符号×无符号 | 高32位 |

**资源估算：**
- LUT: 500-1000
- 延迟: 1-3周期

---

### 5. tb_cpu_core.v - 测试平台

**功能：**
- CPU核心仿真验证
- 简单测试程序
- 波形输出

**测试程序：**
```riscv
ADDI x1, x0, 10  # x1 = 10
ADDI x2, x0, 20  # x2 = 20ADD  x3, x1, x2  # x3 = 30
SUB  x4, x2, x1  # x4 = 10JAL  x0, 0       # halt
```

---

## 使用流程

### 1. 仿真测试

使用ModelSim或iverilog：

```bash
# 使用iverilog编译
iverilog -o cpu_sim cpu_core.v alu.v regfile.v tb_cpu_core.v

# 运行仿真
vvp cpu_sim

# 查看波形
gtkwave cpu_core.vcd
```

### 2. ISE综合

1. 打开ISE
2. 运行TCL脚本：`source update_ise_project.tcl`
3. 或手动添加源文件
4. 运行综合
5. 查看资源使用报告

### 3. FPGA测试

创建顶层模块，连接：
- CPU核心
- 存储器（BRAM或外部SRAM/SDRAM）
- UART（用于调试输出）
- LED（状态指示）

---

## 扩展指南

### 添加M扩展

1. 将`multiplier.v`添加到项目
2. 在CPU中添加乘法指令译码
3. 连接乘法器到执行单元

### 添加CSR支持

创建CSR模块：
```verilog
module csr_file (
    input  wire        clk,
    input  wire [11:0] csr_addr,    // CSR地址
    input  wire        csr_write,   // 写使能    input  wire [31:0] csr_wdata,   // 写数据
    output reg  [31:0] csr_rdata    // 读数据
);
    // mstatus, mtvec, mepc, mcause...
endmodule
```

### 添加中断支持

创建中断控制器：
```verilogmodule interrupt_controller (
    input  wire        timer_irq,    // 定时器中断
    input  wire        software_irq, // 软件中断
    input  wire        external_irq, // 外部中断
    output reg         trap,         // 陷阱信号
    output reg  [31:0] trap_vector   // 陷阱向量
);
endmodule
```

---

## 调试技巧

### 添加内部观察

在CPU中添加调试输出：
```verilog`ifdef DEBUG
    always @(posedge clk) begin        if (instr_valid && !halt) begin            $display("PC: %08h, Instr: %08h", pc_reg, instr);        end    end
`endif```

### 波形分析

关注的关键信号：
- `pc_reg`: 程序计数器
- `instr`: 当前指令
- `alu_result`: ALU结果
- `rd_data`: 写回数据
- `halt`: 停机信号

### 常见问题

1. **PC不变**: 检查复位信号
2. **指令错误**: 检查存储器对齐
3. **ALU结果异常**: 检查操作码译码
4. **无限循环**: 检查跳转地址计算

---

## 资源使用参考

| 配置 | LUT | FF | BRAM | 说明 |
|------|-----|----|----|------|
| RV32I基础 | 1500 | 500 | 0 | 最小配置 |
| +M扩展 | 2500 | 800 | 0 | 添加乘法器 |
| +CSR | 3000 | 1000 | 0 | 添加特权支持 |
| +缓存 | 4000 | 1500 | 4-8 | 添加指令缓存 |
| 完整配置 | 5000+ | 2000+ | 16+ | 可运行简单OS |

**Spartan-6 XC6SLX9资源：**
- 总LUT: 9152
- 总FF: 9152
- 总BRAM: 16 (32KB)

**建议配置：**
- 最小：RV32I基础
- 推荐：RV32I + M + CSR
- 最大：RV32I + M + CSR + 小缓存
