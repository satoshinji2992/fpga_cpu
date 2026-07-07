# Spartan-6 FPGA Linux SoC 指南

## 项目概述
使用 LiteX + VexRiscv 在 Spartan-6 XC6SLX9 FPGA 上运行 Linux

## 硬件配置
- FPGA: Spartan-6 XC6SLX9-2FTG256
- 外部存储: SDRAM
- 工具链: Xilinx ISE 14.7

## 开源项目

### 1. linux-on-litex-vexriscv (推荐)
- **地址**: https://github.com/litex-hub/linux-on-litex-vexriscv
- **描述**: 专门用于在LiteX/VexRiscv SoC上运行Linux的完整项目
- **特点**:
  - 支持Spartan-6 (使用ISE工具链)
  - 预编译的bitstream可用
  - 支持串口/SD卡/以太网启动

### 2. 相关组件
- **LiteX**: SoC生成框架
- **VexRiscv**: 32位RISC-V软核处理器
- **LiteDRAM**: DRAM控制器
- **OpenSBI**: RISC-V引导固件

## 快速开始步骤

### 步骤1: 安装依赖
```bash
# Ubuntu/Debian
sudo apt install build-essential device-tree-compiler wget git python3-setuptools

# 下载并安装LiteX
wget https://raw.githubusercontent.com/enjoy-digital/litex/master/litex_setup.py
chmod +x litex_setup.py
./litex_setup.py --init --install --user
```

### 步骤2: 克隆项目
```bash
git clone https://github.com/litex-hub/linux-on-litex-vexriscv
cd linux-on-litex-vexriscv
```

### 步骤3: 查看支持的板卡
```bash
./make.py --help
```

### 步骤4: 为自定义板卡创建配置
由于您的板卡不在默认支持列表中，需要：
1. 参考 `mini_spartan6` 板卡配置
2. 根据您的硬件修改约束文件
3. 配置SDRAM参数

### 步骤5: 编译Bitstream (可选)
项目提供预编译的bitstream，可以直接使用。
如需重新编译：
```bash
./make.py --board=<your_board> --cpu-count=1 --build
```

### 步骤6: 启动Linux
```bash
# 加载bitstream
./make.py --board=<your_board> --load

# 通过串口加载Linux镜像
litex_term --images=images/boot.json /dev/ttyUSBX
```

## 注意事项

### 资源要求
- 最少需要 32MB RAM (SDRAM)
- UART接口用于控制台
- 更多RAM可以运行更完整的功能

### ISE工具链
- LiteX对Spartan-6使用ISE而非Vivado
- 确保ISE 14.7已安装
- Windows环境下需要额外配置

### 板卡适配
如果您的板卡不在支持列表中：
1. 找到类似板卡的配置文件
2. 修改约束文件 (.xcf)
3. 调整SDRAM时序参数
4. 可能需要调整引脚分配

## 下一步

1. 确认您的板卡SDRAM大小和型号
2. 选择最相似的参考板卡
3. 创建自定义板卡配置
4. 测试SoC功能
5. 启动Linux

## 参考资源

- LiteX Wiki: https://github.com/enjoy-digital/litex/wiki
- VexRiscv: https://github.com/SpinalHDL/VexRiscv
- RISC-V Linux: https://github.com/riscv-collab/riscv-linux
