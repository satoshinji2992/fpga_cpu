//==================================================
// Stage 1 regression: load-use hazard stall.
//
// Without the stall, the ADDI immediately after LW reads x2's stale value
// (EX/MEM forward is gated by !exmem_mem_read), so x3 becomes 1 not 6.
// With the one-cycle stall, LW's result forwards via MEM/WB->EX and x3=6.
//==================================================
`timescale 1ns/1ps
module tb_loaduse;

    reg clk, rst_n;
    reg [31:0] instr_mem [0:255];
    reg [31:0] data_mem  [0:255];

    wire [31:0] instr_addr, instr_data, data_addr, data_wdata, data_rdata;
    wire        instr_valid, data_we, data_ready, halt;
    wire [3:0]  data_be;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_load_use_stall;

    riscv_pipeline_core u_cpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr_addr (instr_addr),
        .instr_data (instr_data),
        .instr_valid(instr_valid),
        .data_addr  (data_addr),
        .data_wdata (data_wdata),
        .data_be    (data_be),
        .data_we    (data_we),
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        .halt       (halt),
        .perf_cycle        (perf_cycle),
        .perf_instret      (perf_instret),
        .perf_branch       (perf_branch),
        .perf_flush        (perf_flush),
        .perf_load_use_stall(perf_load_use_stall)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end
    initial begin rst_n = 1'b0; #20 rst_n = 1'b1; end

    assign instr_data  = instr_mem[instr_addr[9:2]];
    assign instr_valid = 1'b1;
    assign data_rdata  = data_mem[data_addr[9:2]];
    assign data_ready  = 1'b1;

    always @(posedge clk) begin
        if (data_we) begin
            if (data_be[0]) data_mem[data_addr[9:2]][7:0]   <= data_wdata[7:0];
            if (data_be[1]) data_mem[data_addr[9:2]][15:8]  <= data_wdata[15:8];
            if (data_be[2]) data_mem[data_addr[9:2]][23:16] <= data_wdata[23:16];
            if (data_be[3]) data_mem[data_addr[9:2]][31:24] <= data_wdata[31:24];
        end
    end

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            instr_mem[i] = 32'h00000013;
            data_mem[i]  = 32'h00000000;
        end
        instr_mem[0] = 32'h00500093; // ADDI x1, x0, 5
        instr_mem[1] = 32'h00100023; // SW   x1, 0(x0)    -> Mem[0] = 5
        instr_mem[2] = 32'h00002103; // LW   x2, 0(x0)    -> x2 = 5  (load)
        instr_mem[3] = 32'h00110193; // ADDI x3, x2, 1    (load-use: needs stall)
        instr_mem[4] = 32'h00302223; // SW   x3, 4(x0)    -> Mem[1] = 6
        instr_mem[5] = 32'h0000006F; // JAL  x0, 0 (halt)
    end

    initial begin
        #500;
        $display("");
        $display("=======================================");
        $display("LOAD-USE HALT=%0d at %0t", halt, $time);
        $display("Mem[0] = %0d (expected 5)", data_mem[0]);
        $display("Mem[1] = %0d (expected 6; would be 1 without stall)", data_mem[1]);
        if (halt && (data_mem[0] == 32'd5) && (data_mem[1] == 32'd6))
            $display("LOADUSE PASS");
        else
            $display("LOADUSE FAIL");
        $display("PERF cycle=%0d instret=%0d branch=%0d flush=%0d load_use_stall=%0d",
                 perf_cycle, perf_instret, perf_branch, perf_flush, perf_load_use_stall);
        $display("=======================================");
        $finish;
    end

endmodule
