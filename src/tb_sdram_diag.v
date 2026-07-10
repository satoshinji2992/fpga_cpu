`timescale 1ns/1ps
module tb_sdram_diag;
    localparam integer CLKS_PER_BIT = 16;
    localparam integer WAIT_CYCLES  = 70000;
    localparam integer LOG_SIZE     = 16384;

    reg         clk = 1'b0;
    reg         rst_n;
    wire        uart_tx;
    reg         uart_rx_line = 1'b1;
    wire [3:0]  led;

    reg [7:0]   log [0:LOG_SIZE-1];
    integer     log_len = 0;
    integer     i, fails;
    wire [7:0]  cap_data;
    wire        cap_valid;

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000),
        .USE_SDRAM_WINDOW(1),
        .SDRAM_LATENCY(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .key1(1'b1), .key2(1'b1), .key3(1'b1), .key4(1'b1),
        .uart_rx(uart_rx_line), .uart_tx(uart_tx),
        .led1(led[0]), .led2(led[1]), .led3(led[2]), .led4(led[3])
    );

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

    always @(posedge clk) begin
        if (cap_valid && log_len < LOG_SIZE) begin
            log[log_len] = cap_data;
            log_len = log_len + 1;
        end
    end

    function integer contains7;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        input [7:0] e;
        input [7:0] f;
        input [7:0] g;
        integer ii;
        begin
            contains7 = 0;
            for (ii = 0; ii + 6 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c &&
                    log[ii+3] == d && log[ii+4] == e && log[ii+5] == f &&
                    log[ii+6] == g)
                    contains7 = 1;
        end
    endfunction

    function integer contains8;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        input [7:0] e;
        input [7:0] f;
        input [7:0] g;
        input [7:0] h;
        integer ii;
        begin
            contains8 = 0;
            for (ii = 0; ii + 7 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c &&
                    log[ii+3] == d && log[ii+4] == e && log[ii+5] == f &&
                    log[ii+6] == g && log[ii+7] == h)
                    contains8 = 1;
        end
    endfunction

    function integer contains10;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        input [7:0] e;
        input [7:0] f;
        input [7:0] g;
        input [7:0] h;
        input [7:0] i0;
        input [7:0] j;
        integer ii;
        begin
            contains10 = 0;
            for (ii = 0; ii + 9 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c &&
                    log[ii+3] == d && log[ii+4] == e && log[ii+5] == f &&
                    log[ii+6] == g && log[ii+7] == h && log[ii+8] == i0 &&
                    log[ii+9] == j)
                    contains10 = 1;
        end
    endfunction

    function integer contains12;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        input [7:0] e;
        input [7:0] f;
        input [7:0] g;
        input [7:0] h;
        input [7:0] i0;
        input [7:0] j;
        input [7:0] k;
        input [7:0] l;
        integer ii;
        begin
            contains12 = 0;
            for (ii = 0; ii + 11 < log_len; ii = ii + 1)
                if (log[ii] == a && log[ii+1] == b && log[ii+2] == c &&
                    log[ii+3] == d && log[ii+4] == e && log[ii+5] == f &&
                    log[ii+6] == g && log[ii+7] == h && log[ii+8] == i0 &&
                    log[ii+9] == j && log[ii+10] == k && log[ii+11] == l)
                    contains12 = 1;
        end
    endfunction

    initial begin
        #600_000_000;
        $display("SDRAM DIAG FAIL (timeout; log_len=%0d)", log_len);
        $finish;
    end

    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(WAIT_CYCLES) @(posedge clk);
        send_cmd1("h");
        send_cmd1("w");
        send_cmd1("r");
        send_cmd1("i");
        send_cmd1("c");
        send_cmd1("t");
        send_cmd1("l");
        send_cmd1("q");

        repeat(WAIT_CYCLES * 2) @(posedge clk);

        if (!contains7("s", "d", "r", "a", "m", ">", " ")) begin
            $display("  missing sdram prompt");
            fails = fails + 1;
        end
        if (!contains12("d", "e", "m", "o", " ", "w", "r", "i", "t", "t", "e", "n")) begin
            $display("  missing demo written ack");
            fails = fails + 1;
        end
        if (!contains8("1", "2", "3", "4", "5", "6", "7", "8")) begin
            $display("  missing dump value 12345678");
            fails = fails + 1;
        end
        if (!contains10("C", "H", "E", "C", "K", " ", "P", "A", "S", "S")) begin
            $display("  missing CHECK PASS");
            fails = fails + 1;
        end
        if (!contains10("S", "M", "O", "K", "E", " ", "P", "A", "S", "S")) begin
            $display("  missing SMOKE PASS");
            fails = fails + 1;
        end
        if (!contains10("W", "A", "L", "K", "1", " ", "P", "A", "S", "S")) begin
            $display("  missing WALK1 PASS");
            fails = fails + 1;
        end

        if ({dut.sdram_mem_b3[0], dut.sdram_mem_b2[0], dut.sdram_mem_b1[0], dut.sdram_mem_b0[0]} !== 32'h80000000) begin
            $display("  SDRAM word0 mismatch: %08h expected 80000000",
                     {dut.sdram_mem_b3[0], dut.sdram_mem_b2[0], dut.sdram_mem_b1[0], dut.sdram_mem_b0[0]});
            fails = fails + 1;
        end
        if ({dut.sdram_mem_b3[1], dut.sdram_mem_b2[1], dut.sdram_mem_b1[1], dut.sdram_mem_b0[1]} !== 32'hA5A5A5A5) begin
            $display("  SDRAM word1 mismatch: %08h expected A5A5A5A5",
                     {dut.sdram_mem_b3[1], dut.sdram_mem_b2[1], dut.sdram_mem_b1[1], dut.sdram_mem_b0[1]});
            fails = fails + 1;
        end
        if ({dut.sdram_mem_b3[2], dut.sdram_mem_b2[2], dut.sdram_mem_b1[2], dut.sdram_mem_b0[2]} !== 32'h5A5A5A5A) begin
            $display("  SDRAM word2 mismatch: %08h expected 5A5A5A5A",
                     {dut.sdram_mem_b3[2], dut.sdram_mem_b2[2], dut.sdram_mem_b1[2], dut.sdram_mem_b0[2]});
            fails = fails + 1;
        end
        if (led !== 4'h5) begin
            $display("  LED mismatch: led=%h expected 5", led);
            fails = fails + 1;
        end

        if (fails == 0) $display("SDRAM DIAG PASS");
        else begin
            $display("SDRAM DIAG FAIL (%0d missing)", fails);
            $write("--- captured log preview ---\n");
            for (i = 0; i < (log_len < 1200 ? log_len : 1200); i = i + 1)
                $write("%c", log[i]);
            $write("\n--- end preview ---\n");
        end
        $finish;
    end
endmodule
