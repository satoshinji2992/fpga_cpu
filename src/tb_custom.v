//==================================================
// Stage 5 regression: custom-0 ISA extension.
//   x1 = 0xABCD00FF
//   POPCOUNT x2, x1 -> 18  (count of set bits)
//   BITREV   x3, x1 -> 0xFF00B3D5 (32-bit reversal)
//==================================================
`timescale 1ns/1ps
module tb_custom;

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
        instr_mem[0] = 32'hABCD00B7; // LUI       x1, 0xABCD0      -> x1 = 0xABCD0000
        instr_mem[1] = 32'h0FF08093; // ADDI      x1, x1, 0xFF      -> x1 = 0xABCD00FF
        instr_mem[2] = 32'h0000910B; // POPCOUNT  x2, x1  (custom0) -> 18
        instr_mem[3] = 32'h0000A18B; // BITREV    x3, x1  (custom0) -> 0xFF00B3D5
        instr_mem[4] = 32'h00202023; // SW        x2, 0(x0)         -> Mem[0] = 18
        instr_mem[5] = 32'h00302223; // SW        x3, 4(x0)         -> Mem[1] = 0xFF00B3D5
        instr_mem[6] = 32'h0000006F; // JAL  x0, 0 (halt)
    end

    initial begin
        #500;
        $display("");
        $display("=======================================");
        $display("CUSTOM HALT=%0d", halt);
        $display("Mem[0] = %0d (expected 18, POPCOUNT of 0xABCD00FF)", data_mem[0]);
        $display("Mem[1] = %08h (expected FF00B3D5, BITREV)", data_mem[1]);
        if (halt && (data_mem[0] == 32'd18) && (data_mem[1] == 32'hFF00B3D5))
            $display("CUSTOM PASS");
        else
            $display("CUSTOM FAIL");
        $display("PERF cycle=%0d instret=%0d", perf_cycle, perf_instret);
        $display("=======================================");
        $finish;
    end

endmodule
