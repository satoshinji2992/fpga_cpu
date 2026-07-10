//==================================================
// tb_cnn.v - end-to-end UART verification of all ten 8x8 digits.
//
// Each image enters through the real UART receiver. The CPU executes the
// board inference program, prints "pred N", and writes N to the LEDs.
//==================================================
`timescale 1ns/1ps
module tb_cnn;
    localparam integer CLKS_PER_BIT = 16;
    localparam integer READY_CYCLES = 4000;
    localparam integer PRED_TIMEOUT = 200000;
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

    task send_image;
        input integer digit;
        begin
            case (digit)
                0: begin
                    send_row("00111100"); send_row("00100100");
                    send_row("00100100"); send_row("00100100");
                    send_row("00100100"); send_row("00100100");
                    send_row("00111100"); send_row("00000000");
                end
                1: begin
                    send_row("00011000"); send_row("00111000");
                    send_row("00011000"); send_row("00011000");
                    send_row("00011000"); send_row("00011000");
                    send_row("00111100"); send_row("00000000");
                end
                2: begin
                    send_row("00111100"); send_row("00000100");
                    send_row("00000100"); send_row("00011100");
                    send_row("00100000"); send_row("00100000");
                    send_row("00111110"); send_row("00000000");
                end
                3: begin
                    send_row("00111100"); send_row("00000100");
                    send_row("00000100"); send_row("00011100");
                    send_row("00000100"); send_row("00000100");
                    send_row("00111100"); send_row("00000000");
                end
                4: begin
                    send_row("00100100"); send_row("00100100");
                    send_row("00100100"); send_row("00111110");
                    send_row("00000100"); send_row("00000100");
                    send_row("00000100"); send_row("00000000");
                end
                5: begin
                    send_row("00111110"); send_row("00100000");
                    send_row("00100000"); send_row("00111100");
                    send_row("00000100"); send_row("00000100");
                    send_row("00111100"); send_row("00000000");
                end
                6: begin
                    send_row("00111100"); send_row("00100000");
                    send_row("00100000"); send_row("00111100");
                    send_row("00100100"); send_row("00100100");
                    send_row("00111100"); send_row("00000000");
                end
                7: begin
                    send_row("00111110"); send_row("00000100");
                    send_row("00001000"); send_row("00010000");
                    send_row("00010000"); send_row("00100000");
                    send_row("00100000"); send_row("00000000");
                end
                8: begin
                    send_row("00111100"); send_row("00100100");
                    send_row("00100100"); send_row("00111100");
                    send_row("00100100"); send_row("00100100");
                    send_row("00111100"); send_row("00000000");
                end
                9: begin
                    send_row("00111100"); send_row("00100100");
                    send_row("00100100"); send_row("00111110");
                    send_row("00000100"); send_row("00000100");
                    send_row("00111100"); send_row("00000000");
                end
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (cap_valid && log_len < LOG_SIZE) begin
            log[log_len] = cap_data;
            log_len = log_len + 1;
        end
    end

    function integer has_prediction;
        input integer first;
        input integer expected;
        integer ii;
        begin
            has_prediction = 0;
            for (ii = first; ii + 5 < log_len; ii = ii + 1)
                if (log[ii] == "p" && log[ii+1] == "r" && log[ii+2] == "e" &&
                    log[ii+3] == "d" && log[ii+4] == " " &&
                    log[ii+5] == (8'h30 + expected))
                    has_prediction = 1;
        end
    endfunction

    task test_digit;
        input integer digit;
        integer first, cycles;
        begin
            first = log_len;
            send_image(digit);
            send_byte(8'h0A);

            cycles = 0;
            while (!has_prediction(first, digit) && cycles < PRED_TIMEOUT) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (!has_prediction(first, digit)) begin
                $display("digit %0d FAIL: missing pred %0d", digit, digit);
                fails = fails + 1;
            end else if (led !== digit[3:0]) begin
                $display("digit %0d FAIL: LED=%h", digit, led);
                fails = fails + 1;
            end else begin
                $display("digit %0d PASS (%0d cycles)", digit, cycles);
            end
            repeat(READY_CYCLES) @(posedge clk);
        end
    endtask

    initial begin
        #200_000_000;
        $display("CNN FAIL (global timeout; log_len=%0d)", log_len);
        $finish;
    end

    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;
        repeat(20000) @(posedge clk);

        send_byte("c"); send_byte("n"); send_byte("n"); send_byte(8'h0A);
        repeat(READY_CYCLES * 3) @(posedge clk);

        for (i = 0; i < 10; i = i + 1)
            test_digit(i);

        send_byte("q"); send_byte(8'h0A);
        repeat(READY_CYCLES) @(posedge clk);

        $display("captured %0d tx bytes", log_len);
        if (fails == 0)
            $display("CNN ALL-DIGIT PASS (10/10)");
        else
            $display("CNN ALL-DIGIT FAIL (%0d/10 failed)", fails);
        $finish;
    end
endmodule
