//==================================================
// tb_interrupt.v — minimal machine-mode interrupt regression.
//
// The program enables MEIE+MIE, spins in main_loop, and the testbench pulses
// irq_external. The handler records mcause/mepc and returns via MRET.
//==================================================
`timescale 1ns/1ps
module tb_interrupt;
    reg clk = 1'b0;
    reg rst_n;
    reg irq_external;

    wire [31:0] instr_addr, instr_data;
    wire        instr_valid;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0]  data_be;
    wire        data_we;
    wire        data_ready;
    wire        halt;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_lus, perf_bpm, perf_mdu;

    reg [31:0] instr_mem [0:63];
    reg [31:0] data_mem  [0:15];
    integer i;

    riscv_pipeline_core dut (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(instr_addr), .instr_data(instr_data), .instr_valid(instr_valid),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be),
        .data_we(data_we), .data_rdata(data_rdata), .data_ready(data_ready),
        .irq_external(irq_external), .halt(halt),
        .perf_cycle(perf_cycle), .perf_instret(perf_instret),
        .perf_branch(perf_branch), .perf_flush(perf_flush),
        .perf_load_use_stall(perf_lus), .perf_bp_miss(perf_bpm),
        .perf_mdu_inst(perf_mdu)
    );

    always #5 clk = ~clk;

    assign instr_data  = instr_mem[instr_addr[7:2]];
    assign instr_valid = 1'b1;
    assign data_rdata  = data_mem[data_addr[5:2]];
    assign data_ready  = 1'b1;

    always @(posedge clk) begin
        if (data_we && data_be == 4'b1111)
            data_mem[data_addr[5:2]] <= data_wdata;
    end

    initial begin
        for (i = 0; i < 64; i = i + 1) instr_mem[i] = 32'h00000013;
        for (i = 0; i < 16; i = i + 1) data_mem[i] = 32'h00000000;

        instr_mem[ 0] = 32'h02C00293; // addi   t0, x0, handler
        instr_mem[ 1] = 32'h30529073; // csrrw  x0, mtvec, t0
        instr_mem[ 2] = 32'h000012B7; // lui    t0, 0x1
        instr_mem[ 3] = 32'h80028293; // addi   t0, t0, -2048
        instr_mem[ 4] = 32'h30429073; // csrrw  x0, mie, t0
        instr_mem[ 5] = 32'h00800293; // addi   t0, x0, 8
        instr_mem[ 6] = 32'h30029073; // csrrw  x0, mstatus, t0
        instr_mem[ 7] = 32'h00000313; // addi   t1, x0, 0
        instr_mem[ 8] = 32'h00130313; // addi   t1, t1, 1
        instr_mem[ 9] = 32'h00602623; // sw     t1, 12(x0)
        instr_mem[10] = 32'hFF9FF06F; // jal    x0, main_loop
        instr_mem[11] = 32'h00100393; // addi   t2, x0, 1
        instr_mem[12] = 32'h00702023; // sw     t2, 0(x0)
        instr_mem[13] = 32'h34202E73; // csrrs  t3, mcause, x0
        instr_mem[14] = 32'h01C02223; // sw     t3, 4(x0)
        instr_mem[15] = 32'h34102EF3; // csrrs  t4, mepc, x0
        instr_mem[16] = 32'h01D02423; // sw     t4, 8(x0)
        instr_mem[17] = 32'h30200073; // mret

        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(80) @(posedge clk);
        irq_external = 1'b1;
        repeat(1) @(posedge clk);
        irq_external = 1'b0;

        repeat(300) @(posedge clk);
        $display("INT Mem[0]=%0d Mem[1]=%08h Mem[2]=%08h Mem[3]=%0d",
                 data_mem[0], data_mem[1], data_mem[2], data_mem[3]);
        $display("PERF cycle=%0d instret=%0d flush=%0d", perf_cycle, perf_instret, perf_flush);
        if (data_mem[0] == 32'd1 && data_mem[1] == 32'h8000000B &&
            data_mem[2] != 32'd0 && data_mem[3] != 32'd0) begin
            $display("INTERRUPT PASS");
        end else begin
            $display("INTERRUPT FAIL");
        end
        $finish;
    end
endmodule
