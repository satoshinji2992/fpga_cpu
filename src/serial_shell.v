//==================================================
// UART shell for board-level CPU/system debug.
//
// Commands:
//   h - help
//   s - CPU status
//   0 - print Mem[0]
//   1 - print Mem[1]
//   2 - print Mem[2]
//   g - show snake board
//   u/d/l/r - move snake
//   n - reset snake
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

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (rx),
        .data  (rx_data),
        .valid (rx_valid)
    );

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .start (tx_start),
        .data  (tx_data),
        .tx    (tx),
        .busy  (tx_busy)
    );

    localparam MSG_BANNER      = 4'd0;
    localparam MSG_HELP        = 4'd1;
    localparam MSG_PROMPT      = 4'd2;
    localparam MSG_PASS        = 4'd3;
    localparam MSG_FAIL        = 4'd4;
    localparam MSG_MEM0        = 4'd5;
    localparam MSG_MEM1        = 4'd6;
    localparam MSG_MEM2        = 4'd7;
    localparam MSG_BAD         = 4'd8;
    localparam MSG_CRLF        = 4'd9;
    localparam MSG_SNAKE_HEAD  = 4'd10;
    localparam MSG_SNAKE_EAT   = 4'd11;
    localparam MSG_SNAKE_OVER  = 4'd12;
    localparam MSG_SNAKE_RESET = 4'd13;

    localparam BANNER_LEN      = 81;
    localparam HELP_LEN        = 61;
    localparam PROMPT_LEN      = 5;
    localparam PASS_LEN        = 13;
    localparam FAIL_LEN        = 13;
    localparam MEM_LEN         = 7;
    localparam BAD_LEN         = 15;
    localparam CRLF_LEN        = 7;
    localparam SNAKE_HEAD_LEN  = 35;
    localparam SNAKE_EAT_LEN   = 18;
    localparam SNAKE_OVER_LEN  = 28;
    localparam SNAKE_RESET_LEN = 15;

    localparam [8*BANNER_LEN-1:0]      BANNER_TEXT      = "\r\nRISC-V CPU shell\r\nh help s status 0/1/2 mem g snake u/d/l/r move n reset\r\ncpu> ";
    localparam [8*HELP_LEN-1:0]        HELP_TEXT        = "h:help s:status 0/1/2:mem g:snake u/d/l/r:move n:reset\r\ncpu> ";
    localparam [8*PROMPT_LEN-1:0]      PROMPT_TEXT      = "cpu> ";
    localparam [8*PASS_LEN-1:0]        PASS_TEXT        = "PASS halt=1\r\n";
    localparam [8*FAIL_LEN-1:0]        FAIL_TEXT        = "FAIL halt=?\r\n";
    localparam [8*MEM_LEN-1:0]         MEM0_TEXT        = "mem0=0x";
    localparam [8*MEM_LEN-1:0]         MEM1_TEXT        = "mem1=0x";
    localparam [8*MEM_LEN-1:0]         MEM2_TEXT        = "mem2=0x";
    localparam [8*BAD_LEN-1:0]         BAD_TEXT         = "?\r\nh for help\r\n";
    localparam [8*CRLF_LEN-1:0]        CRLF_TEXT        = "\r\ncpu> ";
    localparam [8*SNAKE_HEAD_LEN-1:0]  SNAKE_HEAD_TEXT  = "\r\nSNAKE 8x8: u/d/l/r move n reset\r\n";
    localparam [8*SNAKE_EAT_LEN-1:0]   SNAKE_EAT_TEXT   = "\r\nsnake ate food\r\n";
    localparam [8*SNAKE_OVER_LEN-1:0]  SNAKE_OVER_TEXT  = "\r\nsnake game over, n reset\r\n";
    localparam [8*SNAKE_RESET_LEN-1:0] SNAKE_RESET_TEXT = "\r\nsnake reset\r\n";

    localparam ST_IDLE       = 3'd0;
    localparam ST_SEND_MSG   = 3'd1;
    localparam ST_SEND_HEX   = 3'd2;
    localparam ST_SEND_BOARD = 3'd3;
    localparam ST_WAIT_BYTE  = 3'd4;

    localparam AFTER_NONE   = 3'd0;
    localparam AFTER_HEX    = 3'd1;
    localparam AFTER_PROMPT = 3'd2;
    localparam AFTER_BOARD  = 3'd3;

    localparam DIR_UP    = 2'd0;
    localparam DIR_DOWN  = 2'd1;
    localparam DIR_LEFT  = 2'd2;
    localparam DIR_RIGHT = 2'd3;

    reg [2:0]  state;
    reg [2:0]  return_state;
    reg        wait_seen_busy;
    reg        boot_sent;
    reg [3:0]  active_msg;
    reg [7:0]  msg_index;
    reg [2:0]  after_msg;
    reg [31:0] hex_value;
    reg [3:0]  hex_index;

    reg [2:0] snake_x0;
    reg [2:0] snake_y0;
    reg [2:0] snake_x1;
    reg [2:0] snake_y1;
    reg [2:0] snake_x2;
    reg [2:0] snake_y2;
    reg [2:0] snake_x3;
    reg [2:0] snake_y3;
    reg [2:0] food_x;
    reg [2:0] food_y;
    reg [1:0] snake_dir;
    reg [2:0] snake_len;
    reg       snake_over;
    reg [2:0] move_x;
    reg [2:0] move_y;
    reg       move_wall;
    reg       move_eat;

    reg [3:0] board_x;
    reg [2:0] board_y;

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            hex_char = (nibble < 4'd10) ? (8'h30 + nibble) : (8'h41 + nibble - 4'd10);
        end
    endfunction

    function [7:0] msg_len;
        input [3:0] msg;
        begin
            case (msg)
                MSG_BANNER:      msg_len = BANNER_LEN[7:0];
                MSG_HELP:        msg_len = HELP_LEN[7:0];
                MSG_PROMPT:      msg_len = PROMPT_LEN[7:0];
                MSG_PASS:        msg_len = PASS_LEN[7:0];
                MSG_FAIL:        msg_len = FAIL_LEN[7:0];
                MSG_MEM0:        msg_len = MEM_LEN[7:0];
                MSG_MEM1:        msg_len = MEM_LEN[7:0];
                MSG_MEM2:        msg_len = MEM_LEN[7:0];
                MSG_BAD:         msg_len = BAD_LEN[7:0];
                MSG_CRLF:        msg_len = CRLF_LEN[7:0];
                MSG_SNAKE_HEAD:  msg_len = SNAKE_HEAD_LEN[7:0];
                MSG_SNAKE_EAT:   msg_len = SNAKE_EAT_LEN[7:0];
                MSG_SNAKE_OVER:  msg_len = SNAKE_OVER_LEN[7:0];
                MSG_SNAKE_RESET: msg_len = SNAKE_RESET_LEN[7:0];
                default:         msg_len = 8'd0;
            endcase
        end
    endfunction

    function [7:0] msg_char;
        input [3:0] msg;
        input [7:0] idx;
        begin
            case (msg)
                MSG_BANNER:      msg_char = BANNER_TEXT[(BANNER_LEN - 1 - idx) * 8 +: 8];
                MSG_HELP:        msg_char = HELP_TEXT[(HELP_LEN - 1 - idx) * 8 +: 8];
                MSG_PROMPT:      msg_char = PROMPT_TEXT[(PROMPT_LEN - 1 - idx) * 8 +: 8];
                MSG_PASS:        msg_char = PASS_TEXT[(PASS_LEN - 1 - idx) * 8 +: 8];
                MSG_FAIL:        msg_char = FAIL_TEXT[(FAIL_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM0:        msg_char = MEM0_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM1:        msg_char = MEM1_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM2:        msg_char = MEM2_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_BAD:         msg_char = BAD_TEXT[(BAD_LEN - 1 - idx) * 8 +: 8];
                MSG_CRLF:        msg_char = CRLF_TEXT[(CRLF_LEN - 1 - idx) * 8 +: 8];
                MSG_SNAKE_HEAD:  msg_char = SNAKE_HEAD_TEXT[(SNAKE_HEAD_LEN - 1 - idx) * 8 +: 8];
                MSG_SNAKE_EAT:   msg_char = SNAKE_EAT_TEXT[(SNAKE_EAT_LEN - 1 - idx) * 8 +: 8];
                MSG_SNAKE_OVER:  msg_char = SNAKE_OVER_TEXT[(SNAKE_OVER_LEN - 1 - idx) * 8 +: 8];
                MSG_SNAKE_RESET: msg_char = SNAKE_RESET_TEXT[(SNAKE_RESET_LEN - 1 - idx) * 8 +: 8];
                default:         msg_char = 8'h20;
            endcase
        end
    endfunction

    function [7:0] board_char;
        input [3:0] x;
        input [2:0] y;
        begin
            if (x == 4'd8)
                board_char = 8'h0d;
            else if (x == 4'd9)
                board_char = 8'h0a;
            else if ((x[2:0] == snake_x0) && (y == snake_y0))
                board_char = 8'h4f; // O
            else if ((x[2:0] == snake_x1) && (y == snake_y1))
                board_char = 8'h6f; // o
            else if ((x[2:0] == snake_x2) && (y == snake_y2))
                board_char = 8'h6f; // o
            else if ((snake_len > 3'd3) && (x[2:0] == snake_x3) && (y == snake_y3))
                board_char = 8'h6f; // o
            else if ((x[2:0] == food_x) && (y == food_y))
                board_char = 8'h40; // @
            else
                board_char = 8'h2e; // .
        end
    endfunction

    task reset_snake;
        begin
            snake_x0   <= 3'd4;
            snake_y0   <= 3'd4;
            snake_x1   <= 3'd3;
            snake_y1   <= 3'd4;
            snake_x2   <= 3'd2;
            snake_y2   <= 3'd4;
            snake_x3   <= 3'd1;
            snake_y3   <= 3'd4;
            food_x     <= 3'd6;
            food_y     <= 3'd4;
            snake_dir  <= DIR_RIGHT;
            snake_len  <= 3'd3;
            snake_over <= 1'b0;
        end
    endtask

    task start_message;
        input [3:0] msg;
        input [2:0] next_after;
        begin
            active_msg <= msg;
            msg_index  <= 8'd0;
            after_msg  <= next_after;
            state      <= ST_SEND_MSG;
        end
    endtask

    task render_board_after;
        begin
            board_x   <= 4'd0;
            board_y   <= 3'd0;
            after_msg <= AFTER_PROMPT;
            state     <= ST_SEND_BOARD;
        end
    endtask

    task move_snake;
        input [1:0] dir;
        begin
            move_x    = snake_x0;
            move_y    = snake_y0;
            move_wall = 1'b0;

            case (dir)
                DIR_UP: begin
                    if (snake_y0 == 3'd0)
                        move_wall = 1'b1;
                    else
                        move_y = snake_y0 - 3'd1;
                end
                DIR_DOWN: begin
                    if (snake_y0 == 3'd7)
                        move_wall = 1'b1;
                    else
                        move_y = snake_y0 + 3'd1;
                end
                DIR_LEFT: begin
                    if (snake_x0 == 3'd0)
                        move_wall = 1'b1;
                    else
                        move_x = snake_x0 - 3'd1;
                end
                DIR_RIGHT: begin
                    if (snake_x0 == 3'd7)
                        move_wall = 1'b1;
                    else
                        move_x = snake_x0 + 3'd1;
                end
            endcase

            move_eat = (move_x == food_x) && (move_y == food_y) && !move_wall;

            if (snake_over || move_wall) begin
                snake_over <= 1'b1;
                start_message(MSG_SNAKE_OVER, AFTER_PROMPT);
            end else begin
                snake_dir <= dir;
                snake_x3  <= move_eat ? snake_x2 : snake_x2;
                snake_y3  <= move_eat ? snake_y2 : snake_y2;
                snake_x2  <= snake_x1;
                snake_y2  <= snake_y1;
                snake_x1  <= snake_x0;
                snake_y1  <= snake_y0;
                snake_x0  <= move_x;
                snake_y0  <= move_y;
                if (move_eat) begin
                    if (snake_len < 3'd4)
                        snake_len <= snake_len + 3'd1;
                    food_x <= food_x + 3'd3;
                    food_y <= food_y + 3'd5;
                    start_message(MSG_SNAKE_EAT, AFTER_BOARD);
                end else begin
                    board_x   <= 4'd0;
                    board_y   <= 3'd0;
                    after_msg <= AFTER_PROMPT;
                    state     <= ST_SEND_BOARD;
                end
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            return_state   <= ST_IDLE;
            wait_seen_busy <= 1'b0;
            boot_sent      <= 1'b0;
            active_msg     <= MSG_BANNER;
            msg_index      <= 8'd0;
            after_msg      <= AFTER_NONE;
            hex_value      <= 32'd0;
            hex_index      <= 4'd0;
            board_x        <= 4'd0;
            board_y        <= 3'd0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
            reset_snake();
        end else begin
            tx_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!boot_sent) begin
                        boot_sent <= 1'b1;
                        start_message(MSG_BANNER, AFTER_NONE);
                    end else if (rx_valid) begin
                        case (rx_data)
                            "h", "H": start_message(MSG_HELP, AFTER_NONE);
                            "s", "S": start_message(test_pass ? MSG_PASS : MSG_FAIL, AFTER_PROMPT);
                            "0": begin
                                hex_value <= mem0;
                                start_message(MSG_MEM0, AFTER_HEX);
                            end
                            "1": begin
                                hex_value <= mem1;
                                start_message(MSG_MEM1, AFTER_HEX);
                            end
                            "2": begin
                                hex_value <= mem2;
                                start_message(MSG_MEM2, AFTER_HEX);
                            end
                            "g", "G": start_message(MSG_SNAKE_HEAD, AFTER_BOARD);
                            "n", "N": begin
                                reset_snake();
                                start_message(MSG_SNAKE_RESET, AFTER_BOARD);
                            end
                            "u", "U": move_snake(DIR_UP);
                            "d", "D": move_snake(DIR_DOWN);
                            "l", "L": move_snake(DIR_LEFT);
                            "r", "R": move_snake(DIR_RIGHT);
                            8'h0d, 8'h0a: start_message(MSG_PROMPT, AFTER_NONE);
                            default: start_message(MSG_BAD, AFTER_PROMPT);
                        endcase
                    end
                end

                ST_SEND_MSG: begin
                    if (!tx_busy) begin
                        if (msg_index < msg_len(active_msg)) begin
                            tx_data        <= msg_char(active_msg, msg_index);
                            tx_start       <= 1'b1;
                            msg_index      <= msg_index + 8'd1;
                            return_state   <= ST_SEND_MSG;
                            wait_seen_busy <= 1'b0;
                            state          <= ST_WAIT_BYTE;
                        end else begin
                            if (after_msg == AFTER_HEX) begin
                                hex_index <= 4'd0;
                                state     <= ST_SEND_HEX;
                            end else if (after_msg == AFTER_BOARD) begin
                                render_board_after();
                            end else if (after_msg == AFTER_PROMPT) begin
                                start_message(MSG_PROMPT, AFTER_NONE);
                            end else begin
                                state <= ST_IDLE;
                            end
                        end
                    end
                end

                ST_SEND_HEX: begin
                    if (!tx_busy) begin
                        if (hex_index < 4'd8) begin
                            tx_data        <= hex_char((hex_value >> ((4'd7 - hex_index) * 4)) & 4'hF);
                            tx_start       <= 1'b1;
                            hex_index      <= hex_index + 4'd1;
                            return_state   <= ST_SEND_HEX;
                            wait_seen_busy <= 1'b0;
                            state          <= ST_WAIT_BYTE;
                        end else begin
                            start_message(MSG_CRLF, AFTER_NONE);
                        end
                    end
                end

                ST_SEND_BOARD: begin
                    if (!tx_busy) begin
                        if (board_y < 3'd8) begin
                            tx_data        <= board_char(board_x, board_y);
                            tx_start       <= 1'b1;
                            return_state   <= ST_SEND_BOARD;
                            wait_seen_busy <= 1'b0;
                            state          <= ST_WAIT_BYTE;

                            if (board_x == 4'd9) begin
                                board_x <= 4'd0;
                                board_y <= board_y + 3'd1;
                            end else begin
                                board_x <= board_x + 4'd1;
                            end
                        end else begin
                            if (after_msg == AFTER_PROMPT)
                                start_message(MSG_PROMPT, AFTER_NONE);
                            else
                                state <= ST_IDLE;
                        end
                    end
                end

                ST_WAIT_BYTE: begin
                    if (tx_busy)
                        wait_seen_busy <= 1'b1;
                    else if (wait_seen_busy)
                        state <= return_state;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
