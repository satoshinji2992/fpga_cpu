# Rebuild/update the ISE project source list for the current CPU CNN demo design.
# Run from the repository root in ISE Tcl console if Project Navigator loses
# source associations.

project open xilinx.xise

# Implementation sources
xfile add "src/top.v"
xfile add "src/riscv_pipeline_core.v"
xfile add "src/icache_direct_mapped.v"
xfile add "src/uart_rx.v"
xfile add "src/uart_tx.v"
xfile add "src/top.ucf"

# Standalone/reference sources
xfile add "src/cpu_core.v"
xfile add "src/alu.v"
xfile add "src/regfile.v"
xfile add "src/multiplier.v"
xfile add "src/icache_2way.v"

# Simulation sources
xfile add "src/tb_cpu_core.v" -view Simulation
xfile add "src/tb_pipeline_core.v" -view Simulation
xfile add "src/tb_all_features.v" -view Simulation
xfile add "src/tb_cnn.v" -view Simulation
xfile add "src/tb_loaduse.v" -view Simulation
xfile add "src/tb_branchpredict.v" -view Simulation
xfile add "src/tb_cache.v" -view Simulation
xfile add "src/tb_muldiv.v" -view Simulation
xfile add "src/tb_float.v" -view Simulation
xfile add "src/tb_custom.v" -view Simulation
xfile add "src/tb_csr.v" -view Simulation
xfile add "src/tb_demo.v" -view Simulation

project set "Top Module" "top"
project save
