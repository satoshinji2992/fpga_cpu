# 仿真测试指南

## 方法1: 使用ISE ISim仿真器

### 步骤：

1. **打开ISE项目**
   ```
   打开 xilinx.xise
   ```

2. **添加测试文件到项目**
   - 在Design面板中，右键点击项目
   - 选择"Add Source"
   - 选择 `src/tb_cpu_core.v`
   - 确保设置为"Simulation"源

3. **设置仿真顶层**
   - 在Design面板中，选择"Simulation"视图
   - 将"tb_cpu_core"设置为顶层模块

4. **运行仿真**
   - 在Processes面板中，展开"ISim Simulator"
   - 双击"Simulate Behavioral Model"
   - ISim窗口将打开

5. **查看波形**
   - 在ISim中，选择要查看的信号：
     - clk, rst_n
     - instr_addr, instr_data
     - pc_reg (在u_cpu中)
     - alu_result
     - halt
   - 运行仿真足够时间（1000ns）

### 预期结果：

测试程序执行：
```
[0] ADDI x1, x0, 10  → x1 = 10
[1] ADDI x2, x0, 20  → x2 = 20
[2] ADD  x3, x1, x2  → x3 = 30
[3] SUB  x4, x2, x1  → x4 = 10
[4] JAL  x0, 0       → halt
```

应该在约5-6个周期后halt信号变为高电平。

---

## 方法2: 使用iverilog（如果可用）

### 安装：

**Windows:**
```bash
# 使用 chocolatey
choco install icarus-verilog

# 或从官网下载
# https://github.com/steveicarus/iverilog/releases
```

**Linux:**
```bash
sudo apt install iverilog gtkwave
```

### 运行仿真：

```bash
cd c:/code/fpga/xilinx

# 编译
iverilog -o cpu_sim src/cpu_core.v src/alu.v src/regfile.v src/tb_cpu_core.v

# 运行
vvp cpu_sim

# 查看波形
gtkwave cpu_core.vcd
```

---

## 方法3: 使用Verilator

### 安装：

```bash
# Windows (WSL)
sudo apt install verilator

# 或从源码编译
# https://veripool.org/verilator/
```

### 运行：

```bash
cd c:/code/fpga/xilinx

# 编译
verilator --cc src/cpu_core.v src/alu.v src/regfile.v --exe src/tb_cpu_core.v

# 运行
cd obj_dir
./Vcpu_core
```

---

## 调试信号说明

### 关键信号：

| 信号 | 描述 | 预期值 |
|------|------|--------|
| clk | 时钟 | 100MHz周期 |
| rst_n | 复位（低有效） | 0→1后开始 |
| instr_addr | 指令地址 | 0, 4, 8, 12, 16... |
| instr_data | 指令数据 | 从存储器读取 |
| pc_reg | 程序计数器 | 跟随instr_addr |
| alu_result | ALU结果 | 运算结果 |
| halt | 停机信号 | 执行完成后变高 |

### 寄存器值验证：

由于CPU内部寄存器不能直接观察，需要：
1. 添加调试输出到CPU
2. 在波形中观察rd_data（写回数据）
3. 修改测试程序将结果写入存储器

---

## 常见问题

### Q: ISim找不到信号
A: 确保在仿真窗口中展开了层次结构，信号在u_cpu实例下

### Q: 仿真一直运行不停止
A: 检查halt信号的实现和PC跳转逻辑

### Q: 没有iverilog
A: 使用ISE自带的ISim仿真器

### Q: 波形查看器不可用
A: ISim有内置波形查看功能，不需要额外工具

---

## 当前测试状态

- [ ] 寄存器堆时序：已修复 ✅
- [ ] 算术指令：待验证
- [ ] 访存指令：待验证
- [ ] 跳转指令：待验证
