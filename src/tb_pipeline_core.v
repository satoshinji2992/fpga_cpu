//==================================================
// Five-stage pipeline CPU testbench
//==================================================
`timescale 1ns/1ps
module tb_pipeline_core;

    reg clk;
    reg rst_n;

    reg  [31:0] instr_mem [0:255];
    reg  [31:0] data_mem  [0:255];

    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_valid;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire        data_we;
    wire        data_valid;
    wire [31:0] data_rdata;
    wire        data_ready;
    wire        halt;
    wire [31:0] perf_cycle;
    wire [31:0] perf_instret;
    wire [31:0] perf_branch;
    wire [31:0] perf_flush;

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
        .data_valid (data_valid),
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        .halt       (halt),
        .perf_cycle   (perf_cycle),
        .perf_instret (perf_instret),
        .perf_branch  (perf_branch),
        .perf_flush   (perf_flush)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #20 rst_n = 1'b1;
    end

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
            $display("[%0t] PIPE WRITE addr=%08h data=%08h be=%b",
                     $time, data_addr, data_wdata, data_be);
        end
    end

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            instr_mem[i] = 32'h00000013;
            data_mem[i]  = 32'h00000000;
        end

        instr_mem[0]  = 32'hFFF00093; // ADDI x1,  x0, -1
        instr_mem[1]  = 32'h01200113; // ADDI x2,  x0, 0x12
        instr_mem[2]  = 32'h002000A3; // SB   x2,  1(x0)
        instr_mem[3]  = 32'h00100183; // LB   x3,  1(x0)
        instr_mem[4]  = 32'h00104203; // LBU  x4,  1(x0)
        instr_mem[5]  = 32'hF8000293; // ADDI x5,  x0, -128
        instr_mem[6]  = 32'h00500123; // SB   x5,  2(x0)
        instr_mem[7]  = 32'h00200303; // LB   x6,  2(x0)
        instr_mem[8]  = 32'h00204383; // LBU  x7,  2(x0)
        instr_mem[9]  = 32'h03400413; // ADDI x8,  x0, 0x34
        instr_mem[10] = 32'h008001A3; // SB   x8,  3(x0)
        instr_mem[11] = 32'hFFE00513; // ADDI x10, x0, -2
        instr_mem[12] = 32'h00A01223; // SH   x10, 4(x0)
        instr_mem[13] = 32'h00401583; // LH   x11, 4(x0)
        instr_mem[14] = 32'h00405603; // LHU  x12, 4(x0)
        instr_mem[15] = 32'h00500693; // ADDI x13, x0, 5
        instr_mem[16] = 32'h00500713; // ADDI x14, x0, 5
        instr_mem[17] = 32'h00E68463; // BEQ  x13, x14, +8
        instr_mem[18] = 32'h00100793; // ADDI x15, x0, 1 (skipped)
        instr_mem[19] = 32'h00200793; // ADDI x15, x0, 2
        instr_mem[20] = 32'h00105463; // BGE  x0,  x1,  +8
        instr_mem[21] = 32'h00300793; // ADDI x15, x0, 3 (skipped)
        instr_mem[22] = 32'h00F02423; // SW   x15, 8(x0)
        instr_mem[23] = 32'h0000006F; // JAL  x0,  0 (halt)
    end

    always @(posedge clk) begin
        if (rst_n)
            $display("[%0t] PIPE PC=%08h INSTR=%08h", $time, instr_addr, instr_data);
    end

    initial begin
        #2000;
        $display("");
        $display("=======================================");
        $display("PIPELINE CPU HALT=%0d at %0t", halt, $time);
        $display("Mem[0] = %08h (expected 34801200)", data_mem[0]);
        $display("Mem[1] = %08h (expected 0000fffe)", data_mem[1]);
        $display("Mem[2] = %0d (expected 2)", data_mem[2]);
        if (halt &&
            (data_mem[0] == 32'h34801200) &&
            (data_mem[1] == 32'h0000FFFE) &&
            (data_mem[2] == 32'd2))
            $display("PIPELINE PASS");
        else
            $display("PIPELINE FAIL");
        $display("PERF cycle=%0d instret=%0d branch=%0d flush=%0d",
                 perf_cycle, perf_instret, perf_branch, perf_flush);
        $display("=======================================");
        $finish;
    end

endmodule
