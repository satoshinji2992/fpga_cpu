`timescale 1ns/1ps
module tb_calculator;
    localparam integer CLKS_PER_BIT = 16;
    localparam integer WAIT_CYCLES = 30000;
    localparam integer LOG_SIZE = 4096;

    reg clk = 1'b0;
    reg rst_n;
    reg uart_rx_line = 1'b1;
    wire uart_tx;
    wire [3:0] led;
    wire sh_clk,sh_cke,sh_ncs,sh_nwe,sh_ncas,sh_nras;
    wire sl_clk,sl_cke,sl_ncs,sl_nwe,sl_ncas,sl_nras;
    wire [1:0] sh_dqm,sh_ba,sl_dqm,sl_ba;
    wire [12:0] sh_a,sl_a;
    wire [15:0] sh_db,sl_db;
    wire [7:0] cap_data;
    wire cap_valid;
    reg [7:0] log [0:LOG_SIZE-1];
    integer log_len = 0;
    integer dump_index;
    integer fails = 0;

    top #(.CLK_FREQ(1600000), .BAUD(100000)) dut (
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
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) capture (
        .clk(clk), .rst_n(rst_n), .rx(uart_tx), .data(cap_data), .valid(cap_valid));

    always #5 clk = ~clk;
    always @(posedge clk) if (cap_valid && log_len < LOG_SIZE) begin
        log[log_len] = cap_data;
        log_len = log_len + 1;
    end

    task send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            uart_rx_line = 1'b0;
            repeat(CLKS_PER_BIT) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_line = value[bit_index];
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx_line = 1'b1;
            repeat(CLKS_PER_BIT * 20) @(posedge clk);
        end
    endtask

    task send_calc_command;
        begin
            send_byte("c"); send_byte("a"); send_byte("l"); send_byte("c"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_expr_precedence;
        begin
            send_byte("2"); send_byte("+"); send_byte("3"); send_byte("*"); send_byte("4"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_expr_parens;
        begin
            send_byte("("); send_byte("1"); send_byte("+"); send_byte("2"); send_byte(")");
            send_byte("*"); send_byte("3"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_expr_division;
        begin
            send_byte("7"); send_byte("/"); send_byte("2"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_expr_negative_decimal;
        begin
            send_byte("-"); send_byte("2"); send_byte("."); send_byte("5");
            send_byte("+"); send_byte("1"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    task send_expr_divzero;
        begin
            send_byte("1"); send_byte("/"); send_byte("0"); send_byte(10);
            repeat(WAIT_CYCLES) @(posedge clk);
        end
    endtask

    function integer has_text;
        input [8*32-1:0] value;
        input integer length;
        integer i, j, match;
        begin
            has_text = 0;
            for (i = 0; i + length <= log_len; i = i + 1) begin
                match = 1;
                for (j = 0; j < length; j = j + 1)
                    if (log[i+j] !== value[(length-1-j)*8 +: 8]) match = 0;
                if (match) has_text = 1;
            end
        end
    endfunction

    initial begin
        #200_000_000;
        $display("CALCULATOR FAIL timeout");
        $finish;
    end

    initial begin
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;
        repeat(WAIT_CYCLES) @(posedge clk);
        send_calc_command;
        send_expr_precedence;
        send_expr_parens;
        send_expr_division;
        send_expr_negative_decimal;
        send_expr_divzero;
        send_byte("q"); send_byte(10);
        repeat(WAIT_CYCLES) @(posedge clk);

        if (!has_text("= 14.000 (0x41600000)", 21)) begin $display("precedence FAIL"); fails = fails + 1; end
        if (!has_text("= 9.000 (0x41100000)", 20)) begin $display("parentheses FAIL"); fails = fails + 1; end
        if (!has_text("= 3.500 (0x40600000)", 20)) begin $display("division FAIL"); fails = fails + 1; end
        if (!has_text("= -1.500 (0xbfc00000)", 21)) begin $display("negative decimal FAIL"); fails = fails + 1; end
        if (!has_text("error", 5)) begin $display("divide-by-zero FAIL"); fails = fails + 1; end
        if (!has_text("cpu> ", 5)) begin $display("exit FAIL"); fails = fails + 1; end

        if (fails == 0) $display("CALCULATOR PASS");
        else begin
            $display("CALCULATOR FAIL (%0d checks), UART log:", fails);
            for (dump_index = 0; dump_index < log_len; dump_index = dump_index + 1)
                $write("%c", log[dump_index]);
            $display("");
        end
        $finish;
    end
endmodule
