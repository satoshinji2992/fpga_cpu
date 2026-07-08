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
//   0/1/2/3 - print Mem[0..3]
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
    input  wire [31:0] mem2,
    input  wire [31:0] mem3,
    // Live hardware performance counters (Stages 0-4), printed by 'p'.
    input  wire [31:0] perf_cycle,
    input  wire [31:0] perf_instret,
    input  wire [31:0] perf_branch,
    input  wire [31:0] perf_flush,
    input  wire [31:0] perf_bp_miss
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
    localparam RESP_PERF    = 4'd10;  // live hardware perf counters

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

    // Pong "next ball" values are computed as combinational wires so the clocked
    // block below only commits them. This replaces the former step_pong task:
    // XST 14.7 mis-handles tasks (signed task ports, task-calls-task), and a
    // blocking-assigned scratch reg inside a clocked block would be inferred as
    // a flip-flop, so we avoid both.
    wire rx_left  = (rx_data == "a") || (rx_data == "A") || (rx_data == "l") || (rx_data == "L");
    wire rx_right = (rx_data == "d") || (rx_data == "D") || (rx_data == "r") || (rx_data == "R");
    wire dx_bounce_l = (!ball_dx && ball_x == 3'd0);
    wire dx_bounce_r = (ball_dx  && ball_x == 3'd7);
    wire dy_bounce_t = (!ball_dy && ball_y == 3'd0);
    wire paddle_hit  = (ball_dy  && ball_y == 3'd4) &&
                       (ball_x >= paddle_x) && (ball_x <= paddle_x + 3'd2);
    wire paddle_miss = (ball_dy  && ball_y == 3'd4) && !paddle_hit;
    wire       step_dx = dx_bounce_l ? 1'b1 : (dx_bounce_r ? 1'b0 : ball_dx);
    wire       step_dy = dy_bounce_t ? 1'b1 : (paddle_hit  ? 1'b0 : ball_dy);
    wire [2:0] step_bx = step_dx ? (ball_x + 3'd1) : (ball_x - 3'd1);
    wire [2:0] step_by = step_dy ? (ball_y + 3'd1) : (ball_y - 3'd1);

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
                RESP_HELP:    resp_len = 6'd32; // "h s 0 1 2 3 g a/d/x n p q\r\ncpu> "
                RESP_STATUS:  resp_len = 6'd13; // "PASS halt=1\r\n" or "FAIL halt=0\r\n"
                RESP_MEM:     resp_len = 6'd17; // "memX=0x12345678\r\n"
                RESP_PONG:    resp_len = 6'd13; // "P Bxy Pp Oo\r\n"
                RESP_RESET:   resp_len = 6'd12; // "pong reset\r\n"
                RESP_OVER:    resp_len = 6'd37; // "pong over\r\nfreq=50MHz CPI=1 T=50MIPS\r\n"
                RESP_METRICS: resp_len = 6'd26; // "freq=50MHz CPI=1 T=50MIPS\r\n"
                RESP_BAD:     resp_len = 6'd7;  // "?\r\ncpu> "
                RESP_PROMPT:  resp_len = 6'd5;  // "cpu> "
                RESP_PERF:    resp_len = 6'd38; // "c=8h i=8h b=2h f=2h m=2h\r\n"
                default:      resp_len = 6'd0;
            endcase
        end
    endfunction

    // Fixed response text lives in initial-initialized byte ROMs so XST infers
    // distributed ROM (free BRAM/distributed-RAM) instead of building a giant
    // comparator tree for the old case-in-function. Only the runtime-dependent
    // responses (STATUS/MEM/PONG) stay as inline logic in response_char below.
    reg [7:0] banner_rom  [0:33];
    reg [7:0] help_rom    [0:31];
    reg [7:0] reset_rom   [0:11];
    reg [7:0] over_rom    [0:36];
    reg [7:0] metrics_rom [0:25];
    reg [7:0] bad_rom     [0:6];
    reg [7:0] prompt_rom  [0:4];

    initial begin
        // RESP_BANNER: "\r\nRV32I pipe+icache shell\r\ncpu>  "
        banner_rom[0]=8'h0d; banner_rom[1]=8'h0a; banner_rom[2]="R"; banner_rom[3]="V";
        banner_rom[4]="3";   banner_rom[5]="2";   banner_rom[6]="I"; banner_rom[7]=" ";
        banner_rom[8]="p";   banner_rom[9]="i";   banner_rom[10]="p"; banner_rom[11]="e";
        banner_rom[12]="+";  banner_rom[13]="i";  banner_rom[14]="c"; banner_rom[15]="a";
        banner_rom[16]="c";  banner_rom[17]="h";  banner_rom[18]="e"; banner_rom[19]=" ";
        banner_rom[20]="s";  banner_rom[21]="h";  banner_rom[22]="e"; banner_rom[23]="l";
        banner_rom[24]="l";  banner_rom[25]=8'h0d;banner_rom[26]=8'h0a;banner_rom[27]="c";
        banner_rom[28]="p";  banner_rom[29]="u";  banner_rom[30]=">"; banner_rom[31]=" ";
        banner_rom[32]=" ";  banner_rom[33]=" ";
        // RESP_HELP: "h s 0 1 2 3 g a/d/x n p q\r\ncpu> "
        help_rom[0]="h";  help_rom[1]=" ";  help_rom[2]="s";  help_rom[3]=" ";
        help_rom[4]="0";  help_rom[5]=" ";  help_rom[6]="1";  help_rom[7]=" ";
        help_rom[8]="2";  help_rom[9]=" ";  help_rom[10]="3"; help_rom[11]=" ";
        help_rom[12]="g"; help_rom[13]=" "; help_rom[14]="a"; help_rom[15]="/";
        help_rom[16]="d"; help_rom[17]="/"; help_rom[18]="x"; help_rom[19]=" ";
        help_rom[20]="n"; help_rom[21]=" "; help_rom[22]="p"; help_rom[23]=" ";
        help_rom[24]="q"; help_rom[25]=8'h0d;help_rom[26]=8'h0a;help_rom[27]="c";
        help_rom[28]="p"; help_rom[29]="u"; help_rom[30]=">"; help_rom[31]=" ";
        // RESP_RESET: "pong reset\r\n"
        reset_rom[0]="p";  reset_rom[1]="o";  reset_rom[2]="n";  reset_rom[3]="g";
        reset_rom[4]=" ";  reset_rom[5]="r";  reset_rom[6]="e";  reset_rom[7]="s";
        reset_rom[8]="e";  reset_rom[9]="t";  reset_rom[10]=8'h0d;reset_rom[11]=8'h0a;
        // RESP_BAD: "?\r\ncpu>"
        bad_rom[0]="?"; bad_rom[1]=8'h0d; bad_rom[2]=8'h0a; bad_rom[3]="c";
        bad_rom[4]="p"; bad_rom[5]="u";   bad_rom[6]=">";
        // RESP_PROMPT: "cpu> "
        prompt_rom[0]="c"; prompt_rom[1]="p"; prompt_rom[2]="u"; prompt_rom[3]=">"; prompt_rom[4]=" ";
        // RESP_OVER: "pong over\r\n" + "freq=50MHz CPI=1 T=50MIPS\r" + "\n"
        over_rom[0]="p";  over_rom[1]="o";  over_rom[2]="n";  over_rom[3]="g";
        over_rom[4]=" ";  over_rom[5]="o";  over_rom[6]="v";  over_rom[7]="e";
        over_rom[8]="r";  over_rom[9]=8'h0d;over_rom[10]=8'h0a;
        over_rom[11]="f"; over_rom[12]="r"; over_rom[13]="e"; over_rom[14]="q";
        over_rom[15]="="; over_rom[16]="5"; over_rom[17]="0"; over_rom[18]="M";
        over_rom[19]="H"; over_rom[20]="z"; over_rom[21]=" "; over_rom[22]="C";
        over_rom[23]="P"; over_rom[24]="I"; over_rom[25]="="; over_rom[26]="1";
        over_rom[27]=" "; over_rom[28]="T"; over_rom[29]="="; over_rom[30]="5";
        over_rom[31]="0"; over_rom[32]="M"; over_rom[33]="I"; over_rom[34]="P";
        over_rom[35]=8'h0d;over_rom[36]=8'h0a;
        // RESP_METRICS: "freq=50MHz CPI=1 T=50MIPS\r\n"
        metrics_rom[0]="f";  metrics_rom[1]="r";  metrics_rom[2]="e";  metrics_rom[3]="q";
        metrics_rom[4]="=";  metrics_rom[5]="5";  metrics_rom[6]="0";  metrics_rom[7]="M";
        metrics_rom[8]="H";  metrics_rom[9]="z";  metrics_rom[10]=" "; metrics_rom[11]="C";
        metrics_rom[12]="P"; metrics_rom[13]="I"; metrics_rom[14]="="; metrics_rom[15]="1";
        metrics_rom[16]=" "; metrics_rom[17]="T"; metrics_rom[18]="="; metrics_rom[19]="5";
        metrics_rom[20]="0"; metrics_rom[21]="M"; metrics_rom[22]="I"; metrics_rom[23]="P";
        metrics_rom[24]=8'h0d; metrics_rom[25]=8'h0a;
    end

    function [7:0] response_char;
        input [3:0] r;
        input [5:0] p;
        begin
            response_char = 8'h20;
            case (r)
                RESP_BANNER:  response_char = banner_rom[p];
                RESP_HELP:    response_char = help_rom[p];
                RESP_RESET:   response_char = reset_rom[p];
                RESP_OVER:    response_char = over_rom[p];
                RESP_METRICS: response_char = metrics_rom[p];
                RESP_BAD:     response_char = bad_rom[p];
                RESP_PROMPT:  response_char = prompt_rom[p];
                RESP_PERF: begin
                    // "c=XXXXXXXX i=XXXXXXXX b=XX f=XX m=XX\r\n" (hex)
                    case (p)
                        6'd0:  response_char = "c";
                        6'd1:  response_char = "=";
                        6'd2:  response_char = hex_char(perf_cycle[31:28]);
                        6'd3:  response_char = hex_char(perf_cycle[27:24]);
                        6'd4:  response_char = hex_char(perf_cycle[23:20]);
                        6'd5:  response_char = hex_char(perf_cycle[19:16]);
                        6'd6:  response_char = hex_char(perf_cycle[15:12]);
                        6'd7:  response_char = hex_char(perf_cycle[11:8]);
                        6'd8:  response_char = hex_char(perf_cycle[7:4]);
                        6'd9:  response_char = hex_char(perf_cycle[3:0]);
                        6'd10: response_char = " ";
                        6'd11: response_char = "i";
                        6'd12: response_char = "=";
                        6'd13: response_char = hex_char(perf_instret[31:28]);
                        6'd14: response_char = hex_char(perf_instret[27:24]);
                        6'd15: response_char = hex_char(perf_instret[23:20]);
                        6'd16: response_char = hex_char(perf_instret[19:16]);
                        6'd17: response_char = hex_char(perf_instret[15:12]);
                        6'd18: response_char = hex_char(perf_instret[11:8]);
                        6'd19: response_char = hex_char(perf_instret[7:4]);
                        6'd20: response_char = hex_char(perf_instret[3:0]);
                        6'd21: response_char = " ";
                        6'd22: response_char = "b";
                        6'd23: response_char = "=";
                        6'd24: response_char = hex_char(perf_branch[7:4]);
                        6'd25: response_char = hex_char(perf_branch[3:0]);
                        6'd26: response_char = " ";
                        6'd27: response_char = "f";
                        6'd28: response_char = "=";
                        6'd29: response_char = hex_char(perf_flush[7:4]);
                        6'd30: response_char = hex_char(perf_flush[3:0]);
                        6'd31: response_char = " ";
                        6'd32: response_char = "m";
                        6'd33: response_char = "=";
                        6'd34: response_char = hex_char(perf_bp_miss[7:4]);
                        6'd35: response_char = hex_char(perf_bp_miss[3:0]);
                        6'd36: response_char = 8'h0d;
                        6'd37: response_char = 8'h0a;
                        default: response_char = 8'h20;
                    endcase
                end
                RESP_STATUS: begin
                    if (test_pass) begin
                        case (p)
                            0: response_char="P"; 1: response_char="A"; 2: response_char="S"; 3: response_char="S";
                            4: response_char=" "; 5: response_char="h"; 6: response_char="a"; 7: response_char="l";
                            8: response_char="t"; 9: response_char="="; 10: response_char="1"; 11: response_char=8'h0d;
                            12: response_char=8'h0a; 13: response_char=" ";
                            default: response_char=8'h20;
                        endcase
                    end else begin
                        case (p)
                            0: response_char="F"; 1: response_char="A"; 2: response_char="I"; 3: response_char="L";
                            4: response_char=" "; 5: response_char="h"; 6: response_char="a"; 7: response_char="l";
                            8: response_char="t"; 9: response_char="="; 10: response_char=halt ? "1" : "0"; 11: response_char=8'h0d;
                            12: response_char=8'h0a; 13: response_char=" ";
                            default: response_char=8'h20;
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
                        default: response_char=8'h20;
                    endcase
                end
                RESP_PONG: begin
                    case (p)
                        0: response_char="P"; 1: response_char=" "; 2: response_char="B"; 3: response_char=digit(ball_x);
                        4: response_char=digit(ball_y); 5: response_char=" "; 6: response_char="P"; 7: response_char=digit(paddle_x);
                        8: response_char=" "; 9: response_char="O"; 10: response_char=pong_over ? "1" : "0";
                        11: response_char=8'h0d; 12: response_char=8'h0a;
                        default: response_char=8'h20;
                    endcase
                end
                default: response_char = 8'h20;
            endcase
        end
    endfunction

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
            // reset_pong, inlined
            ball_x <= 3'd4;
            ball_y <= 3'd2;
            ball_dx <= 1'b1;
            ball_dy <= 1'b1;
            paddle_x <= 3'd2;
            pong_over <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (!boot_sent) begin
                        boot_sent <= 1'b1;
                        resp <= RESP_BANNER; pos <= 6'd0; state <= ST_SEND;
                    end else if (rx_valid) begin
                        case (rx_data)
                            "h", "H": begin resp <= RESP_HELP;   pos <= 6'd0; state <= ST_SEND; end
                            "s", "S": begin resp <= RESP_STATUS; pos <= 6'd0; state <= ST_SEND; end
                            8'h0d, 8'h0a: begin state <= ST_IDLE; end
                            "0": begin selected_mem <= mem0; mem_id <= 2'd0; resp <= RESP_MEM; pos <= 6'd0; state <= ST_SEND; end
                            "1": begin selected_mem <= mem1; mem_id <= 2'd1; resp <= RESP_MEM; pos <= 6'd0; state <= ST_SEND; end
                            "2": begin selected_mem <= mem2; mem_id <= 2'd2; resp <= RESP_MEM; pos <= 6'd0; state <= ST_SEND; end
                            "3": begin selected_mem <= mem3; mem_id <= 2'd3; resp <= RESP_MEM; pos <= 6'd0; state <= ST_SEND; end
                            "g", "G": begin resp <= RESP_PONG; pos <= 6'd0; state <= ST_SEND; end
                            "n", "N": begin
                                // reset_pong, inlined
                                ball_x <= 3'd4; ball_y <= 3'd2; ball_dx <= 1'b1;
                                ball_dy <= 1'b1; paddle_x <= 3'd2; pong_over <= 1'b0;
                                resp <= RESP_RESET; pos <= 6'd0; state <= ST_SEND;
                            end
                            "p", "P": begin resp <= RESP_PERF;   pos <= 6'd0; state <= ST_SEND; end
                            "a", "A", "l", "L", "d", "D", "r", "R", "x", "X", 8'h20: begin
                                // step_pong, inlined; paddle direction comes from rx_data
                                if (rx_left && paddle_x != 3'd0)
                                    paddle_x <= paddle_x - 3'd1;
                                else if (rx_right && paddle_x < 3'd5)
                                    paddle_x <= paddle_x + 3'd1;

                                if (!pong_over) begin
                                    if (paddle_miss) begin
                                        pong_over <= 1'b1;
                                        resp <= RESP_OVER; pos <= 6'd0; state <= ST_SEND;
                                    end else begin
                                        ball_x <= step_bx;
                                        ball_y <= step_by;
                                        ball_dx <= step_dx;
                                        ball_dy <= step_dy;
                                        resp <= RESP_PONG; pos <= 6'd0; state <= ST_SEND;
                                    end
                                end else begin
                                    resp <= RESP_OVER; pos <= 6'd0; state <= ST_SEND;
                                end
                            end
                            default: begin resp <= RESP_BAD; pos <= 6'd0; state <= ST_SEND; end
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
