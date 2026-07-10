//==================================================
// tb_sdram_wait.v — CPU wait-state regression using SDRAM-like memory.
//
// data_ready stays low for several cycles on each load/store. The dependent
// ADDI after LW must see the loaded value, proving the pipeline holds MEM/EX.
//==================================================
`timescale 1ns/1ps
module tb_sdram_wait;
    reg clk = 1'b0;
    reg rst_n;

    wire [31:0] instr_addr, instr_data;
    wire        instr_valid;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [3:0]  data_be;
    wire        data_valid, data_we, data_ready;
    wire        halt;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_lus, perf_bpm, perf_mdu;

    reg [31:0] instr_mem [0:31];
    integer i;

    riscv_pipeline_core dut (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(instr_addr), .instr_data(instr_data), .instr_valid(instr_valid),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be),
        .data_valid(data_valid), .data_we(data_we),
        .data_rdata(data_rdata), .data_ready(data_ready),
        .irq_external(1'b0), .halt(halt),
        .perf_cycle(perf_cycle), .perf_instret(perf_instret),
        .perf_branch(perf_branch), .perf_flush(perf_flush),
        .perf_load_use_stall(perf_lus), .perf_bp_miss(perf_bpm),
        .perf_mdu_inst(perf_mdu)
    );

    sdram_latency_model #(.WORDS(256), .LATENCY(5)) u_sdram_model (
        .clk(clk), .rst_n(rst_n),
        .req(data_valid), .we(data_we), .addr(data_addr),
        .wdata(data_wdata), .be(data_be),
        .rdata(data_rdata), .ready(data_ready)
    );

    always #5 clk = ~clk;

    assign instr_data  = instr_mem[instr_addr[6:2]];
    assign instr_valid = 1'b1;

    initial begin
        for (i = 0; i < 32; i = i + 1) instr_mem[i] = 32'h00000013;

        instr_mem[0] = 32'h123452B7; // lui    t0, 0x12345
        instr_mem[1] = 32'h67828293; // addi   t0, t0, 1656
        instr_mem[2] = 32'h00502023; // sw     t0, 0(x0)
        instr_mem[3] = 32'h00002303; // lw     t1, 0(x0)
        instr_mem[4] = 32'h00130393; // addi   t2, t1, 1
        instr_mem[5] = 32'h00702223; // sw     t2, 4(x0)
        instr_mem[6] = 32'h00402E03; // lw     t3, 4(x0)
        instr_mem[7] = 32'h01C02423; // sw     t3, 8(x0)
        instr_mem[8] = 32'h0000006F; // jal    x0, halt

        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(500) @(posedge clk);
        $display("SDRAM Mem[0]=%08h Mem[1]=%08h Mem[2]=%08h",
                 u_sdram_model.mem[0], u_sdram_model.mem[1], u_sdram_model.mem[2]);
        $display("PERF cycle=%0d instret=%0d", perf_cycle, perf_instret);
        if (u_sdram_model.mem[0] == 32'h12345678 &&
            u_sdram_model.mem[1] == 32'h12345679 &&
            u_sdram_model.mem[2] == 32'h12345679) begin
            $display("SDRAM WAIT PASS");
        end else begin
            $display("SDRAM WAIT FAIL");
        end
        $finish;
    end
endmodule
