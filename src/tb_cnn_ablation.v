//==================================================
// End-to-end CNN program ablation.
//
// Runs the same UART-driven CNN command on two top-level systems:
//   - ENABLE_BP=1: 2-bit BHT branch prediction
//   - ENABLE_BP=0: baseline predict-not-taken
//
// The measured window starts immediately before sending "cnn\n" and ends when
// each CPU has printed "pred 7" over UART.
//==================================================
`timescale 1ns/1ps
module tb_cnn_ablation;
    localparam integer CLKS_PER_BIT = 16;
    localparam integer WAIT_CYCLES  = 20000;
    localparam integer LOG_SIZE     = 8192;

    reg clk = 1'b0;
    reg rst_n;
    reg uart_rx_line = 1'b1;

    wire uart_tx_on;
    wire uart_tx_off;
    wire [3:0] led_on;
    wire [3:0] led_off;
    wire sh_clk_on,sh_cke_on,sh_ncs_on,sh_nwe_on,sh_ncas_on,sh_nras_on;
    wire sl_clk_on,sl_cke_on,sl_ncs_on,sl_nwe_on,sl_ncas_on,sl_nras_on;
    wire [1:0] sh_dqm_on,sh_ba_on,sl_dqm_on,sl_ba_on;
    wire [12:0] sh_a_on,sl_a_on;
    wire [15:0] sh_db_on,sl_db_on;
    wire sh_clk_off,sh_cke_off,sh_ncs_off,sh_nwe_off,sh_ncas_off,sh_nras_off;
    wire sl_clk_off,sl_cke_off,sl_ncs_off,sl_nwe_off,sl_ncas_off,sl_nras_off;
    wire [1:0] sh_dqm_off,sh_ba_off,sl_dqm_off,sl_ba_off;
    wire [12:0] sh_a_off,sl_a_off;
    wire [15:0] sh_db_off,sl_db_off;

    reg [7:0] log_on  [0:LOG_SIZE-1];
    reg [7:0] log_off [0:LOG_SIZE-1];
    integer log_len_on = 0;
    integer log_len_off = 0;
    integer fails = 0;

    wire [7:0] cap_data_on;
    wire [7:0] cap_data_off;
    wire cap_valid_on;
    wire cap_valid_off;

    reg done_on = 1'b0;
    reg done_off = 1'b0;

    reg [31:0] start_cycle_on, start_instret_on, start_branch_on, start_flush_on;
    reg [31:0] start_lus_on, start_bpm_on, start_mdu_on;
    reg [31:0] start_cycle_off, start_instret_off, start_branch_off, start_flush_off;
    reg [31:0] start_lus_off, start_bpm_off, start_mdu_off;

    reg [31:0] end_cycle_on, end_instret_on, end_branch_on, end_flush_on;
    reg [31:0] end_lus_on, end_bpm_on, end_mdu_on;
    reg [31:0] end_cycle_off, end_instret_off, end_branch_off, end_flush_off;
    reg [31:0] end_lus_off, end_bpm_off, end_mdu_off;

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000)
    ) dut_on (
        .clk(clk), .rst_n(rst_n),
        .key1(1'b1), .key2(1'b1), .key3(1'b1), .key4(1'b1),
        .uart_rx(uart_rx_line), .uart_tx(uart_tx_on),
        .led1(led_on[0]), .led2(led_on[1]), .led3(led_on[2]), .led4(led_on[3]),
        .sh_clk(sh_clk_on),.sh_cke(sh_cke_on),.sh_ncs(sh_ncs_on),.sh_nwe(sh_nwe_on),.sh_ncas(sh_ncas_on),.sh_nras(sh_nras_on),
        .sh_dqm(sh_dqm_on),.sh_ba(sh_ba_on),.sh_a(sh_a_on),.sh_db(sh_db_on),
        .sl_clk(sl_clk_on),.sl_cke(sl_cke_on),.sl_ncs(sl_ncs_on),.sl_nwe(sl_nwe_on),.sl_ncas(sl_ncas_on),.sl_nras(sl_nras_on),
        .sl_dqm(sl_dqm_on),.sl_ba(sl_ba_on),.sl_a(sl_a_on),.sl_db(sl_db_on)
    );

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000)
    ) dut_off (
        .clk(clk), .rst_n(rst_n),
        .key1(1'b1), .key2(1'b1), .key3(1'b1), .key4(1'b1),
        .uart_rx(uart_rx_line), .uart_tx(uart_tx_off),
        .led1(led_off[0]), .led2(led_off[1]), .led3(led_off[2]), .led4(led_off[3]),
        .sh_clk(sh_clk_off),.sh_cke(sh_cke_off),.sh_ncs(sh_ncs_off),.sh_nwe(sh_nwe_off),.sh_ncas(sh_ncas_off),.sh_nras(sh_nras_off),
        .sh_dqm(sh_dqm_off),.sh_ba(sh_ba_off),.sh_a(sh_a_off),.sh_db(sh_db_off),
        .sl_clk(sl_clk_off),.sl_cke(sl_cke_off),.sl_ncs(sl_ncs_off),.sl_nwe(sl_nwe_off),.sl_ncas(sl_ncas_off),.sl_nras(sl_nras_off),
        .sl_dqm(sl_dqm_off),.sl_ba(sl_ba_off),.sl_a(sl_a_off),.sl_db(sl_db_off)
    );

    sdram_device_model mem_model_on(.clk(sh_clk_on),.cke(sh_cke_on),.cs_n(sh_ncs_on),.ras_n(sh_nras_on),.cas_n(sh_ncas_on),.we_n(sh_nwe_on),
        .dqm_lo(sl_dqm_on),.dqm_hi(sh_dqm_on),.ba(sh_ba_on),.addr(sh_a_on),.dq_lo(sl_db_on),.dq_hi(sh_db_on));
    sdram_device_model mem_model_off(.clk(sh_clk_off),.cke(sh_cke_off),.cs_n(sh_ncs_off),.ras_n(sh_nras_off),.cas_n(sh_ncas_off),.we_n(sh_nwe_off),
        .dqm_lo(sl_dqm_off),.dqm_hi(sh_dqm_off),.ba(sh_ba_off),.addr(sh_a_off),.dq_lo(sl_db_off),.dq_hi(sh_db_off));

    defparam dut_off.u_cpu.ENABLE_BP = 0;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_capture_on (
        .clk(clk), .rst_n(rst_n), .rx(uart_tx_on), .data(cap_data_on), .valid(cap_valid_on)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_capture_off (
        .clk(clk), .rst_n(rst_n), .rx(uart_tx_off), .data(cap_data_off), .valid(cap_valid_off)
    );

    always #5 clk = ~clk;

    task send_byte;
        input [7:0] b;
        integer k;
        begin
            uart_rx_line = 1'b0;
            repeat(CLKS_PER_BIT) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_line = b[k];
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx_line = 1'b1;
            repeat(CLKS_PER_BIT * 20) @(posedge clk);
        end
    endtask

    task send_row;
        input [8*8-1:0] row;
        integer n;
        begin
            for (n = 7; n >= 0; n = n - 1)
                send_byte(row[n*8 +: 8]);
        end
    endtask

    function integer log_has_pred7_on;
        input integer unused;
        integer ii;
        begin
            log_has_pred7_on = 0;
            for (ii = 0; ii + 5 < log_len_on; ii = ii + 1)
                if (log_on[ii] == "p" && log_on[ii+1] == "r" &&
                    log_on[ii+2] == "e" && log_on[ii+3] == "d" &&
                    log_on[ii+4] == " " && log_on[ii+5] == "7")
                    log_has_pred7_on = 1;
        end
    endfunction

    function integer log_has_pred7_off;
        input integer unused;
        integer ii;
        begin
            log_has_pred7_off = 0;
            for (ii = 0; ii + 5 < log_len_off; ii = ii + 1)
                if (log_off[ii] == "p" && log_off[ii+1] == "r" &&
                    log_off[ii+2] == "e" && log_off[ii+3] == "d" &&
                    log_off[ii+4] == " " && log_off[ii+5] == "7")
                    log_has_pred7_off = 1;
        end
    endfunction

    always @(posedge clk) begin
        if (cap_valid_on && log_len_on < LOG_SIZE) begin
            log_on[log_len_on] = cap_data_on;
            log_len_on = log_len_on + 1;
            if (!done_on && log_has_pred7_on(0)) begin
                done_on <= 1'b1;
                end_cycle_on  <= dut_on.u_cpu.perf_cycle;
                end_instret_on <= dut_on.u_cpu.perf_instret;
                end_branch_on <= dut_on.u_cpu.perf_branch;
                end_flush_on  <= dut_on.u_cpu.perf_flush;
                end_lus_on    <= dut_on.u_cpu.perf_load_use_stall;
                end_bpm_on    <= dut_on.u_cpu.perf_bp_miss;
                end_mdu_on    <= dut_on.u_cpu.perf_mdu_inst;
            end
        end
        if (cap_valid_off && log_len_off < LOG_SIZE) begin
            log_off[log_len_off] = cap_data_off;
            log_len_off = log_len_off + 1;
            if (!done_off && log_has_pred7_off(0)) begin
                done_off <= 1'b1;
                end_cycle_off  <= dut_off.u_cpu.perf_cycle;
                end_instret_off <= dut_off.u_cpu.perf_instret;
                end_branch_off <= dut_off.u_cpu.perf_branch;
                end_flush_off  <= dut_off.u_cpu.perf_flush;
                end_lus_off    <= dut_off.u_cpu.perf_load_use_stall;
                end_bpm_off    <= dut_off.u_cpu.perf_bp_miss;
                end_mdu_off    <= dut_off.u_cpu.perf_mdu_inst;
            end
        end
    end

    initial begin
        #500_000_000;
        $display("CNN_ABLATION FAIL timeout done_on=%0d done_off=%0d log_on=%0d log_off=%0d",
                 done_on, done_off, log_len_on, log_len_off);
        $finish;
    end

    initial begin
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(WAIT_CYCLES) @(posedge clk);

        start_cycle_on   = dut_on.u_cpu.perf_cycle;
        start_instret_on = dut_on.u_cpu.perf_instret;
        start_branch_on  = dut_on.u_cpu.perf_branch;
        start_flush_on   = dut_on.u_cpu.perf_flush;
        start_lus_on     = dut_on.u_cpu.perf_load_use_stall;
        start_bpm_on     = dut_on.u_cpu.perf_bp_miss;
        start_mdu_on     = dut_on.u_cpu.perf_mdu_inst;

        start_cycle_off   = dut_off.u_cpu.perf_cycle;
        start_instret_off = dut_off.u_cpu.perf_instret;
        start_branch_off  = dut_off.u_cpu.perf_branch;
        start_flush_off   = dut_off.u_cpu.perf_flush;
        start_lus_off     = dut_off.u_cpu.perf_load_use_stall;
        start_bpm_off     = dut_off.u_cpu.perf_bp_miss;
        start_mdu_off     = dut_off.u_cpu.perf_mdu_inst;

        send_byte("c");
        send_byte("n");
        send_byte("n");
        send_byte(8'h0A);
        repeat(WAIT_CYCLES) @(posedge clk);

        send_row("00000000");
        send_row("00000000");
        send_row("00111100");
        send_row("00111100");
        send_row("00001100");
        send_row("00011000");
        send_row("00011000");
        send_row("00010000");
        send_byte(8'h0A);

        wait(done_on && done_off);
        repeat(1000) @(posedge clk);

        if (led_on !== 4'h7) begin
            $display("  BP_ON LED mismatch: led=%h expected 7", led_on);
            fails = fails + 1;
        end
        if (led_off !== 4'h7) begin
            $display("  BP_OFF LED mismatch: led=%h expected 7", led_off);
            fails = fails + 1;
        end

        $display("");
        $display("=======================================");
        $display("CNN ABLATION: measured from sending cnn command to receiving pred 7");
        $display("BP_ON  cycle=%0d instret=%0d cpi=%.3f branch=%0d flush=%0d bp_miss=%0d acc=%.2f%% load_use=%0d mdu=%0d log_bytes=%0d",
                 end_cycle_on - start_cycle_on,
                 end_instret_on - start_instret_on,
                 ((end_instret_on - start_instret_on) > 0) ?
                    (1.0 * (end_cycle_on - start_cycle_on) / (end_instret_on - start_instret_on)) : 0.0,
                 end_branch_on - start_branch_on,
                 end_flush_on - start_flush_on,
                 end_bpm_on - start_bpm_on,
                 ((end_branch_on - start_branch_on) > 0) ?
                    (100.0 * ((end_branch_on - start_branch_on) - (end_bpm_on - start_bpm_on)) /
                     (end_branch_on - start_branch_on)) : 0.0,
                 end_lus_on - start_lus_on,
                 end_mdu_on - start_mdu_on,
                 log_len_on);
        $display("BP_OFF cycle=%0d instret=%0d cpi=%.3f branch=%0d flush=%0d bp_miss=%0d acc=%.2f%% load_use=%0d mdu=%0d log_bytes=%0d",
                 end_cycle_off - start_cycle_off,
                 end_instret_off - start_instret_off,
                 ((end_instret_off - start_instret_off) > 0) ?
                    (1.0 * (end_cycle_off - start_cycle_off) / (end_instret_off - start_instret_off)) : 0.0,
                 end_branch_off - start_branch_off,
                 end_flush_off - start_flush_off,
                 end_bpm_off - start_bpm_off,
                 ((end_branch_off - start_branch_off) > 0) ?
                    (100.0 * ((end_branch_off - start_branch_off) - (end_bpm_off - start_bpm_off)) /
                     (end_branch_off - start_branch_off)) : 0.0,
                 end_lus_off - start_lus_off,
                 end_mdu_off - start_mdu_off,
                 log_len_off);
        if (fails == 0) $display("CNN_ABLATION PASS");
        else $display("CNN_ABLATION FAIL (%0d)", fails);
        $display("=======================================");
        $finish;
    end
endmodule
