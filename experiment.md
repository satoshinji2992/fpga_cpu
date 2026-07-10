# 项目进度与验证记录

更新日期：2026-07-10

## 当前基线

| 项目 | 当前状态 |
|---|---|
| 硬件版本标识 | `R13` |
| SoC 工作频率 | `25 MHz`（TEC-PLUS 50 MHz 输入经 BUFG 二分频） |
| FPGA | Xilinx Spartan-6 `XC6SLX9-2FTG256` |
| 板端固件 | `asm/soc_firmware.s` -> `src/soc_firmware.vh` |
| 串口 | 115200 baud，8N1 |
| 完整仿真回归 | `15/15 PASS` |
| 当前板端结论 | Shell、SDRAM、CNN、Pong、Paint 和性能读取可用；R13 组合开机自检待重新烧录复测 |

当前构建标识：

```text
build 25M ALL-SELFTEST FIXED-PRINT IRQ-PONG R13
```

## 功能进度

| 功能 | 状态 | 验证情况 |
|---|---|---|
| RV32I 五级流水线 | 已完成 | 基础、自相关、load-use、分支回归通过 |
| RV32M | 已完成 | `MUL/DIVU/REMU` 仿真通过，板端程序可运行 |
| Custom Float32 | 已完成 | `FADD32/FMUL32/FGT32` 仿真通过，用于数字推理 |
| 自定义位操作 | 已完成 | `POPCOUNT/BITREVERSE` 回归通过 |
| 冒险处理 | 已完成 | 前递、load-use 停顿、分支冲刷已验证 |
| 动态分支预测 | 已完成 | 16-entry 2-bit BHT，专用回归通过 |
| I-Cache | 已完成 | 直接映射与 2 路组相联版本均有测试 |
| 片内存储 | 已完成 | 8 KiB 指令 ROM、4 KiB 数据 RAM |
| 外部 SDRAM | 已完成 | 64 MiB，板端命令返回 `SDRAM PASS 64MiB` |
| UART/LED/KEY | 已完成 | MMIO 与串口 shell 可用 |
| 中断系统 | 已完成 | 最小机器态 CSR、`MRET`、UART/KEY/定时中断 |
| 性能计数器 | 已完成 | cycle、instret、branch、flush、stall、mdu、I-Cache hit/miss |
| 数字识别 | 已完成 | CPU 执行 8x8、64->10 float32 推理，串口连续交互 |
| Pong | 已完成 | 定时中断自动推进，UART 中断接收 `a/d` |
| SDRAM Paint | 已完成 | 512x256、128 KiB 画布，必须访问 SDRAM |
| 十项组合开机自检 | 待板端复测 | 仿真通过；R12 真板曾失败，R13 已修复固定格式输出但尚未取得复测结果 |
| 当前 PPA | 已刷新 | ISE/PAR/Timing/XPower 已更新；25 MHz 系统时钟约束通过 |

## R13 PPA 结果

PPA 数据来自 2026-07-10 重新实现后的 ISE 14.7 报告：

| 指标 | 报告文件 |
|---|---|
| 资源利用率 | `top.par` |
| 时序 | `top.par` / `top.twr` |
| 功耗 | `top.pwr` |

资源利用率：

| 资源 | 使用量 | 总量 | 利用率 | 备注 |
|---|---:|---:|---:|---|
| Slice Registers | `2,063` | `11,440` | `18%` | 寄存器资源充足 |
| Slice LUTs | `5,073` | `5,720` | `88%` | LUT 压力较高 |
| Occupied Slices | `1,416` | `1,430` | `99%` | Slice 接近满载 |
| Bonded IOBs | `90` | `186` | `48%` | SDRAM/外设引脚占用明显 |
| RAMB16BWER | `0` | `32` | `0%` | 未使用 16K BRAM |
| RAMB8BWER | `2` | `64` | `3%` | 少量 BRAM |
| BUFG/BUFGMUX | `2` | `16` | `12%` | 输入时钟与系统时钟 |
| DSP48A1 | `8` | `16` | `50%` | DSP 仍有余量 |

时序结果：

| 指标 | 数值 |
|---|---:|
| 系统时钟约束 | `40 ns`，即 `25 MHz` |
| Best achievable period | `31.557 ns` |
| 估算最高频率 | `31.689 MHz` |
| Worst setup slack | `8.443 ns` |
| Min-period slack | `17.334 ns` |
| Timing errors | `0` |
| Timing score | `0` |
| 约束结果 | All constraints were met |

功耗估计：

| 指标 | 数值 |
|---|---:|
| Total supply power | `44.09 mW` |
| Dynamic power | `29.38 mW` |
| Static power | `14.71 mW` |
| XPower confidence | `Medium` |

说明：XPower 未使用 SAIF/VCD 活动文件，内部节点活动覆盖不足，因此功耗只能作为粗略估计。

PPA 结论：

| 维度 | 结论 |
|---|---|
| Area | LUT `88%`、Slice `99%`，面积非常紧张；DSP 降至 `50%`，比此前版本有余量 |
| Performance | 当前 `25 MHz` 系统时钟约束通过，静态时序最高约 `31.689 MHz` |
| Power | XPower 粗略估计总功耗 `44.09 mW`，confidence 为 `Medium` |

## R13 仿真回归

运行命令：

```bash
python scripts/analyze.py
```

2026-07-10 的完整结果为 `15/15 testbench PASS`：

| Testbench | 覆盖内容 |
|---|---|
| `self-test` | 流水线基础功能 |
| `load-use` | Load-use 停顿 |
| `branchpredict` | 动态分支预测 |
| `muldiv` | RV32M 乘除法 |
| `float` | Custom Float32 |
| `custom` | 自定义位操作 |
| `all-features` | 指令综合测试 |
| `interrupt` | CSR、中断与 `MRET` |
| `sdram-wait` | CPU 外存等待握手 |
| `sdram-ctrl` | SDRAM 控制器命令与时序 |
| `cache` | 两种 I-Cache |
| `cnn` | 数字推理端到端 |
| `cnn-ablation` | CNN 分支预测对比 |
| `shell` | CPU 串口 shell |
| `soc-io` | 顶层 MMIO 与交互程序 |

关键仿真指标摘录：

| 实验 | Baseline | 优化后 | 变化 |
|---|---:|---:|---:|
| 分支预测微基准 CPI | `1.57` | `1.14` | 降低 `27.4%` |
| 分支预测微基准准确率 | - | `80.0%` | 误预测 `2` 次 |
| CNN 端到端 cycle | `34591` | `32735` | 降低 `5.4%` |
| CNN 端到端 CPI | `1.905` | `1.355` | 明显降低 |
| CNN 分支预测准确率 | `8.39%` | `95.43%` | 提高 `87.04` pct |
| I-Cache 冲突流命中率 | `68.4%` | `94.7%` | 提高 `26.3` pct |

## 真板验证记录

已经观察到的有效现象：

- `sdram` 返回 `SDRAM PASS 64MiB`。
- `cnn` 可连续接收 8x8 图像并返回预测结果。
- `pong` 可自动推进小球，并用 `a/d` 控制挡板。
- `paint` 使用 128 KiB SDRAM 画布，PC 端只负责字符渲染。
- `irq` 可读取 UART 与 KEY 中断计数。
- `p` 可读取并由 Python 解码全部性能计数器。

R12 在 12.5 MHz 下取得的一次真板累计性能快照：

| 指标 | 数值 |
|---|---:|
| cycle | `729870212` |
| instret | `534283231` |
| CPI | `1.366` |
| 吞吐量 | `9.150 MIPS` |
| branch | `195615266` |
| flush | `10` |
| bp_miss | `7625` |
| stall | `195552334` |
| mdu | `3` |
| I-Cache hit / miss | `729764955 / 105284` |
| I-Cache 命中率 | `99.99%` |

该数据是从复位开始的累计值，包含串口轮询和人工等待，只用于证明实机性能观测链路有效，不能当作单一程序的基准成绩。当前 R13 已恢复为 25 MHz，不能直接沿用上表计算 R13 的实机吞吐量。

## 开机自检布局

R13 设计了十个互不覆盖的结果槽：

```text
m0  RV32I 算术、逻辑与移位
m1  分支循环求和
m2  片内 RAM 写回
m3  MUL
m4  DIVU / REMU
m5  FADD32
m6  FMUL32 / FGT32
m7  POPCOUNT / BITREVERSE
m8  CSR / RDCYCLE
m9  SDRAM 写回
```

R13 把十六进制输出改成固定展开的无栈打印，目的是隔离此前 `mN` 乱码和组合自检输出异常。尚未取得 R13 重新烧录后的 `ver`、`s`、`m0..m9` 完整记录，因此不能把板端组合自检标记为通过。

## 已知问题

1. R12 的主应用均可工作，但组合开机自检曾出现 `FAIL MUL`、`FAIL RAM` 等不稳定结果；这说明问题不只是工作频率，也可能与自检执行顺序或输出例程有关。
2. R13 已通过全部仿真并修复固定格式输出，ISE 实现和时序已通过；仍需要重新烧录验证板端组合自检。
3. 当前“CNN”是 8x8 输入上的 `64 -> 10` float32 线性分类器，没有卷积层；它用于展示 CPU 浮点推理链路，不应写成完整卷积神经网络。
4. 系统没有 MMU、特权级和操作系统启动链，因此不是可运行 Linux 的完整通用 SoC。
5. R13 的 PPA 已刷新；当前剩余风险集中在板端组合开机自检复测。

## 下一步

1. 烧录最新 R13 bitstream。
2. 依次记录 `ver`、`s`、`m0` 到 `m9`，确认组合自检和 LED 状态。
3. 若仍失败，按第一个错误槽定位，不再同时修改频率、打印和应用逻辑。
4. 若板端复测修改了 RTL，再重新导出 Map、PAR、Timing 和功耗报告并更新 PPA。
5. 保存最终串口、LED、ISE 和开发板照片，替换报告中的占位截图。

## 最终验收标准

- `python scripts/analyze.py` 显示 `15/15 PASS`。
- 真板 `ver` 显示 R13，`s` 与 `m0..m9` 结果完整且稳定。
- `sdram`、`irq`、`p` 可重复执行且输出格式正确。
- `cnn`、`pong`、`paint` 均可进入、交互并退出回 shell。
- ISE 能生成 bitstream，R13 的资源、时序和功耗数据已补齐。
