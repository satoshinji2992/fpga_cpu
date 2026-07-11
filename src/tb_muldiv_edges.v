`timescale 1ns/1ps
module tb_muldiv_edges;
    reg clk = 1'b0, rst_n = 1'b0;
    wire [31:0] instr_addr, data_addr, data_wdata;
    wire [3:0] data_be;
    wire data_valid, data_we, halt;
    reg [31:0] instr_mem [0:63];
    reg [31:0] data_mem [0:63];
    integer i;

    riscv_pipeline_core dut (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(instr_addr), .instr_data(instr_mem[instr_addr[7:2]]), .instr_valid(1'b1),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be),
        .data_valid(data_valid), .data_we(data_we), .data_rdata(data_mem[data_addr[7:2]]),
        .data_ready(1'b1), .irq_external(1'b0), .halt(halt),
        .perf_cycle(), .perf_instret(), .perf_branch(), .perf_flush(),
        .perf_load_use_stall(), .perf_bp_miss(), .perf_mdu_inst()
    );

    always #5 clk = ~clk;
    always @(posedge clk) if (data_valid && data_we) begin
        if (data_be[0]) data_mem[data_addr[7:2]][7:0] <= data_wdata[7:0];
        if (data_be[1]) data_mem[data_addr[7:2]][15:8] <= data_wdata[15:8];
        if (data_be[2]) data_mem[data_addr[7:2]][23:16] <= data_wdata[23:16];
        if (data_be[3]) data_mem[data_addr[7:2]][31:24] <= data_wdata[31:24];
    end

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            instr_mem[i] = 32'h00000013;
            data_mem[i] = 32'd0;
        end
        instr_mem[0] = 32'hFF900093; instr_mem[1] = 32'h00300113;
        instr_mem[2] = 32'h022081B3; instr_mem[3] = 32'h02209233;
        instr_mem[4] = 32'h0220A2B3; instr_mem[5] = 32'h0220B333;
        instr_mem[6] = 32'h0220C3B3; instr_mem[7] = 32'h0220D433;
        instr_mem[8] = 32'h0220E4B3; instr_mem[9] = 32'h0220F533;
        instr_mem[10] = 32'h00000593; instr_mem[11] = 32'h02B0C633;
        instr_mem[12] = 32'h02B0E6B3; instr_mem[13] = 32'h80000737;
        instr_mem[14] = 32'h00070713; instr_mem[15] = 32'hFFF00793;
        instr_mem[16] = 32'h02F74833; instr_mem[17] = 32'h02F768B3;
        instr_mem[18] = 32'h00302023; instr_mem[19] = 32'h00402223;
        instr_mem[20] = 32'h00502423; instr_mem[21] = 32'h00602623;
        instr_mem[22] = 32'h00702823; instr_mem[23] = 32'h00802A23;
        instr_mem[24] = 32'h00902C23; instr_mem[25] = 32'h00A02E23;
        instr_mem[26] = 32'h02C02023; instr_mem[27] = 32'h02D02223;
        instr_mem[28] = 32'h03002423; instr_mem[29] = 32'h03102623;
        instr_mem[30] = 32'h00000073;

        repeat (3) @(posedge clk); rst_n = 1'b1;
        wait(halt); repeat (5) @(posedge clk);
        if (data_mem[0]  === 32'hFFFFFFEB && // MUL -7*3
            data_mem[1]  === 32'hFFFFFFFF && // MULH signed*signed
            data_mem[2]  === 32'hFFFFFFFF && // MULHSU signed*unsigned
            data_mem[3]  === 32'h00000002 && // MULHU unsigned*unsigned
            data_mem[4]  === 32'hFFFFFFFE && // DIV -7/3
            data_mem[5]  === 32'h55555553 && // DIVU
            data_mem[6]  === 32'hFFFFFFFF && // REM -7/3
            data_mem[7]  === 32'h00000000 && // REMU
            data_mem[8]  === 32'hFFFFFFFF && // DIV by zero
            data_mem[9]  === 32'hFFFFFFF9 && // REM by zero
            data_mem[10] === 32'h80000000 && // signed overflow quotient
            data_mem[11] === 32'h00000000) begin
            $display("MULDIV EDGES PASS");
        end else begin
            $display("MULDIV EDGES FAIL %08h %08h %08h %08h %08h %08h %08h %08h %08h %08h %08h %08h",
                     data_mem[0], data_mem[1], data_mem[2], data_mem[3],
                     data_mem[4], data_mem[5], data_mem[6], data_mem[7],
                     data_mem[8], data_mem[9], data_mem[10], data_mem[11]);
        end
        $finish;
    end

    initial begin
        #200000; $display("MULDIV EDGES FAIL timeout"); $finish;
    end
endmodule
