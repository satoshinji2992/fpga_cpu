//==================================================
// Comprehensive CPU feature regression.
//
// Covers:
//   RV32I ALU/logic/shift/compare
//   load/store and byte writes
//   load-use hazard stall
//   branch loop + BHT predictor counters
//   RV32M MUL/DIV/REM
//   custom-0 POPCOUNT/BITREVERSE
//   RDCYCLE CSR read
//   ECALL halt
//
// Floating point is intentionally absent: this CPU does not implement F/D.
//==================================================
`timescale 1ns/1ps
module tb_all_features;

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
            instr_mem[i] = 32'h00000013;
            data_mem[i]  = 32'h00000000;
        end

        instr_mem[0]  = 32'h00700093; // ADDI x1,  x0, 7
        instr_mem[1]  = 32'h00600113; // ADDI x2,  x0, 6
        instr_mem[2]  = 32'h022081B3; // MUL  x3,  x1, x2
        instr_mem[3]  = 32'h0220C233; // DIV  x4,  x1, x2
        instr_mem[4]  = 32'h0220E2B3; // REM  x5,  x1, x2
        instr_mem[5]  = 32'h00302023; // SW   x3,  0(x0)
        instr_mem[6]  = 32'h00402223; // SW   x4,  4(x0)
        instr_mem[7]  = 32'h00502423; // SW   x5,  8(x0)
        instr_mem[8]  = 32'hABCD0337; // LUI  x6,  0xABCD0
        instr_mem[9]  = 32'h0FF30313; // ADDI x6,  x6, 0x0FF
        instr_mem[10] = 32'h0003138B; // POPCOUNT x7, x6
        instr_mem[11] = 32'h0003240B; // BITREV   x8, x6
        instr_mem[12] = 32'h00702623; // SW   x7,  12(x0)
        instr_mem[13] = 32'h00802823; // SW   x8,  16(x0)
        instr_mem[14] = 32'h00000493; // ADDI x9,  x0, 0
        instr_mem[15] = 32'h00100513; // ADDI x10, x0, 1
        instr_mem[16] = 32'h00B00593; // ADDI x11, x0, 11
        instr_mem[17] = 32'h00A484B3; // ADD  x9,  x9, x10
        instr_mem[18] = 32'h00150513; // ADDI x10, x10, 1
        instr_mem[19] = 32'hFEB54CE3; // BLT  x10, x11, -8
        instr_mem[20] = 32'h00902A23; // SW   x9,  20(x0)
        instr_mem[21] = 32'h01200613; // ADDI x12, x0, 0x12
        instr_mem[22] = 32'h00C00CA3; // SB   x12, 25(x0)
        instr_mem[23] = 32'hF8000693; // ADDI x13, x0, -128
        instr_mem[24] = 32'h00D00D23; // SB   x13, 26(x0)
        instr_mem[25] = 32'h03400713; // ADDI x14, x0, 0x34
        instr_mem[26] = 32'h00E00DA3; // SB   x14, 27(x0)
        instr_mem[27] = 32'h01802783; // LW   x15, 24(x0)
        instr_mem[28] = 32'h00F02C23; // SW   x15, 24(x0)
        instr_mem[29] = 32'hC0002873; // RDCYCLE x16
        instr_mem[30] = 32'h01002E23; // SW   x16, 28(x0)
        instr_mem[31] = 32'h00002883; // LW   x17, 0(x0)
        instr_mem[32] = 32'h00188913; // ADDI x18, x17, 1
        instr_mem[33] = 32'h03202023; // SW   x18, 32(x0)
        instr_mem[34] = 32'h00F00993; // ADDI x19, x0, 0x0F
        instr_mem[35] = 32'h0F000A13; // ADDI x20, x0, 0x0F0
        instr_mem[36] = 32'h0149EAB3; // OR   x21, x19, x20
        instr_mem[37] = 32'h0AAAFB13; // ANDI x22, x21, 0x0AA
        instr_mem[38] = 32'h055B4B93; // XORI x23, x22, 0x055
        instr_mem[39] = 32'h001B9C13; // SLLI x24, x23, 1
        instr_mem[40] = 32'h001C5C93; // SRLI x25, x24, 1
        instr_mem[41] = 32'h03902223; // SW   x25, 36(x0)
        instr_mem[42] = 32'h0020AD33; // SLT  x26, x1, x2
        instr_mem[43] = 32'h00113DB3; // SLTU x27, x2, x1
        instr_mem[44] = 32'h01BD0E33; // ADD  x28, x26, x27
        instr_mem[45] = 32'h03C02423; // SW   x28, 40(x0)
        instr_mem[46] = 32'h00000073; // ECALL
    end

    initial begin
        #8000;
        $display("");
        $display("=======================================");
        $display("ALL FEATURES HALT=%0d", halt);
        $display("Mem[0]  = %0d (expected 42, MUL)", data_mem[0]);
        $display("Mem[1]  = %0d (expected 1, DIV)", data_mem[1]);
        $display("Mem[2]  = %0d (expected 1, REM)", data_mem[2]);
        $display("Mem[3]  = %0d (expected 18, POPCOUNT)", data_mem[3]);
        $display("Mem[4]  = %08h (expected FF00B3D5, BITREV)", data_mem[4]);
        $display("Mem[5]  = %0d (expected 55, branch loop sum)", data_mem[5]);
        $display("Mem[6]  = %08h (expected 34801200, byte stores)", data_mem[6]);
        $display("Mem[7]  = %0d (RDCYCLE, must be > 0)", data_mem[7]);
        $display("Mem[8]  = %0d (expected 43, load-use)", data_mem[8]);
        $display("Mem[9]  = %0d (expected 255, logic/shift)", data_mem[9]);
        $display("Mem[10] = %0d (expected 1, compare)", data_mem[10]);
        if (halt &&
            data_mem[0]  == 32'd42 &&
            data_mem[1]  == 32'd1 &&
            data_mem[2]  == 32'd1 &&
            data_mem[3]  == 32'd18 &&
            data_mem[4]  == 32'hFF00B3D5 &&
            data_mem[5]  == 32'd55 &&
            data_mem[6]  == 32'h34801200 &&
            data_mem[7]  >  32'd0 &&
            data_mem[8]  == 32'd43 &&
            data_mem[9]  == 32'd255 &&
            data_mem[10] == 32'd1)
            $display("ALL FEATURES PASS");
        else
            $display("ALL FEATURES FAIL");
        $display("PERF cycle=%0d instret=%0d branch=%0d flush=%0d load_use=%0d bp_miss=%0d mdu=%0d",
                 perf_cycle, perf_instret, perf_branch, perf_flush, perf_lus, perf_bpm, perf_mdu);
        $display("=======================================");
        $finish;
    end

endmodule
