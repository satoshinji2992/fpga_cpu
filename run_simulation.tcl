#==============================================
# ISE仿真设置脚本
# 在ISE中运行: Tools → TCL Console → source run_simulation.tcl
#==============================================# 设置项目属性
project set "Simulator" "ISim (Verilog)"
project set "Simulation Top Module" "tb_cpu_core"
project set "Simulation Runtime" "1000ns"
project set "Simulation Mode" "Behavioral"# 添加测试文件（如果还没有）
# 检查是否已存在tb_cpu_core.v
set testfile_exists 0foreach f [get_files -quiet {*.v}] {    if {[string match "*tb_cpu_core.v" $f]} {        set testfile_exists 1
        break
    }}if {!$testfile_exists} {    puts "Adding tb_cpu_core.v to project..."
    add_file -srcfile "src/tb_cpu_core.v" -lib work -view simulation}# 显示配置信息puts "========================================"puts "ISE Simulation Configuration"puts "========================================"puts "Top Module: tb_cpu_core"puts "Runtime: 1000ns"puts "Mode: Behavioral"puts ""puts "Next Steps:"puts "1. In Design panel, select 'Simulation' view"puts "2. Set 'tb_cpu_core' as top module"puts "3. Go to Processes → ISim Simulator"puts "4. Double-click 'Simulate Behavioral Model'"puts "========================================"puts ""puts "Or run simulation now with:"puts "process run \"Simulate Behavioral Model\""
