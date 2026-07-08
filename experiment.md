# 实验结果记录

本文记录当前 `fpga_cpu` 仓库的仿真实验、ablation 对比和指标结果。实验使用 Icarus Verilog 运行，不依赖 FPGA 开发板。

## 实验环境

| 项目 | 配置 |
|---|---|
| 仿真器 | Icarus Verilog |
| 版本 | `Icarus Verilog version 12.0 (devel) (s20150603-1539-g2693dd32b)` |
| 安装位置 | `C:\tools\iverilog\bin` |
| 操作系统 | Windows |
| 仓库路径 | `C:\code\fpga_cpu` |
| 汇总脚本 | `scripts/analyze.py` |

复现命令：

```powershell
$env:PATH='C:\tools\iverilog\bin;' + $env:PATH
python scripts\analyze.py
```

本次完整回归结果：

```text
回归: 11/11 testbench 通过
```

通过的 testbench：

| testbench | 结果 |
|---|---|
| `self-test` | PASS |
| `load-use` | PASS |
| `branchpredict` | PASS |
| `muldiv` | PASS |
| `float` | PASS |
| `custom` | PASS |
| `all-features` | PASS |
| `cache` | PASS |
| `cnn` | PASS |
| `cnn-ablation` | PASS |
| `shell` | PASS |

## 关键配置

本实验重点比较 baseline 与开启优化后的指标变化。流水线 CPU 当前包含以下可观测配置：

| 项目 | 实现 |
|---|---|
| CPU | 五级流水线 `riscv_pipeline_core` |
| 分支预测 | `ENABLE_BP=1` 时开启 16-entry 2-bit BHT；`ENABLE_BP=0` 时 baseline predict-not-taken |
| I-Cache | 顶层默认使用 2-way + LRU I-Cache；参数 `USE_2WAY_ICACHE=0` 可切回 direct-mapped baseline |
| 性能计数 | `cycle`、`instret`、`branch`、`flush`、`load_use_stall`、`bp_miss`、`mdu_inst` |
| 顶层程序 | CPU 通过 UART MMIO 运行 shell / CNN / Pong 程序 |

## Ablation 总表

下表重点展示 baseline 和加入模块后的变化。

| 实验模块 | Baseline | 加入/开启后 | Baseline 指标 | 加入后指标 | 提升/变化 | 结论 |
|---|---|---|---:|---:|---:|---|
| 分支预测微基准 | `ENABLE_BP=0`，默认预测不跳转 | `ENABLE_BP=1`，16-entry 2-bit BHT | `CPI=1.57`，`flush=10` | `CPI=1.14`，`bp_miss=2`，`acc=80.0%` | CPI 降低 `27.4%` | BHT 有效减少 taken branch 带来的冲刷 |
| CNN 程序分支预测 | `ENABLE_BP=0` | `ENABLE_BP=1` | `cycle=59787`，`CPI=1.919`，`flush=9728`，`bp_miss=9555`，`acc=4.44%` | `cycle=57915`，`CPI=1.324`，`flush=403`，`bp_miss=318`，`acc=97.76%` | cycle 降低 `3.1%`，flush 降低 `95.9%` | 真实 CNN 程序中预测显著减少控制冒险 |
| I-Cache 结构 | 直接映射 8 行 | 2-way 组相联 + LRU | `hit=26`，`miss=12`，命中率 `68.4%` | `hit=36`，`miss=2`，命中率 `94.7%` | 命中率 +`26.3` pct，miss 降低 `83.3%` | 2-way cache 显著减少冲突 miss |
| Load-use 冒险处理 | 无专门暂停会读到旧值或结果错误 | 加入 load-use stall | 不作为当前可运行配置 | `LOADUSE PASS`，有 stall 计数 | 正确性提升 | load-use hazard 被正确插泡处理 |
| 数据前递 | 依赖写回后再读，会产生 RAW 冒险或需要更多 stall | EX/MEM、MEM/WB 到 EX 前递 | 不作为当前可运行配置 | self-test `CPI=1.22`，回归 PASS | 减少不必要停顿 | ALU 相关 RAW 冒险无需等 WB |
| RV32M 指令 | 无硬件乘除法 | 硬件 `MUL/DIV/REM` | 无硬件结果 | `7*6=42`，`7/6=1`，`7%6=1` | 功能扩展 | RV32M 乘除法正确 |
| Custom float32 | 无 float32 custom 指令 | `FADD32/FMUL32/FGT32` | 无硬件结果 | `FADD32=0x40700000`，`FMUL32=0x40400000`，`FGT32=1` | 功能扩展 | 支持 CNN 推理所需轻量 float32 |
| Custom bit ops | 无 bit custom 指令 | `POPCOUNT/BITREVERSE` | 无硬件结果 | `POPCOUNT=18`，`BITREV=0xff00b3d5` | 功能扩展 | 自定义 bit 指令正确 |
| 顶层 UART 程序 | 简单内存 self-test | CPU 端 shell/CNN/Pong | 无交互程序 | `CNN PASS`，`SHELL PASS` | 系统能力提升 | CPU 能运行完整板级交互程序 |

## PPA / 资源与时序

PPA 数据来自当前仓库已有的 Xilinx ISE 14.7 实现报告和本次生成的 XPower 报告：

| 指标 | 报告文件 |
|---|---|
| 资源利用率 | `top.par` / `top_map.mrp` |
| 时序 | `top.par` / `top.twr` |
| 功耗 | `top.pwr` |

注意：本轮已经把顶层 I-Cache 默认切换为 2-way + LRU。下表中的 ISE 资源/时序/功耗已根据重新编译后的 `top.par/top.twr/top.ncd/top.pcf` 和重新生成的 `top.pwr` 刷新。

目标器件：

| 项目 | 值 |
|---|---|
| FPGA | Xilinx Spartan-6 `xc6slx9` |
| 封装/速度级 | `ftg256`, `-2` |
| 目标时钟约束 | 20 ns，即 50 MHz |

资源利用率：

| 资源 | 使用量 | 总量 | 利用率 | 备注 |
|---|---:|---:|---:|---|
| Slice Registers | `1,281` | `11,440` | `11%` | 其中 FF `1,279` |
| Slice LUTs | `4,615` | `5,720` | `80%` | 逻辑和分布式 RAM 占用较高 |
| Occupied Slices | `1,344` | `1,430` | `93%` | 已接近器件容量上限 |
| LUT-FF pairs | `4,654` | - | - | fully used `1,009` |
| Bonded IOBs | `12` | `186` | `6%` | 顶层 LED/KEY/UART/clk/reset |
| RAMB16BWER | `0` | `32` | `0%` | 未使用 16K block RAM |
| RAMB8BWER | `2` | `64` | `3%` | 少量 block RAM |
| BUFG/BUFGMUX | `1` | `16` | `6%` | 主时钟 |
| DSP48A1 | `16` | `16` | `100%` | DSP 已用满 |

时序结果：

| 指标 | 数值 |
|---|---:|
| 目标周期 | `20 ns` |
| 目标频率 | `50 MHz` |
| PAR best achievable period | `98.723 ns` |
| 对应最高频率 | `10.129 MHz` |
| Worst slack | `-78.723 ns` |
| Timing errors | `528` |
| Timing score | `5787865` |
| 结论 | 当前实现未满足 50 MHz 时序 |

功耗估计：

| 指标 | 数值 |
|---|---:|
| Total supply power | `35.07 mW` |
| Dynamic power | `20.44 mW` |
| Static power | `14.63 mW` |
| XPower confidence | `Medium` |

XPower 说明：

功耗估计未使用 SAIF/VCD 活动文件，内部节点活动覆盖不足，因此只能作为粗略估计。报告中的 confidence 为 `Medium`。

ISE / XPower 报告中的关键行：

```text
* TS_clk = PERIOD TIMEGRP "clk_grp" 20 ns HIGH 50%
  SETUP Worst Case Slack = -78.723ns
  Best Case Achievable = 98.723ns
  Timing Errors = 528

Minimum period: 98.723ns (Maximum frequency: 10.129MHz)

Supply Power (mW): Total 35.07, Dynamic 20.44, Static 14.63
```

PPA 结论：

| 维度 | 结论 |
|---|---|
| Area | 资源压力主要来自 LUT、occupied slices 和 DSP；Slice 已用 `95%`，DSP 已用 `100%` |
| Performance | 当前 bitstream 对 50 MHz 约束未收敛，静态时序估计最高约 `10.129 MHz` |
| Power | 已生成 XPower 粗略估计：总功耗 `35.07 mW`，动态 `20.44 mW`，静态 `14.63 mW`；confidence 为 `Medium` |

可能的优化方向：

| 问题 | 优化方向 |
|---|---|
| LUT / Slice 占用高 | 缩小 CNN 程序/权重规模，减少 custom float 组合逻辑，裁剪非上板必需功能 |
| DSP 用满 | 减少并行乘法器，复用乘法单元，或把部分 float 运算改为定点 |
| 时序未达 50 MHz | 拆分长组合路径，给 custom float / ALU / forwarding / branch 路径加流水级 |
| 分布式 RAM 占用 LUT | 若允许增加访存周期，可改同步读以推断 block RAM |

PPA 提取脚本：

```powershell
python scripts\ppa_report.py
```

## 分支预测微基准

测试文件：`src/tb_branchpredict.v`

测试内容：

```text
sum = 1 + 2 + ... + 10
循环分支 BLT 执行 10 次：9 次 taken，1 次 not-taken
```

对比对象：

| 配置 | 含义 |
|---|---|
| `ENABLE_BP=0` | baseline，默认预测 not-taken |
| `ENABLE_BP=1` | 开启 16-entry 2-bit BHT |

结果：

| 指标 | Baseline `ENABLE_BP=0` | BHT `ENABLE_BP=1` | 变化 |
|---|---:|---:|---:|
| CPI | `1.57` | `1.14` | 降低 `27.4%` |
| flush | `10` | 约等于误预测次数 `2` | 明显减少 |
| bp_miss | 未预测 taken，误预测较多 | `2` | 明显减少 |
| 预测准确率 | 约 `10.0%` | `80.0%` | 提高约 `70.0` pct |

结论：

2-bit BHT 在循环分支上能够学习 taken 模式。由于初始状态是弱不跳转，循环开始阶段会有冷启动误预测；循环退出时也会有一次方向变化误预测，所以总误预测为 2 次，符合 2-bit BHT 的典型行为。

## CNN 端到端分支预测 Ablation

测试文件：`src/tb_cnn_ablation.v`

测试窗口：

```text
从发送 UART 命令 "cnn\n" 前开始计数，
到 UART 输出中捕获 "pred 7" 为止。
```

该窗口包含：

| 内容 | 是否计入 |
|---|---|
| CPU 轮询 UART 输入 | 是 |
| shell 解析 `cnn` 命令 | 是 |
| 接收 8x8 图像 | 是 |
| CNN 推理程序 | 是 |
| UART 输出结果 | 是 |

输入图像：

```text
00000000
00000000
00111100
00111100
00001100
00011000
00011000
00010000
```

预期输出：

```text
pred 7
```

结果：

| 指标 | Baseline `ENABLE_BP=0` | BHT `ENABLE_BP=1` | 变化 |
|---|---:|---:|---:|
| cycle | `59787` | `57915` | 降低 `3.1%` |
| instret | `31157` | `43741` | 增加 |
| CPI | `1.919` | `1.324` | 降低 `31.0%` |
| branch | `9999` | `14193` | 增加 |
| flush | `9728` | `403` | 降低 `95.9%` |
| bp_miss | `9555` | `318` | 降低 `96.7%` |
| 预测准确率 | `4.44%` | `97.76%` | 提高 `93.32` pct |
| load-use stall | `9174` | `13369` | 增加 |
| mdu inst | `0` | `0` | 无变化 |

说明：

`ENABLE_BP=1` 和 `ENABLE_BP=0` 的 `instret`、`branch` 不完全相同，是因为本实验是端到端 UART 交互窗口。开启预测后程序更快推进，捕获到 `pred 7` 时所处的 I/O 输出节奏和退休指令窗口会发生差异。因此端到端 cycle 是主要对比指标，flush、bp_miss 和准确率用于说明控制冒险变化。

结论：

在真实 CNN UART 程序中，2-bit BHT 将 flush 从 `9728` 降到 `403`，将误预测从 `9555` 降到 `318`。这说明 IF 阶段预测 PC 的逻辑确实在工作。端到端 cycle 从 `59787` 降到 `57915`，总体降低 `3.1%`。

## I-Cache 对比实验

测试文件：`src/tb_cache.v`

测试内容：

```text
访问冲突地址流：0, 32, 0, 32, ...
这些地址映射到直接映射 cache 的同一组。
```

结果：

| 指标 | 直接映射 8 行 | 2-way 组相联 + LRU | 变化 |
|---|---:|---:|---:|
| hit | `26` | `36` | 增加 `10` |
| miss | `12` | `2` | 降低 `83.3%` |
| 命中率 | `68.4%` | `94.7%` | 提高 `26.3` pct |

结论：

2-way 组相联 cache 能保留两个冲突地址，显著减少直接映射 cache 的冲突 miss。

注意：

当前 FPGA 顶层 `top.v` 默认使用 2-way + LRU I-Cache。若要进行 direct-mapped baseline 综合，可将 `top` 参数 `USE_2WAY_ICACHE` 设为 `0`。

## RV32M 乘除法实验

测试文件：`src/tb_muldiv.v`

结果：

| 指令/表达式 | 结果 | 期望 | 结论 |
|---|---:|---:|---|
| `MUL 7*6` | `42` | `42` | PASS |
| `DIV 7/6` | `1` | `1` | PASS |
| `REM 7%6` | `1` | `1` | PASS |

结论：

RV32M 的基本乘除法路径正确。当前实现中乘法为组合乘法，除法使用多周期恢复除法 FSM，以避免综合出过大的组合除法路径。

## Custom float32 实验

测试文件：`src/tb_float.v`

结果：

| 指令 | 输入 | 输出 | 期望 | 结论 |
|---|---|---:|---:|---|
| `FADD32` | `1.5 + 2.25` | `0x40700000` | `0x40700000` | PASS |
| `FMUL32` | `1.5 * 2.0` | `0x40400000` | `0x40400000` | PASS |
| `FGT32` | `2.25 > 1.5` | `0x00000001` | `0x00000001` | PASS |

结论：

轻量 float32 custom 指令能够支持 CNN 推理演示所需的基本浮点运算。该实现不是完整 RV32F，不包含 NaN、Inf、subnormal、舍入模式和异常标志。

## Custom bit 指令实验

测试文件：`src/tb_custom.v`

结果：

| 指令 | 输入 | 输出 | 期望 | 结论 |
|---|---|---:|---:|---|
| `POPCOUNT` | `0xABCD00FF` | `18` | `18` | PASS |
| `BITREVERSE` | `0xABCD00FF` | `0xff00b3d5` | `0xff00b3d5` | PASS |

结论：

custom-0 opcode 下的 bit 操作扩展执行正确。

## CNN 功能实验

测试文件：`src/tb_cnn.v`

测试过程：

1. 顶层 `top` 运行 CPU 程序。
2. testbench 通过 UART 发送 `cnn\n`。
3. testbench 发送 8x8 二值图像。
4. 捕获 CPU 通过 UART 打印的结果。
5. 检查输出中是否包含 `pred 7`。
6. 检查 LED 是否为 `7`。

结果：

| 指标 | 结果 |
|---|---|
| UART 输出 | 包含 `pred 7` |
| LED | `7` |
| testbench | `CNN PASS` |

结论：

CPU 能够通过 UART MMIO 接收 8x8 图像，运行 CNN 推理程序，并通过 UART/LED 输出预测结果。

## Shell/Pong 功能实验

测试文件：`src/tb_shell.v`

测试命令：

```text
h
s
m1
p
leda
pong
d
q
```

检查项：

| 检查项 | 结果 |
|---|---|
| 状态输出包含 `OK ` | PASS |
| 内存输出包含 `mem1=` | PASS |
| 性能输出包含 `cycle` | PASS |
| Pong 状态输出正确 | PASS |
| LED 状态符合预期 | PASS |

结论：

CPU 端 shell、性能计数输出、内存读取、LED 控制和 Pong demo 的 UART 交互均可用。

## 当前仍未覆盖的指标

| 指标 | 状态 | 说明 |
|---|---|---|
| 上板 UART 实测吞吐 | 未在本文记录 | 需要实际 TEC-PLUS 板卡测试 |

当前仿真已经覆盖功能正确性、CPI、分支预测准确率、flush、bp_miss、load-use stall、I-cache 命中率、RV32M、custom 指令、CNN 和 UART shell。资源、时序和功耗已根据重新编译后的 ISE/XPower 报告记录；实板指标仍需补充。
