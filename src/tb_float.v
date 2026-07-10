//==================================================
// Custom lightweight float32 extension regression.
//   fadd32: 1.5 + 2.25 = 3.75 -> 0x40700000
//   fmul32: 1.5 * 2.0  = 3.0  -> 0x40400000
//   fgt32 : 2.25 > 1.5 -> 1
//==================================================
`timescale 1ns/1ps
module tb_float;

    reg clk, rst_n;
    reg [31:0] instr_mem [0:255];
    reg [31:0] data_mem  [0:255];

    wire [31:0] instr_addr, instr_data, data_addr, data_wdata, data_rdata;
    wire        instr_valid, data_we, data_valid, data_ready, halt;
    wire [3:0]  data_be;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_lus, perf_bpm, perf_mdu;

    riscv_pipeline_core u_cpu (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(instr_addr), .instr_data(instr_data), .instr_valid(instr_valid),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be), .data_we(data_we),
        .data_valid(data_valid),
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
        instr_mem[0]  = 32'h3FC000B7; // lui    x1, 0x3fc00
        instr_mem[1]  = 32'h00008093; // addi   x1, x1, 0       -> 1.5
        instr_mem[2]  = 32'h40100137; // lui    x2, 0x40100
        instr_mem[3]  = 32'h00010113; // addi   x2, x2, 0       -> 2.25
        instr_mem[4]  = 32'h400001B7; // lui    x3, 0x40000
        instr_mem[5]  = 32'h00018193; // addi   x3, x3, 0       -> 2.0
        instr_mem[6]  = 32'h0020B20B; // fadd32 x4, x1, x2      -> 3.75
        instr_mem[7]  = 32'h0030C28B; // fmul32 x5, x1, x3      -> 3.0
        instr_mem[8]  = 32'h0011530B; // fgt32  x6, x2, x1      -> 1
        instr_mem[9]  = 32'h00402023; // sw     x4, 0(x0)
        instr_mem[10] = 32'h00502223; // sw     x5, 4(x0)
        instr_mem[11] = 32'h00602423; // sw     x6, 8(x0)
        instr_mem[12] = 32'h00100073; // ebreak
    end

    initial begin
        #800;
        $display("");
        $display("=======================================");
        $display("FLOAT HALT=%0d", halt);
        $display("Mem[0] = %08h (expected 40700000, 1.5+2.25)", data_mem[0]);
        $display("Mem[1] = %08h (expected 40400000, 1.5*2.0)", data_mem[1]);
        $display("Mem[2] = %08h (expected 00000001, 2.25>1.5)", data_mem[2]);
        if (halt && (data_mem[0] == 32'h40700000) && (data_mem[1] == 32'h40400000) &&
            (data_mem[2] == 32'h00000001))
            $display("FLOAT PASS");
        else
            $display("FLOAT FAIL");
        $display("=======================================");
        $finish;
    end

endmodule
