//==================================================
// 上板综合演示程序的仿真验证 (与 top.v 固化程序一致)
//   mem0 = MUL 7*6 = 42          (RV32M)
//   mem1 = sum 1+..+10 = 55      (循环 -> 分支预测)
//   mem2 = POPCOUNT(0xFF) = 8    (自定义指令)
//==================================================
`timescale 1ns/1ps
module tb_demo;

    reg clk, rst_n;
    reg [31:0] instr_mem [0:255];
    reg [31:0] data_mem  [0:255];

    wire [31:0] instr_addr, instr_data, data_addr, data_wdata, data_rdata;
    wire        instr_valid, data_we, data_ready, halt;
    wire [3:0]  data_be;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_lus, perf_bpm, perf_mdu;

    riscv_pipeline_core u_cpu (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(instr_addr), .instr_data(instr_data), .instr_valid(instr_valid),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be), .data_we(data_we),
        .data_rdata(data_rdata), .data_ready(data_ready), .halt(halt),
        .perf_cycle(perf_cycle), .perf_instret(perf_instret), .perf_branch(perf_branch),
        .perf_flush(perf_flush), .perf_load_use_stall(perf_lus), .perf_bp_miss(perf_bpm),
        .perf_mdu_inst(perf_mdu)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end
    initial begin rst_n = 1'b0; #20 rst_n = 1'b1; end

    assign instr_data  = instr_mem[instr_addr[9:2]];
    assign instr_valid = 1'b1;
    assign data_rdata  = data_mem[data_addr[9:2]];
    assign data_ready  = 1'b1;

    always @(posedge clk) if (data_we) begin
        if (data_be[0]) data_mem[data_addr[9:2]][7:0]   <= data_wdata[7:0];
        if (data_be[1]) data_mem[data_addr[9:2]][15:8]  <= data_wdata[15:8];
        if (data_be[2]) data_mem[data_addr[9:2]][23:16] <= data_wdata[23:16];
        if (data_be[3]) data_mem[data_addr[9:2]][31:24] <= data_wdata[31:24];
    end

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            instr_mem[i] = 32'h00000013; data_mem[i] = 32'h00000000;
        end
        instr_mem[0]  = 32'h00700093; // ADDI x1, x0, 7
        instr_mem[1]  = 32'h00600113; // ADDI x2, x0, 6
        instr_mem[2]  = 32'h022081B3; // MUL  x3, x1, x2      -> 42
        instr_mem[3]  = 32'h00302023; // SW   x3, 0(x0)       -> mem0 = 42
        instr_mem[4]  = 32'h00000213; // ADDI x4, x0, 0       (sum)
        instr_mem[5]  = 32'h00100293; // ADDI x5, x0, 1       (i)
        instr_mem[6]  = 32'h00B00313; // ADDI x6, x0, 11      (bound)
        instr_mem[7]  = 32'h00520233; // ADD  x4, x4, x5      (loop:)
        instr_mem[8]  = 32'h00128293; // ADDI x5, x5, 1
        instr_mem[9]  = 32'hFE62CCE3; // BLT  x5, x6, -8      (-> loop)
        instr_mem[10] = 32'h00402223; // SW   x4, 4(x0)       -> mem1 = 55
        instr_mem[11] = 32'h0FF00393; // ADDI x7, x0, 0xFF
        instr_mem[12] = 32'h0003940B; // POPCOUNT x8, x7      -> 8
        instr_mem[13] = 32'h00802423; // SW   x8, 8(x0)       -> mem2 = 8
        instr_mem[14] = 32'hC00024F3; // RDCYCLE  x9         -> x9 = cycle (CSR)
        instr_mem[15] = 32'h00902623; // SW       x9, 12(x0) -> Mem[3] = cycle
        instr_mem[16] = 32'h00000073; // ECALL (halt)
    end

    real cpi;
    real acc;
    initial begin
        #3000;
        cpi = (perf_instret > 0) ? (1.0 * perf_cycle / perf_instret) : 0.0;
        acc = (perf_branch > 0) ? (100.0 * (perf_branch - perf_bpm) / perf_branch) : 0.0;
        $display("");
        $display("=======================================");
        $display("DEMO HALT=%0d", halt);
        $display("Mem[0] = %0d (expected 42, MUL 7*6)",        data_mem[0]);
        $display("Mem[1] = %0d (expected 55, sum 1..10)",      data_mem[1]);
        $display("Mem[2] = %0d (expected 8,  POPCOUNT 0xFF)",  data_mem[2]);
        if (halt && (data_mem[0]==32'd42) && (data_mem[1]==32'd55) && (data_mem[2]==32'd8) && (data_mem[3]>0))
            $display("DEMO PASS");
        else
            $display("DEMO FAIL");
        $display("Mem[3] = %0d (RDCYCLE, CSR read)", data_mem[3]);
        $display("PERF cycle=%0d instret=%0d cpi=%.2f branch=%0d flush=%0d bp_miss=%0d acc=%.1f%% mdu=%0d",
                 perf_cycle, perf_instret, cpi, perf_branch, perf_flush, perf_bpm, acc, perf_mdu);
        $display("=======================================");
        $finish;
    end

endmodule
