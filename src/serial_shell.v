//==================================================
// Lightweight UART shell for the FPGA CPU system.
//
// The FPGA keeps CPU status and a tiny Pong game state machine. The PC
// Python client renders the board, which keeps this module small enough
// for XC6SLX9.
//
// Commands:
//   h - help
//   s - CPU status
//   0/1/2 - print Mem[0..2]
//   g - get Pong state
//   a/l - move paddle left and step
//   d/r - move paddle right and step
//   x - step
//   n - reset Pong
//   p - performance metrics
//==================================================
module serial_shell #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD     = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,
    output wire        tx,
    input  wire        halt,
    input  wire        test_pass,
    input  wire [31:0] mem0,
    input  wire [31:0] mem1,
    input  wire [31:0] mem2
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk(clk), .rst_n(rst_n), .rx(rx), .data(rx_data), .valid(rx_valid)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data), .tx(tx), .busy(tx_busy)
    );

    localparam RESP_BANNER  = 4'd0;
    localparam RESP_HELP    = 4'd1;
    localparam RESP_STATUS  = 4'd2;
    localparam RESP_MEM     = 4'd3;
    localparam RESP_PONG    = 4'd4;
    localparam RESP_RESET   = 4'd5;
    localparam RESP_OVER    = 4'd6;
    localparam RESP_METRICS = 4'd7;
    localparam RESP_BAD     = 4'd8;
    localparam RESP_PROMPT  = 4'd9;

    localparam ST_IDLE = 2'd0;
    localparam ST_SEND = 2'd1;
    localparam ST_WAIT = 2'd2;

    reg [1:0]  state;
    reg        wait_seen_busy;
    reg        boot_sent;
    reg [3:0]  resp;
    reg [5:0]  pos;
    reg [31:0] selected_mem;
    reg [1:0]  mem_id;

    reg [2:0] ball_x;
    reg [2:0] ball_y;
    reg       ball_dx;       // 0:left, 1:right
    reg       ball_dy;       // 0:up,   1:down
    reg [2:0] paddle_x;      // left edge, width 3
    reg       pong_over;

    reg [2:0] next_x;
    reg [2:0] next_y;
    reg       next_dx;
    reg       next_dy;
    reg       miss;

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            hex_char = (nibble < 4'd10) ? (8'h30 + nibble) : (8'h41 + nibble - 4'd10);
        end
    endfunction

    function [7:0] digit;
        input [2:0] value;
        begin
            digit = 8'h30 + {5'b0, value};
        end
    endfunction

    function [5:0] resp_len;
        input [3:0] r;
        begin
            case (r)
                RESP_BANNER:  resp_len = 6'd34; // "\r\nRV32I pipe+icache shell\r\ncpu> "
                RESP_HELP:    resp_len = 6'd47; // "h s 0 1 2 g a/d/x n p; q quits host\r\ncpu> "
                RESP_STATUS:  resp_len = 6'd14; // "PASS halt=1\r\n" or "FAIL halt=0\r\n"
                RESP_MEM:     resp_len = 6'd17; // "memX=0x12345678\r\n"
                RESP_PONG:    resp_len = 6'd13; // "P Bxy Pp Oo\r\n"
                RESP_RESET:   resp_len = 6'd12; // "pong reset\r\n"
                RESP_OVER:    resp_len = 6'd37; // "pong over\r\nfreq=50MHz CPI=1 T=50MIPS\r\n"
                RESP_METRICS: resp_len = 6'd26; // "freq=50MHz CPI=1 T=50MIPS\r\n"
                RESP_BAD:     resp_len = 6'd7;  // "?\r\ncpu> "
                RESP_PROMPT:  resp_len = 6'd5;  // "cpu> "
                default:      resp_len = 6'd0;
            endcase
        end
    endfunction

    function [7:0] metric_char;
        input [5:0] p;
        begin
            metric_char = 8'h20;
            case (p)
                0: metric_char="f"; 1: metric_char="r"; 2: metric_char="e"; 3: metric_char="q";
                4: metric_char="="; 5: metric_char="5"; 6: metric_char="0"; 7: metric_char="M";
                8: metric_char="H"; 9: metric_char="z"; 10: metric_char=" "; 11: metric_char="C";
                12: metric_char="P"; 13: metric_char="I"; 14: metric_char="="; 15: metric_char="1";
                16: metric_char=" "; 17: metric_char="T"; 18: metric_char="="; 19: metric_char="5";
                20: metric_char="0"; 21: metric_char="M"; 22: metric_char="I"; 23: metric_char="P";
                24: metric_char=8'h0d; 25: metric_char=8'h0a;
            endcase
        end
    endfunction

    function [7:0] response_char;
        input [3:0] r;
        input [5:0] p;
        begin
            response_char = 8'h20;
            case (r)
                RESP_BANNER: begin
                    case (p)
                        0: response_char=8'h0d; 1: response_char=8'h0a; 2: response_char="R"; 3: response_char="V";
                        4: response_char="3"; 5: response_char="2"; 6: response_char="I"; 7: response_char=" ";
                        8: response_char="p"; 9: response_char="i"; 10: response_char="p"; 11: response_char="e";
                        12: response_char="+"; 13: response_char="i"; 14: response_char="c"; 15: response_char="a";
                        16: response_char="c"; 17: response_char="h"; 18: response_char="e"; 19: response_char=" ";
                        20: response_char="s"; 21: response_char="h"; 22: response_char="e"; 23: response_char="l";
                        24: response_char="l"; 25: response_char=8'h0d; 26: response_char=8'h0a; 27: response_char="c";
                        28: response_char="p"; 29: response_char="u"; 30: response_char=">"; 31: response_char=" ";
                    endcase
                end
                RESP_HELP: begin
                    case (p)
                        0: response_char="h"; 1: response_char=" "; 2: response_char="s"; 3: response_char=" ";
                        4: response_char="0"; 5: response_char=" "; 6: response_char="1"; 7: response_char=" ";
                        8: response_char="2"; 9: response_char=" "; 10: response_char="g"; 11: response_char=" ";
                        12: response_char="a"; 13: response_char="/"; 14: response_char="d"; 15: response_char="/";
                        16: response_char="x"; 17: response_char=" "; 18: response_char="n"; 19: response_char=" ";
                        20: response_char="p"; 21: response_char=";"; 22: response_char=" "; 23: response_char="q";
                        24: response_char=" "; 25: response_char="q"; 26: response_char="u"; 27: response_char="i";
                        28: response_char="t"; 29: response_char="s"; 30: response_char=" "; 31: response_char="h";
                        32: response_char="o"; 33: response_char="s"; 34: response_char="t"; 35: response_char=8'h0d;
                        36: response_char=8'h0a; 37: response_char="c"; 38: response_char="p"; 39: response_char="u";
                        40: response_char=">"; 41: response_char=" ";
                    endcase
                end
                RESP_STATUS: begin
                    if (test_pass) begin
                        case (p)
                            0: response_char="P"; 1: response_char="A"; 2: response_char="S"; 3: response_char="S";
                            4: response_char=" "; 5: response_char="h"; 6: response_char="a"; 7: response_char="l";
                            8: response_char="t"; 9: response_char="="; 10: response_char="1"; 11: response_char=8'h0d;
                            12: response_char=8'h0a; 13: response_char=" ";
                        endcase
                    end else begin
                        case (p)
                            0: response_char="F"; 1: response_char="A"; 2: response_char="I"; 3: response_char="L";
                            4: response_char=" "; 5: response_char="h"; 6: response_char="a"; 7: response_char="l";
                            8: response_char="t"; 9: response_char="="; 10: response_char=halt ? "1" : "0"; 11: response_char=8'h0d;
                            12: response_char=8'h0a; 13: response_char=" ";
                        endcase
                    end
                end
                RESP_MEM: begin
                    case (p)
                        0: response_char="m"; 1: response_char="e"; 2: response_char="m"; 3: response_char=8'h30 + {6'b0, mem_id};
                        4: response_char="="; 5: response_char="0"; 6: response_char="x";
                        7: response_char=hex_char(selected_mem[31:28]);
                        8: response_char=hex_char(selected_mem[27:24]);
                        9: response_char=hex_char(selected_mem[23:20]);
                        10: response_char=hex_char(selected_mem[19:16]);
                        11: response_char=hex_char(selected_mem[15:12]);
                        12: response_char=hex_char(selected_mem[11:8]);
                        13: response_char=hex_char(selected_mem[7:4]);
                        14: response_char=hex_char(selected_mem[3:0]);
                        15: response_char=8'h0d;
                        16: response_char=8'h0a;
                    endcase
                end
                RESP_PONG: begin
                    case (p)
                        0: response_char="P"; 1: response_char=" "; 2: response_char="B"; 3: response_char=digit(ball_x);
                        4: response_char=digit(ball_y); 5: response_char=" "; 6: response_char="P"; 7: response_char=digit(paddle_x);
                        8: response_char=" "; 9: response_char="O"; 10: response_char=pong_over ? "1" : "0";
                        11: response_char=8'h0d; 12: response_char=8'h0a;
                    endcase
                end
                RESP_RESET: begin
                    case (p)
                        0: response_char="p"; 1: response_char="o"; 2: response_char="n"; 3: response_char="g";
                        4: response_char=" "; 5: response_char="r"; 6: response_char="e"; 7: response_char="s";
                        8: response_char="e"; 9: response_char="t"; 10: response_char=8'h0d; 11: response_char=8'h0a;
                    endcase
                end
                RESP_OVER: begin
                    case (p)
                        0: response_char="p"; 1: response_char="o"; 2: response_char="n"; 3: response_char="g";
                        4: response_char=" "; 5: response_char="o"; 6: response_char="v"; 7: response_char="e";
                        8: response_char="r"; 9: response_char=8'h0d; 10: response_char=8'h0a;
                        11: response_char=metric_char(0);  12: response_char=metric_char(1);
                        13: response_char=metric_char(2);  14: response_char=metric_char(3);
                        15: response_char=metric_char(4);  16: response_char=metric_char(5);
                        17: response_char=metric_char(6);  18: response_char=metric_char(7);
                        19: response_char=metric_char(8);  20: response_char=metric_char(9);
                        21: response_char=metric_char(10); 22: response_char=metric_char(11);
                        23: response_char=metric_char(12); 24: response_char=metric_char(13);
                        25: response_char=metric_char(14); 26: response_char=metric_char(15);
                        27: response_char=metric_char(16); 28: response_char=metric_char(17);
                        29: response_char=metric_char(18); 30: response_char=metric_char(19);
                        31: response_char=metric_char(20); 32: response_char=metric_char(21);
                        33: response_char=metric_char(22); 34: response_char=metric_char(23);
                        35: response_char=metric_char(24); 36: response_char=8'h0a;
                    endcase
                end
                RESP_METRICS: begin
                    if (p < 6'd26)
                        response_char = metric_char(p);
                    else
                        response_char = 8'h0a;
                end
                RESP_BAD: begin
                    case (p)
                        0: response_char="?"; 1: response_char=8'h0d; 2: response_char=8'h0a; 3: response_char="c";
                        4: response_char="p"; 5: response_char="u"; 6: response_char=">";
                    endcase
                end
                RESP_PROMPT: begin
                    case (p)
                        0: response_char="c"; 1: response_char="p"; 2: response_char="u"; 3: response_char=">";
                        4: response_char=" ";
                    endcase
                end
            endcase
        end
    endfunction

    task reset_pong;
        begin
            ball_x <= 3'd4;
            ball_y <= 3'd2;
            ball_dx <= 1'b1;
            ball_dy <= 1'b1;
            paddle_x <= 3'd2;
            pong_over <= 1'b0;
        end
    endtask

    task start_resp;
        input [3:0] r;
        begin
            resp <= r;
            pos <= 6'd0;
            state <= ST_SEND;
        end
    endtask

    task step_pong;
        input signed [1:0] paddle_delta;
        begin
            if (paddle_delta < 0 && paddle_x != 3'd0)
                paddle_x <= paddle_x - 3'd1;
            else if (paddle_delta > 0 && paddle_x < 3'd5)
                paddle_x <= paddle_x + 3'd1;

            next_x = ball_x;
            next_y = ball_y;
            next_dx = ball_dx;
            next_dy = ball_dy;
            miss = 1'b0;

            if (!pong_over) begin
                if (!ball_dx && ball_x == 3'd0)
                    next_dx = 1'b1;
                else if (ball_dx && ball_x == 3'd7)
                    next_dx = 1'b0;

                if (!ball_dy && ball_y == 3'd0)
                    next_dy = 1'b1;

                if (ball_dy && ball_y == 3'd4) begin
                    if ((ball_x >= paddle_x) && (ball_x <= paddle_x + 3'd2))
                        next_dy = 1'b0;
                    else
                        miss = 1'b1;
                end

                if (miss) begin
                    pong_over <= 1'b1;
                    start_resp(RESP_OVER);
                end else begin
                    if (next_dx)
                        ball_x <= ball_x + 3'd1;
                    else
                        ball_x <= ball_x - 3'd1;

                    if (next_dy)
                        ball_y <= ball_y + 3'd1;
                    else
                        ball_y <= ball_y - 3'd1;

                    ball_dx <= next_dx;
                    ball_dy <= next_dy;
                    start_resp(RESP_PONG);
                end
            end else begin
                start_resp(RESP_OVER);
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            wait_seen_busy <= 1'b0;
            boot_sent <= 1'b0;
            resp <= RESP_BANNER;
            pos <= 6'd0;
            selected_mem <= 32'd0;
            mem_id <= 2'd0;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
            reset_pong();
        end else begin
            tx_start <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (!boot_sent) begin
                        boot_sent <= 1'b1;
                        start_resp(RESP_BANNER);
                    end else if (rx_valid) begin
                        case (rx_data)
                            "h", "H": start_resp(RESP_HELP);
                            "s", "S": start_resp(RESP_STATUS);
                            "0": begin selected_mem <= mem0; mem_id <= 2'd0; start_resp(RESP_MEM); end
                            "1": begin selected_mem <= mem1; mem_id <= 2'd1; start_resp(RESP_MEM); end
                            "2": begin selected_mem <= mem2; mem_id <= 2'd2; start_resp(RESP_MEM); end
                            "g", "G": start_resp(RESP_PONG);
                            "n", "N": begin reset_pong(); start_resp(RESP_RESET); end
                            "p", "P": start_resp(RESP_METRICS);
                            "a", "A", "l", "L": step_pong(-1);
                            "d", "D", "r", "R": step_pong(1);
                            "x", "X", 8'h20: step_pong(0);
                            default: start_resp(RESP_BAD);
                        endcase
                    end
                end
                ST_SEND: begin
                    if (!tx_busy) begin
                        if (pos < resp_len(resp)) begin
                            tx_data <= response_char(resp, pos);
                            tx_start <= 1'b1;
                            pos <= pos + 6'd1;
                            wait_seen_busy <= 1'b0;
                            state <= ST_WAIT;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end
                ST_WAIT: begin
                    if (tx_busy)
                        wait_seen_busy <= 1'b1;
                    else if (wait_seen_busy)
                        state <= ST_SEND;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
