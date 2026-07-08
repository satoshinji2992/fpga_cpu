//==================================================
// tb_cnn.v — end-to-end UART verification of CPU 8x8 digit inference.
//
// Sends "cnn\n" and one 8x8 digit template as real UART frames, then checks the
// CPU prints "prediction: 7". Python does not participate in this test.
//==================================================
`timescale 1ns/1ps
module tb_cnn;
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

    task send_row;
        input [8*8-1:0] row;
        integer n;
        begin
            for (n = 7; n >= 0; n = n - 1)
                send_byte(row[n*8 +: 8]);
        end
    endtask

    always @(posedge clk) begin
        if (cap_valid && log_len < LOG_SIZE) begin
            log[log_len] = cap_data;
            log_len = log_len + 1;
        end
    end

    function integer has_prediction7;
        input integer unused;
        integer ii;
        begin
            has_prediction7 = 0;
            for (ii = 0; ii + 12 < log_len; ii = ii + 1)
                if (log[ii] == "p" && log[ii+1] == "r" && log[ii+2] == "e" &&
                    log[ii+3] == "d" && log[ii+4] == "i" && log[ii+5] == "c" &&
                    log[ii+6] == "t" && log[ii+7] == "i" && log[ii+8] == "o" &&
                    log[ii+9] == "n" && log[ii+10] == ":" && log[ii+11] == " " &&
                    log[ii+12] == "7") has_prediction7 = 1;
        end
    endfunction

    initial begin
        #200_000_000;
        $display("CNN FAIL (timeout; log_len=%0d)", log_len);
        $finish;
    end

    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        repeat(WAIT_CYCLES) @(posedge clk);
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
        repeat(WAIT_CYCLES * 60) @(posedge clk);

        $display("captured %0d tx bytes", log_len);
        if (!has_prediction7(0)) begin
            $display("  missing prediction: 7");
            fails = fails + 1;
        end
        if (led !== 4'h7) begin
            $display("  LED mismatch: led=%h expected 7", led);
            fails = fails + 1;
        end

        if (fails == 0) $display("CNN PASS");
        else begin
            $display("CNN FAIL (%0d missing)", fails);
            $write("--- captured log preview ---\n");
            for (i = 0; i < (log_len < 600 ? log_len : 600); i = i + 1)
                $write("%c", log[i]);
            $write("\n--- end preview ---\n");
        end
        $finish;
    end
endmodule
