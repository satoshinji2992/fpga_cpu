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

    reg [7:0]   log [0:LOG_SIZE-1];
    integer     log_len = 0;
    integer     i, fails;
    wire [7:0]  cap_data;
    wire        cap_valid;

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000)
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

    function integer contains_pong_after_d;
        input integer unused;
        integer ii;
        begin
            contains_pong_after_d = 0;
            for (ii = 0; ii + 8 < log_len; ii = ii + 1)
                if (log[ii] == "P" && log[ii+1] == " " && log[ii+2] == "4" &&
                    log[ii+3] == " " && log[ii+4] == "2" &&
                    log[ii+5] == " " && log[ii+6] == "3" &&
                    log[ii+7] == " " && log[ii+8] == "0")
                    contains_pong_after_d = 1;
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
        send_cmd1("s");
        send_cmd2("m", "1");
        send_cmd1("p");
        send_cmd4("l", "e", "d", "a");
        send_cmd4("p", "o", "n", "g");
        send_cmd1("d");
        send_cmd1("q");

        repeat(WAIT_CYCLES * 10) @(posedge clk);

        if (!contains3("O", "K", " ")) begin
            $display("  missing status output");
            fails = fails + 1;
        end
        if (!contains5("m", "e", "m", "1", "=")) begin
            $display("  missing mem1 output");
            fails = fails + 1;
        end
        if (!contains5("c", "y", "c", "l", "e")) begin
            $display("  missing cycle output");
            fails = fails + 1;
        end
        if (!contains_pong_after_d(0)) begin
            $display("  missing pong state after d");
            fails = fails + 1;
        end
        if (led !== 4'h0) begin
            $display("  LED mismatch after pong score render: led=%h expected 0", led);
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
