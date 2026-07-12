# 项目进度与验证记录

更新日期：2026-07-12

## 当前基线

| 项目 | 当前状态 |
|---|---|
| 硬件版本标识 | `R16` |
| 发布版本 | `2.0.0` |
| SoC 工作频率 | `50 MHz`（TEC-PLUS 50 MHz 输入经 BUFG，单一时钟域） |
| FPGA | Xilinx Spartan-6 `XC6SLX9-2FTG256` |
| 板端固件 | `asm/soc_firmware.s` -> `src/soc_firmware.vh` |
| 串口 | 115200 baud，8N1 |
| 完整仿真回归 | `17/17 PASS` |
| 当前板端结论 | R15已在50 MHz真板稳定显示`SELFTEST PASS`；R16待ISE编译和烧录 |

当前构建标识：

```text
build 50M ALL-SELFTEST SYNC-BRAM50 IRQ-PONG R16
```

## 功能进度

| 功能 | 状态 | 验证情况 |
|---|---|---|
| RV32I 五级流水线 | 已完成 | 同步取指空拍可正确注入 bubble，基础、自相关、load-use、分支回归通过 |
| RV32M | 已完成 | MUL 系列改为 32 拍迭代乘法，DIV/REM 保持多周期；回归通过 |
| Custom Float32 | 已完成 | `FADD32/FMUL32/FGT32` 仿真通过，用于数字推理 |
| 自定义位操作 | 已完成 | `POPCOUNT/BITREVERSE` 回归通过 |
| 冒险处理 | 已完成 | 前递、load-use 停顿、分支冲刷已验证 |
| 动态分支预测 | 已完成 | 16-entry 2-bit BHT，专用回归通过 |
| I-Cache | 已完成 | 直接映射与 2 路组相联版本均有测试 |
| 片内存储 | 已完成 | R16为16 KiB同步指令ROM、4 KiB同步字节写数据RAM；R15的8 KiB版本已确认BRAM推断 |
| 外部 SDRAM | 已完成 | 64 MiB，板端命令返回 `SDRAM PASS 64MiB` |
| UART/LED/KEY | 已完成 | MMIO 与串口 shell 可用 |
| 中断系统 | 已完成 | 最小机器态 CSR、`MRET`、UART/KEY/定时中断 |
| 性能计数器 | 已完成 | cycle、instret、branch、flush、stall、mdu、I-Cache hit/miss |
| 数字识别 | 已完成 | CPU执行8x8、64->8->10 float32 MLP，精确模型测试集82.84%，原型10/10 |
| 浮点计算器 | 已完成 | `calc`支持十进制数、括号、一元负号及`+ - * /`，UART端到端测试通过 |
| Pong | 已完成 | 定时中断自动推进，UART 中断接收 `a/d` |
| SDRAM Paint | 已完成 | 512x256、128 KiB 画布，必须访问 SDRAM |
| 十项组合开机自检 | R15真板通过 | R16仿真通过，需新bitstream复测 |
| 当前 PPA | 已完成 | R16面积、时序和XPower均已刷新 |

## R16 50 MHz PPA

R16于2026-07-12完成ISE 14.7综合、布局布线和bitstream生成。XST确认`instr_mem`为`4096x32` Block RAM，CPU `regs`为Distributed RAM；后者没有退回曾导致R14真板错误的同步Block RAM实现。

| 资源 | R15 | R16 | 变化 |
|---|---:|---:|---:|
| Slice Registers | `2584`（22%） | `2584`（22%） | 不变 |
| Slice LUTs | `4455`（77%） | `4455`（77%） | 不变 |
| Occupied Slices | `1358`（94%） | `1371`（95%） | `+13` |
| RAMB16BWER | `4`（12%） | `8`（25%） | `+4`，来自16 KiB指令ROM |
| RAMB8BWER | `4`（6%） | `4`（6%） | 不变 |
| DSP48A1 | `0` | `0` | 不变 |

| 时序指标 | R15 | R16 |
|---|---:|---:|
| 最短周期 | `18.267 ns` | `19.349 ns` |
| 最大频率 | `54.744 MHz` | `51.682 MHz` |
| 20 ns约束裕量 | `1.733 ns` | `0.651 ns` |
| Timing errors | `0` | `0` |
| 约束结论 | 通过 | 通过 |

R16以4个RAMB16和约5.6%的Fmax下降换取更大的固件空间、两层浮点MLP及表达式计算器。51.682 MHz仍高于50 MHz目标，但裕量仅0.651 ns，后续增加组合逻辑时必须重新检查时序。

| 功耗指标 | R15 | R16 | 变化 |
|---|---:|---:|---:|
| Total supply power | `90.56 mW` | `91.30 mW` | `+0.74 mW` |
| Dynamic power | `75.46 mW` | `76.19 mW` | `+0.73 mW` |
| Static power | `15.10 mW` | `15.11 mW` | `+0.01 mW` |
| XPower confidence | Medium | Medium | 均未加载VCD/SAIF |

R16 XPower基于当前`top.ncd/top.pcf`进行vector-less活动率传播。功耗增幅约0.82%，与新增指令BRAM及固件功能相符；该值适合版本间PPA比较，不等同于板级实测功耗。

## R13 PPA Baseline

以下数据来自 2026-07-10 的 R13 25 MHz ISE 14.7 报告，仅用于与 R14 对比：

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

## R14 50 MHz PPA

R14于2026-07-11完成ISE 14.7布局布线和XPower分析，数据来自当前`top.par/top.twr/top.pwr`。

| 资源 | R13 baseline | R14 | 变化 |
|---|---:|---:|---:|
| Slice Registers | `2,063`（18%） | `2,573`（22%） | `+510` |
| Slice LUTs | `5,073`（88%） | `4,397`（76%） | `-676`，降低12 pct |
| Occupied Slices | `1,416`（99%） | `1,330`（93%） | `-86`，降低6 pct |
| RAMB16BWER | `0` | `4`（12%） | 指令ROM映射到BRAM |
| RAMB8BWER | `2`（3%） | `6`（9%） | 四路数据RAM映射到BRAM |
| DSP48A1 | `8`（50%） | `0` | 组合乘法改为迭代逻辑 |
| BUFG | `2` | `1` | 取消逻辑分频时钟 |

| 时序指标 | R14结果 |
|---|---:|
| 系统时钟约束 | `20 ns`（50 MHz） |
| Best achievable period | `19.216 ns` |
| Maximum frequency | `52.040 MHz` |
| Worst setup slack | `+0.784 ns` |
| Timing errors / score | `0 / 0` |
| 约束结果 | `All constraints met` |

XST确认`2048x32`指令ROM和四个`1024x8`数据RAM均实现为Block RAM。最终关键路径不再经过DSP级联，而是EX前递/ALU结果选择路径。50 MHz在ISE慢速角模型下具有正裕量，但裕量小于最初2 ns理想目标，仍需真板连续自检验证。

| 功耗指标 | R13 baseline | R14 50 MHz |
|---|---:|---:|
| Total supply power | `44.09 mW` | `90.56 mW` |
| Dynamic power | `29.38 mW` | `75.46 mW` |
| Static power | `14.71 mW` | `15.10 mW` |
| Junction temperature | - | `27.9 C` |
| XPower confidence | `Medium` | `Medium` |

R14动态功耗增加与系统时钟从25 MHz提高到50 MHz有关。XPower未加载SAIF/VCD活动文件，节点翻转率来自vector-less传播和默认值，因此该结果只用于版本间粗略PPA比较，不作为实测板级功耗。

## R14 仿真回归

运行命令：

```bash
python scripts/analyze.py
```

使用 WSL Icarus Verilog 12.0 重新运行，R16完整结果为 `17/17 testbench PASS`：

| Testbench | 覆盖内容 |
|---|---|
| `self-test` | 流水线基础功能 |
| `load-use` | Load-use 停顿 |
| `branchpredict` | 动态分支预测 |
| `muldiv` | RV32M 乘除法 |
| `muldiv-edges` | RV32M高半积、符号、无符号、除零与溢出边界 |
| `float` | Custom Float32 |
| `custom` | 自定义位操作 |
| `all-features` | 指令综合测试 |
| `interrupt` | CSR、中断与 `MRET` |
| `sdram-wait` | CPU 外存等待握手 |
| `sdram-ctrl` | SDRAM 控制器命令与时序 |
| `cache` | 两种 I-Cache |
| `cnn` | 数字推理端到端 |
| `cnn-ablation` | CNN 分支预测对比 |
| `calculator` | 浮点表达式解析、优先级、括号、小数、除法与错误处理 |
| `shell` | CPU 串口 shell |
| `soc-io` | 顶层 MMIO 与交互程序 |

关键仿真指标摘录：

| 实验 | Baseline | 优化后 | 变化 |
|---|---:|---:|---:|
| 分支预测微基准 CPI | `1.57` | `1.14` | 降低 `27.4%` |
| 分支预测微基准准确率 | - | `80.0%` | 误预测 `2` 次 |
| CNN 端到端 cycle | `70347` | `66258` | 降低 `5.8%` |
| CNN 端到端 CPI | `3.021` | `2.273` | 降低 `24.8%` |
| CNN 分支预测准确率 | `6.27%` | `96.46%` | 提高 `90.19` pct |
| I-Cache 冲突流命中率 | `0.0%` | `83.3%` | 提高 `83.3` pct |

R14 的周期数包含同步取指/数据 RAM 延迟以及迭代式 FMUL，因此不能直接与 R13 的周期数比较。按目标频率换算，R14 CNN 预测路径约为 `67276 / 50 MHz = 1.346 ms`；R13 记录为 `32735 / 25 MHz = 1.309 ms`。当前重构首先换取时序可实现性和稳定性，性能是否改善需以新的 ISE Fmax 与真板测量为准。

## 真板验证记录

R15于2026-07-12在TEC-PLUS板卡、50 MHz时钟下完成复测：启动输出为`SELFTEST PASS`，`m0..m9`均稳定正确，串口CNN模式可连续识别0、1、2、3、5、7等演示图。R14中不稳定的`m1`与错误的`m4`最终定位为XST把CPU寄存器文件错误推断成同步Block RAM；R15用`ram_style="distributed"`强制组合读LUT RAM后解决。

R16在此基础上扩展16 KiB指令ROM、两层浮点MLP和计算器。当前只有RTL仿真结论，不能把R15的真板与PPA数据直接标成R16结果。

旧版 R11/R12 已经观察到的有效现象（不是 R14 验收结果）：

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

该数据是从复位开始的累计值，包含串口轮询和人工等待，只用于证明旧版本实机性能观测链路有效，不能当作 R14 基准成绩。

## 开机自检布局

R14 保留十个互不覆盖的结果槽：

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

十六进制输出继续使用固定展开的无栈打印。尚未取得 R14 bitstream 的 `ver`、`s`、`m0..m9` 完整记录，因此不能把板端组合自检标记为通过。

## 已知问题

1. R12 的主应用均可工作，但组合开机自检曾出现 `FAIL MUL`、`FAIL RAM` 等不稳定结果；这说明问题不只是工作频率，也可能与自检执行顺序或输出例程有关。
2. R15已解决寄存器文件被XST错误映射为同步BRAM的问题，并在50 MHz真板通过自检；R16扩容后仍需重新完成ISE和真板验收。
3. 当前“CNN”是8x8输入上的`64 -> 8 -> 10` float32 MLP，没有卷积层；它用于展示CPU浮点推理链路，不应写成卷积神经网络。
4. 系统没有 MMU、特权级和操作系统启动链，因此不是可运行 Linux 的完整通用 SoC。
5. R16 PPA已完整刷新；XPower为无SAIF的Medium-confidence估算，不能替代板级电流实测。

## 下一步

1. 使用ISE 14.7完成R16 XST、Map、PAR和bitstream，确认16 KiB指令ROM映射到BRAM且寄存器文件保持distributed RAM。
2. 检查 20 ns约束、未应用约束和未约束路径，并运行布局布线后门级时序仿真。
3. 烧录后依次记录 `ver`、`s`、`m0` 到 `m9`，确认组合自检和 LED 状态。
4. 若仍失败，按第一个错误槽定位，不再同时修改频率、打印和应用逻辑。
5. 保存最终串口、LED、ISE 和开发板照片。

## 最终验收标准

- `python scripts/analyze.py` 显示 `17/17 PASS`。
- 真板`ver`显示R16，`s`与`m0..m9`结果完整且稳定，`cnn`与`calc`均可交互。
- `sdram`、`irq`、`p` 可重复执行且输出格式正确。
- `cnn`、`pong`、`paint` 均可进入、交互并退出回 shell。
- ISE能生成bitstream，20 ns约束通过且R16的资源、时序和功耗数据已补齐。
