//==================================================
// tb_shell.v — end-to-end UART verification of the CPU shell.
//
// Exercises old short commands plus shell-like long commands:
//   h, s, m1, p, led a, pong / d / q
//==================================================
`timescale 1ns/1ps
module tb_shell;
    localparam integer CLKS_PER_BIT = 16;
    localparam integer WAIT_CYCLES  = 20000;
    localparam integer LOG_SIZE     = 4096;

    reg         clk = 1'b0;
    reg         rst_n;
    wire        uart_tx;
    reg         uart_rx_line = 1'b1;
    wire [3:0]  led;
    wire sh_clk,sh_cke,sh_ncs,sh_nwe,sh_ncas,sh_nras;
    wire sl_clk,sl_cke,sl_ncs,sl_nwe,sl_ncas,sl_nras;
    wire [1:0] sh_dqm,sh_ba,sl_dqm,sl_ba;
    wire [12:0] sh_a,sl_a;
    wire [15:0] sh_db,sl_db;

    reg [7:0]   log [0:LOG_SIZE-1];
    integer     log_len = 0;
    integer     i, fails;
    wire [7:0]  cap_data;
    wire        cap_valid;

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000),
        .PONG_TICK_CYCLES(500000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .key1(1'b1), .key2(1'b1), .key3(1'b1), .key4(1'b1),
        .uart_rx(uart_rx_line), .uart_tx(uart_tx),
        .led1(led[0]), .led2(led[1]), .led3(led[2]), .led4(led[3]),
        .sh_clk(sh_clk),.sh_cke(sh_cke),.sh_ncs(sh_ncs),.sh_nwe(sh_nwe),.sh_ncas(sh_ncas),.sh_nras(sh_nras),
        .sh_dqm(sh_dqm),.sh_ba(sh_ba),.sh_a(sh_a),.sh_db(sh_db),
        .sl_clk(sl_clk),.sl_cke(sl_cke),.sl_ncs(sl_ncs),.sl_nwe(sl_nwe),.sl_ncas(sl_ncas),.sl_nras(sl_nras),
        .sl_dqm(sl_dqm),.sl_ba(sl_ba),.sl_a(sl_a),.sl_db(sl_db)
    );
    sdram_device_model mem_model(.clk(sh_clk),.cke(sh_cke),.cs_n(sh_ncs),.ras_n(sh_nras),.cas_n(sh_ncas),.we_n(sh_nwe),
        .dqm_lo(sl_dqm),.dqm_hi(sh_dqm),.ba(sh_ba),.addr(sh_a),.dq_lo(sl_db),.dq_hi(sh_db));

    always #5 clk = ~clk;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_capture_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_tx), .data(cap_data), .valid(cap_valid)
    );

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

    task send_cmd1;
        input [7:0] a;
        begin
            send_byte(a);
            send_byte(8'h0A);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_cmd2;
        input [7:0] a;
        input [7:0] b;
        begin
            send_byte(a);
            send_byte(b);
            send_byte(8'h0A);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_cmd4;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        begin
            send_byte(a);
            send_byte(b);
            send_byte(c);
            send_byte(d);
            send_byte(8'h0A);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_game_key;
        input [7:0] key;
        begin
            send_byte(key);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (cap_valid && log_len < LOG_SIZE) begin
            log[log_len] = cap_data;
            log_len = log_len + 1;
        end
    end

    function integer contains3;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        integer ii;
        begin
            contains3 = 0;
            for (ii = 0; ii + 2 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c)
                    contains3 = 1;
        end
    endfunction

    function integer contains5;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        input [7:0] e;
        integer ii;
        begin
            contains5 = 0;
            for (ii = 0; ii + 4 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c &&
                    log[ii+3] == d && log[ii+4] == e)
                    contains5 = 1;
        end
    endfunction

    function integer has_text;
        input [8*32-1:0] value;
        input integer length;
        integer ii, jj, ok;
        begin
            has_text = 0;
            for (ii = 0; ii + length <= log_len; ii = ii + 1) begin
                ok = 1;
                for (jj = 0; jj < length; jj = jj + 1)
                    if (log[ii+jj] !== value[(length-1-jj)*8 +: 8]) ok = 0;
                if (ok) has_text = 1;
            end
        end
    endfunction

    function integer count_perf_packets;
        input integer unused;
        integer ii;
        begin
            count_perf_packets = 0;
            for (ii = 0; ii + 38 < log_len; ii = ii + 1) begin
                if (log[ii] == 8'hA5 && log[ii+1] == "P" &&
                    log[ii+2] == 8'd36)
                    count_perf_packets = count_perf_packets + 1;
            end
        end
    endfunction

    function integer perf_instret_nontrivial;
        input integer unused;
        integer ii;
        reg [31:0] value;
        begin
            perf_instret_nontrivial = 0;
            for (ii = 0; ii + 38 < log_len; ii = ii + 1) begin
                if (log[ii] == 8'hA5 && log[ii+1] == "P" &&
                    log[ii+2] == 8'd36) begin
                    value = {log[ii+10], log[ii+9], log[ii+8], log[ii+7]};
                    if (value > 32'd100) perf_instret_nontrivial = 1;
                end
            end
        end
    endfunction

    function integer contains_pong_state;
        input [7:0] bx;
        input [7:0] by;
        input [7:0] pad;
        input [7:0] over;
        input [7:0] score;
        input integer unused;
        integer ii;
        begin
            contains_pong_state = 0;
            for (ii = 0; ii + 10 < log_len; ii = ii + 1)
                if (log[ii] == "P" && log[ii+1] == " " && log[ii+2] == bx &&
                    log[ii+3] == " " && log[ii+4] == by &&
                    log[ii+5] == " " && log[ii+6] == pad &&
                    log[ii+7] == " " && log[ii+8] == over &&
                    log[ii+9] == " " && log[ii+10] == score)
                    contains_pong_state = 1;
        end
    endfunction

    initial begin
        #200_000_000;
        $display("SHELL FAIL (timeout; log_len=%0d)", log_len);
        $finish;
    end

    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(WAIT_CYCLES) @(posedge clk);
        send_cmd1("h");
        send_cmd1("v");
        send_cmd1("s");
        send_cmd2("m", "1");
        send_cmd2("m", "9");
        send_cmd1("p");
        send_cmd1("p");
        send_cmd4("l", "e", "d", "a");
        send_cmd4("p", "o", "n", "g");
        send_game_key("a");
        send_game_key("d");
        send_game_key("s");
        send_game_key("s");
        send_game_key("s");
        send_game_key("d");
        send_game_key("d");
        send_game_key("d");
        send_game_key("s");
        send_game_key("s");

        // No key is sent here. One timer IRQ must advance (6,3) to (5,2).
        repeat(1100000) @(posedge clk);
        send_game_key("q");

        repeat(WAIT_CYCLES * 10) @(posedge clk);

        if (!contains5("S", "E", "L", "F", "T")) begin
            $display("  missing startup self-test output");
            fails = fails + 1;
        end
        if (!has_text("SELFTEST PASS", 13)) begin
            $display("  startup self-test did not pass");
            fails = fails + 1;
        end
        if (!contains3("O", "K", " ")) begin
            $display("  missing status output");
            fails = fails + 1;
        end
        if (!contains5("b", "u", "i", "l", "d")) begin
            $display("  missing build identifier");
            fails = fails + 1;
        end
        if (!contains5("m", "e", "m", "1", "=")) begin
            $display("  missing mem1 output");
            fails = fails + 1;
        end
        if (!has_text("mem1=0x00000037", 15)) begin
            $display("  mem1 output is malformed or has the wrong value");
            fails = fails + 1;
        end
        if (!has_text("mem9=0x5aa5c33c", 15)) begin
            $display("  mem9 SDRAM self-test result is malformed or wrong");
            fails = fails + 1;
        end
        if ({dut.data_mem_b3[768],dut.data_mem_b2[768],dut.data_mem_b1[768],dut.data_mem_b0[768]} !== 32'h000000ff ||
            {dut.data_mem_b3[769],dut.data_mem_b2[769],dut.data_mem_b1[769],dut.data_mem_b0[769]} !== 32'h00000037 ||
            {dut.data_mem_b3[770],dut.data_mem_b2[770],dut.data_mem_b1[770],dut.data_mem_b0[770]} !== 32'h13579bdf ||
            {dut.data_mem_b3[771],dut.data_mem_b2[771],dut.data_mem_b1[771],dut.data_mem_b0[771]} !== 32'h0000002a ||
            {dut.data_mem_b3[772],dut.data_mem_b2[772],dut.data_mem_b1[772],dut.data_mem_b0[772]} !== 32'h00020001 ||
            {dut.data_mem_b3[773],dut.data_mem_b2[773],dut.data_mem_b1[773],dut.data_mem_b0[773]} !== 32'h40000000 ||
            {dut.data_mem_b3[774],dut.data_mem_b2[774],dut.data_mem_b1[774],dut.data_mem_b0[774]} !== 32'h40400000 ||
            {dut.data_mem_b3[775],dut.data_mem_b2[775],dut.data_mem_b1[775],dut.data_mem_b0[775]} !== 32'hff00b3d5 ||
            {dut.data_mem_b3[776],dut.data_mem_b2[776],dut.data_mem_b1[776],dut.data_mem_b0[776]} === 32'h00000000 ||
            {dut.data_mem_b3[777],dut.data_mem_b2[777],dut.data_mem_b1[777],dut.data_mem_b0[777]} !== 32'h5aa5c33c ||
            {dut.data_mem_b3[778],dut.data_mem_b2[778],dut.data_mem_b1[778],dut.data_mem_b0[778]} !== 32'h00000000) begin
            $display("  one or more persistent self-test slots are wrong");
            fails = fails + 1;
        end
        if (has_text("FAIL ", 5)) begin
            $display("  startup self-test reported a failure");
            fails = fails + 1;
        end
        if (count_perf_packets(0) < 2) begin
            $display("  expected two complete bounded performance records");
            fails = fails + 1;
        end
        if (!perf_instret_nontrivial(0)) begin
            $display("  performance packet contains an invalid instret value");
            fails = fails + 1;
        end
        if (!contains_pong_state("3", "1", "1", "0", "0", 0)) begin
            $display("  pong a moved the ball (must only move paddle)");
            fails = fails + 1;
        end
        if (!contains_pong_state("4", "2", "2", "0", "0", 0)) begin
            $display("  pong s did not advance the ball correctly");
            fails = fails + 1;
        end
        if (!contains_pong_state("7", "4", "5", "0", "1", 0)) begin
            $display("  pong paddle hit/score trajectory is wrong");
            fails = fails + 1;
        end
        if (!contains_pong_state("6", "3", "5", "0", "1", 0)) begin
            $display("  pong right-wall reflection is wrong");
            fails = fails + 1;
        end
        if (!contains_pong_state("5", "2", "5", "0", "1", 0)) begin
            $display("  pong timer IRQ did not advance the ball automatically");
            fails = fails + 1;
        end
        if (led !== 4'h1) begin
            $display("  LED mismatch after pong score render: led=%h expected 1", led);
            fails = fails + 1;
        end

        if (fails == 0) $display("SHELL PASS");
        else begin
            $display("SHELL FAIL (%0d missing)", fails);
            $write("--- captured log preview ---\n");
            for (i = 0; i < (log_len < 800 ? log_len : 800); i = i + 1)
                $write("%c", log[i]);
            $write("\n--- end preview ---\n");
        end
        $finish;
    end
endmodule
