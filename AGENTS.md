# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project

RV32I-subset CPU course design targeting the **Xilinx Spartan-6 XC6SLX9-2FTG256** on the **TEC-PLUS** core board (50 MHz clock). Verilog-2001. The same CPU core runs simulation testbenches and an on-board self-test program; LED/KEY and a UART shell are how results are observed on hardware.

## Toolchains

- **Simulation:** Icarus Verilog (`iverilog` / `vvp`) — installed locally under Homebrew; GTKWave for `.vcd` files.
- **Board build:** Xilinx **ISE 14.7** (XST synthesis → Implement Design → Generate Programming File → iMPACT for `top.bit`). The project file is `xilinx.xise`; top module is `top`.
- iverilog is far more permissive than XST 14.7. Code that **simulates clean can still fail ISE synthesis** — when a board build breaks but the testbenches pass, suspect XST-strictness (tasks with non-blocking assigns from clocked blocks, `signed` task/function ports, nested task calls), not a logic bug.

## Common commands

```bash
# Single-cycle CPU regression (expect "PASS")
iverilog -o cpu_sim src/cpu_core.v src/tb_cpu_core.v && vvp cpu_sim

# Five-stage pipeline CPU regression (expect "PIPELINE PASS")
iverilog -o pipe_sim src/riscv_pipeline_core.v src/tb_pipeline_core.v && vvp pipe_sim

# Elaboration check of the board top (no top-level testbench; just confirm it builds)
iverilog -o top_sim src/top.v src/riscv_pipeline_core.v src/icache_direct_mapped.v \
    src/serial_shell.v src/uart_rx.v src/uart_tx.v

# Host side of the UART shell (115200 8N1)
python scripts/serial_shell.py --list
python scripts/serial_shell.py -p <port>        # interactive
python scripts/serial_shell.py -p <port> --pong # keyboard Pong demo
```

VCD dumps (`cpu_core.vcd`, etc.) open in GTKWave. The ISE flow is GUI-driven; `run_simulation.tcl` configures ISim, `reference/update_ise_project.tcl` re-adds sources to the project.

## Architecture

### Two CPU cores, one memory interface

Both cores expose the **same bus** so they are swappable in a testbench or `top`:

```
instr_addr/instr_data/instr_valid      # fetch port (async read)
data_addr/data_wdata/data_be/data_we/data_rdata/data_ready   # load/store port, byte-enable
halt                                   # set when the program executes its halt instruction
```

- [cpu_core.v](src/cpu_core.v) — module `riscv_core`: **single-cycle** RV32I. Used only by [tb_cpu_core.v](src/tb_cpu_core.v) (instantiates `regfile.v`).
- [riscv_pipeline_core.v](src/riscv_pipeline_core.v) — module `riscv_pipeline_core`: **5-stage IF/ID/EX/MEM/WB** with EX-stage forwarding (EX/MEM and MEM/WB → EX) and branch/jump resolve-in-EX with younger-stage flush. This is what the board (`top`) actually runs.

[alu.v](src/alu.v), [multiplier.v](src/multiplier.v) are standalone reference modules and are **not instantiated** by either active core (each core implements its ALU inline). Don't assume edits to them affect the build.

### Board top ([top.v](src/top.v))

`top` wires `riscv_pipeline_core` + [icache_direct_mapped.v](src/icache_direct_mapped.v) + [serial_shell.v](src/serial_shell.v). Memory is on-chip:

- **Instruction ROM** `reg [31:0] instr_mem [0:63]`, async read (`instr_mem[addr[7:2]]`), initialized by an `initial` block of hand-assembled RV32I machine code.
- **Data RAM** is split into four byte-wide arrays (`data_mem_b0..b3`) so XST infers distributed RAM instead of thousands of FFs and write muxes; word reads are recombined from the four arrays.
- **I-Cache**: 8-line direct-mapped, look-through — returns ROM data in the same cycle on a miss and fills the line on the next edge. Hit/miss counters were removed because they were unused on the board and cost extra LUTs.
- **`halt` instruction** = `JAL x0, 0` (`0x0000006F`); the core raises `halt`.
- **Self-test pass** condition: `halt && Mem[0]==0x34801200 && Mem[1]==0x0000FFFE && Mem[2]==2`. With no key pressed, all 4 LEDs on = PASS; KEY1–4 display fixed nibbles of `Mem[0..2]`.

### The self-test program exists in THREE copies

The same hand-assembled instruction encodings (24 words) are duplicated in [top.v](src/top.v), [tb_cpu_core.v](src/tb_cpu_core.v), and [tb_pipeline_core.v](src/tb_pipeline_core.v). **Editing the program means updating all three** or the simulation and hardware will diverge. (Note: the testbenches index 256 words via `addr[9:2]`, while `top` uses 64 words via `addr[7:2]`.)

### UART shell ([serial_shell.v](src/serial_shell.v))

A char-at-a-time FSM (UART 115200 8N1) emits fixed response strings. It also holds a tiny Pong game state machine; the PC client (`scripts/serial_shell.py`) renders the board and sends single-letter commands. Command set: `h` help, `s` status, `0/1/2` read Mem, `g/n/x/a/d/p` Pong control + metrics.

## Conventions

- Active-low **async** reset (`rst_n`), `posedge clk` everywhere.
- Pin assignments for the TEC-PLUS board live in [top.ucf](src/top.ucf).
- The `doc/` directory mixes accurate module docs with generic, aspirational RISC-V learning material (options/extensions not present in `src/`). **Treat `src/` as ground truth** when docs conflict.
