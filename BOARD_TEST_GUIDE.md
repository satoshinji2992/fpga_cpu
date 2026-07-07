# TEC-PLUS 上机验证指南

## 🎯 当前功能

### CPU功能
您的 RISC-V CPU (`cpu_core.v`) 实现了 RV32I 基础指令集：
- ✅ 算术逻辑运算 (ADD, SUB, AND, OR, XOR...)
- ✅ 访存指令 (LW, SW, LB, SB...)
- ✅ 分支跳转 (BEQ, BNE, JAL, JALR...)
- ✅ 比较指令 (SLT, SLTU)

### 测试程序 (固化在ROM中)
```
地址  指令              说明
[0]   ADDI x1, x0, 10   x1 = 10
[1]   ADDI x2, x0, 20   x2 = 20
[2]   ADD  x3, x1, x2   x3 = 30  (10+20)
[3]   SUB  x4, x2, x1   x4 = 10  (20-10)
[4]   SW   x3, 0(x0)    Mem[0] = 30  ← 存入内存
[5]   JAL  x0, 0        停机
```

### LED 显示内容
8个LED显示 `Mem[0]` 的低8位 = **30 = 0x1E = 0001_1110**

## 🔧 ISE 操作步骤

### 步骤1: 设置顶层模块
1. 打开 `xilinx.xise`
2. Design面板 → **Implementation** 视图
3. 右键 `top (top.v)` → **Set as Top Module**
4. top 应该出现在层次结构最顶部

### 步骤2: 综合
1. 选中 `top`
2. Processes面板 → 双击 **Synthesize - XST**
3. 等待完成, 检查是否0错误

### 步骤3: 实现布局布线
1. 展开 **Implement Design**
2. 依次双击:
   - Translate
   - Map
   - Place & Route

### 步骤4: 生成bitstream
1. 展开 **Generate Programming File**
2. 双击 **Generate Bitstream**
3. 生成 `top.bit` 文件

### 步骤5: 下载到FPGA
1. 双击 **Configure Target Device** (iMPACT)
2. 用下载线连接FPGA
3. 加载 `top.bit` 下载

## 💡 预期结果

### LED 状态 (计算结果 30 = 0x1E)

```
0x1E = 0001_1110 (二进制)

LED显示 (取反后, 共阳极LED低电平亮):
位7(M)    位6(CIN)  位5(LDC)  位4(LDZ)  位3(S3)  位2(S2)  位1(S1)  位0(S0)
 1(灭)    1(灭)     0(亮)     0(亮)     0(亮)    0(亮)    1(灭)    0(亮)
```

**简单判断**: 5个LED亮(S0,S2,S3,LDZ,LDC), 3个灭(S1,CIN,M) → 结果正确

### 其他LED
- **STOP灯**: CPU停机后熄灭
- **ABUS灯(心跳)**: 持续闪烁(说明时钟工作)

## ⚠️ 可能的问题

### 问题1: T3时钟不连续
**症状**: LED不变化, CPU不动
**原因**: T3可能是手动单脉冲, 不是连续时钟
**解决**: 需要确认板子的连续时钟引脚

### 问题2: LED极性相反
**症状**: 该亮的不亮
**解决**: 修改 `top.v` 里的LED取反逻辑
```verilog
led_s0 = result[0];  // 不取反 (如果LED是共阴)
```

### 问题3: 综合资源不足
**症状**: Map阶段失败
**解决**: CPU可能太大, 需要精简

## 🎛️ 高级验证 (可选)

### 用开关切换显示内容
可以修改 top.v, 用 SWA/SWB/SWC 开关选择显示哪个寄存器:
- SWC=0: 显示 x1 (10)
- SWC=1: 显示 x2 (20)
- 等等

### 单步执行
用按键作为时钟, 一步一步执行观察

## 📊 验证清单

- [ ] ISE能综合通过
- [ ] 布局布线成功
- [ ] 生成bitstream
- [ ] 下载到FPGA
- [ ] LED显示 30 (0x1E)
- [ ] STOP灯正确指示停机

## 📝 时钟说明 (重要!)

TEC-PLUS 的 T3 (C10) 引脚:
- 如果是板子自带的连续时钟 → 直接可用
- 如果是手动脉冲 → 需要换其他时钟源

**建议**: 先确认 T3 是否为连续时钟. 可以先用一个最简单的LED闪烁测试:
```verilog
// 如果这个能让LED闪, 说明T3是连续时钟
assign led_s0 = clk;
```
