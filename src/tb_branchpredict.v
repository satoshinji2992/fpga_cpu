//==================================================
// Stage 2 regression: dynamic branch prediction.
//
// Loops 1+2+...+10 (BLT taken 9x, not-taken 1x) on two identical cores:
// one with ENABLE_BP=1 (2-bit BHT), one with ENABLE_BP=0 (predict not-taken).
// Compares CPI, flush count and branch-misprediction rate.
//==================================================
`timescale 1ns/1ps
module tb_branchpredict;

    reg clk, rst_n;

    // ---- ENABLE_BP = 1 instance ----
    reg  [31:0] im_on  [0:255];
    reg  [31:0] dm_on  [0:255];
    wire [31:0] ia_on, id_on, da_on, dw_on, dr_on;
    wire        iv_on, dwen_on, dvalid_on, dready_on, halt_on;
    wire [3:0]  dbe_on;
    wire [31:0] pc_on, pi_on, pb_on, pf_on, pl_on, pm_on;
    riscv_pipeline_core #(.ENABLE_BP(1)) u_on (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(ia_on), .instr_data(id_on), .instr_valid(iv_on),
        .data_addr(da_on), .data_wdata(dw_on), .data_be(dbe_on), .data_we(dwen_on),
        .data_valid(dvalid_on),
        .data_rdata(dr_on), .data_ready(dready_on), .halt(halt_on),
        .perf_cycle(pc_on), .perf_instret(pi_on), .perf_branch(pb_on),
        .perf_flush(pf_on), .perf_load_use_stall(pl_on), .perf_bp_miss(pm_on)
    );
    assign id_on = im_on[ia_on[9:2]];
    assign iv_on = 1'b1;
    assign dr_on = dm_on[da_on[9:2]];
    assign dready_on = 1'b1;
    always @(posedge clk) if (dwen_on) begin
        if (dbe_on[0]) dm_on[da_on[9:2]][7:0]   <= dw_on[7:0];
        if (dbe_on[1]) dm_on[da_on[9:2]][15:8]  <= dw_on[15:8];
        if (dbe_on[2]) dm_on[da_on[9:2]][23:16] <= dw_on[23:16];
        if (dbe_on[3]) dm_on[da_on[9:2]][31:24] <= dw_on[31:24];
    end

    // ---- ENABLE_BP = 0 instance (baseline) ----
    reg  [31:0] im_off [0:255];
    reg  [31:0] dm_off [0:255];
    wire [31:0] ia_off, id_off, da_off, dw_off, dr_off;
    wire        iv_off, dwen_off, dvalid_off, dready_off, halt_off;
    wire [3:0]  dbe_off;
    wire [31:0] pc_off, pi_off, pb_off, pf_off, pl_off, pm_off;
    riscv_pipeline_core #(.ENABLE_BP(0)) u_off (
        .clk(clk), .rst_n(rst_n),
        .instr_addr(ia_off), .instr_data(id_off), .instr_valid(iv_off),
        .data_addr(da_off), .data_wdata(dw_off), .data_be(dbe_off), .data_we(dwen_off),
        .data_valid(dvalid_off),
        .data_rdata(dr_off), .data_ready(dready_off), .halt(halt_off),
        .perf_cycle(pc_off), .perf_instret(pi_off), .perf_branch(pb_off),
        .perf_flush(pf_off), .perf_load_use_stall(pl_off), .perf_bp_miss(pm_off)
    );
    assign id_off = im_off[ia_off[9:2]];
    assign iv_off = 1'b1;
    assign dr_off = dm_off[da_off[9:2]];
    assign dready_off = 1'b1;
    always @(posedge clk) if (dwen_off) begin
        if (dbe_off[0]) dm_off[da_off[9:2]][7:0]   <= dw_off[7:0];
        if (dbe_off[1]) dm_off[da_off[9:2]][15:8]  <= dw_off[15:8];
        if (dbe_off[2]) dm_off[da_off[9:2]][23:16] <= dw_off[23:16];
        if (dbe_off[3]) dm_off[da_off[9:2]][31:24] <= dw_off[31:24];
    end

    initial begin clk = 1'b0; forever #5 clk = ~clk; end
    initial begin rst_n = 1'b0; #20 rst_n = 1'b1; end

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            im_on[i]  = 32'h00000013; dm_on[i]  = 32'h00000000;
            im_off[i] = 32'h00000013; dm_off[i] = 32'h00000000;
        end
        // sum = 1+2+...+10 via counted loop. BLT taken 9x, not-taken 1x.
        im_on[0]=32'h00000093; im_off[0]=32'h00000093; // ADDI x1,x0,0      (sum)
        im_on[1]=32'h00100113; im_off[1]=32'h00100113; // ADDI x2,x0,1      (i)
        im_on[2]=32'h00B00193; im_off[2]=32'h00B00193; // ADDI x3,x0,11     (bound)
        im_on[3]=32'h002080B3; im_off[3]=32'h002080B3; // ADD  x1,x1,x2     (loop:)
        im_on[4]=32'h00110113; im_off[4]=32'h00110113; // ADDI x2,x2,1
        im_on[5]=32'hFE314CE3; im_off[5]=32'hFE314CE3; // BLT  x2,x3,-8     (-> loop)
        im_on[6]=32'h00102023; im_off[6]=32'h00102023; // SW   x1,0(x0)     -> Mem[0]=55
        im_on[7]=32'h0000006F; im_off[7]=32'h0000006F; // JAL  x0,0 (halt)
    end

    real cpi_on, cpi_off, acc_on;
    initial begin
        #10000;
        cpi_on  = (pi_on  > 0) ? (1.0 * pc_on  / pi_on)  : 0.0;
        cpi_off = (pi_off > 0) ? (1.0 * pc_off / pi_off) : 0.0;
        acc_on  = (pb_on  > 0) ? (100.0 * (pb_on - pm_on) / pb_on) : 0.0;
        $display("");
        $display("=======================================");
        $display("PREDICT  (ENABLE_BP=1): halt=%0d Mem[0]=%0d (expected 55)", halt_on,  dm_on[0]);
        $display("  PERF cycle=%0d instret=%0d cpi=%.2f branch=%0d flush=%0d bp_miss=%0d acc=%.1f%%",
                 pc_on, pi_on, cpi_on, pb_on, pf_on, pm_on, acc_on);
        $display("BASELINE (ENABLE_BP=0): halt=%0d Mem[0]=%0d (expected 55)", halt_off, dm_off[0]);
        $display("  PERF cycle=%0d instret=%0d cpi=%.2f branch=%0d flush=%0d bp_miss=%0d",
                 pc_off, pi_off, cpi_off, pb_off, pf_off, pm_off);
        if (halt_on && halt_off && (dm_on[0] == 32'd55) && (dm_off[0] == 32'd55))
            $display("BRANCHPREDICT PASS");
        else
            $display("BRANCHPREDICT FAIL");
        $display("=======================================");
        $finish;
    end

endmodule
