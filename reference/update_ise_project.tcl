#==============================================
# ISE项目更新脚本
# 用于将CPU模块添加到现有ISE项目
#==============================================project new xilinx.xise -dir "c:/code/fpga/xilinx"# 设置项目属性
project set "Device Family" "Spartan6"project set "Device" "xc6slx9"project set "Package" "ftg256"
project set "Speed Grade" "-2"project set "Top-Level Source Type" "HDL"project set "Synthesis Tool" "XST (Verilog)"
project set "Preferred Language" "Verilog"# 添加源文件
xfile add "cpu_core.v"xfile add "alu.v"xfile add "regfile.v"
xfile add "multiplier.v"# 添加测试文件（仅仿真）xfile add "tb_cpu_core.v" -view simulation# 保存项目project save
#==============================================
# 综合脚本
#==============================================project set "Top Module" "riscv_core"process run "Synthesize"#==============================================
# 生成综合报告
#==============================================# 运行此脚本后，可以在ISE中查看：
# - 综合报告（资源使用情况）
# - RTL原理图# - 时序报告
