//==================================================
// Simple UART shell for board-level CPU/system debug
// Commands:
//   h - help
//   s - status
//   0 - print Mem[0]
//   1 - print Mem[1]
//   2 - print Mem[2]
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

    localparam MSG_BANNER = 4'd0;
    localparam MSG_HELP   = 4'd1;
    localparam MSG_PROMPT = 4'd2;
    localparam MSG_PASS   = 4'd3;
    localparam MSG_FAIL   = 4'd4;
    localparam MSG_MEM0   = 4'd5;
    localparam MSG_MEM1   = 4'd6;
    localparam MSG_MEM2   = 4'd7;
    localparam MSG_BAD    = 4'd8;
    localparam MSG_CRLF   = 4'd9;

    localparam BANNER_LEN = 55;
    localparam HELP_LEN   = 45;
    localparam PROMPT_LEN = 5;
    localparam PASS_LEN   = 14;
    localparam FAIL_LEN   = 12;
    localparam MEM_LEN    = 7;
    localparam BAD_LEN    = 14;
    localparam CRLF_LEN   = 7;

    localparam [8*BANNER_LEN-1:0] BANNER_TEXT = "\r\nRISC-V CPU shell\r\nh help s status 0/1/2 mem\r\ncpu> ";
    localparam [8*HELP_LEN-1:0]   HELP_TEXT   = "h:help s:status 0:mem0 1:mem1 2:mem2\r\ncpu> ";
    localparam [8*PROMPT_LEN-1:0] PROMPT_TEXT = "cpu> ";
    localparam [8*PASS_LEN-1:0]   PASS_TEXT   = "PASS halt=1\r\n";
    localparam [8*FAIL_LEN-1:0]   FAIL_TEXT   = "FAIL halt=?\r\n";
    localparam [8*MEM_LEN-1:0]    MEM0_TEXT   = "mem0=0x";
    localparam [8*MEM_LEN-1:0]    MEM1_TEXT   = "mem1=0x";
    localparam [8*MEM_LEN-1:0]    MEM2_TEXT   = "mem2=0x";
    localparam [8*BAD_LEN-1:0]    BAD_TEXT    = "?\r\nh for help\r\n";
    localparam [8*CRLF_LEN-1:0]   CRLF_TEXT   = "\r\ncpu> ";

    localparam ST_IDLE      = 3'd0;
    localparam ST_SEND_MSG  = 3'd1;
    localparam ST_SEND_HEX  = 3'd2;
    localparam ST_WAIT_BYTE = 3'd3;

    localparam AFTER_NONE = 2'd0;
    localparam AFTER_HEX  = 2'd1;
    localparam AFTER_CRLF = 2'd2;

    reg [2:0]  state;
    reg [2:0]  return_state;
    reg        wait_seen_busy;
    reg        boot_sent;
    reg [3:0]  active_msg;
    reg [7:0]  msg_index;
    reg [1:0]  after_msg;
    reg [31:0] hex_value;
    reg [3:0]  hex_index;

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
                MSG_BANNER: msg_len = BANNER_LEN[7:0];
                MSG_HELP:   msg_len = HELP_LEN[7:0];
                MSG_PROMPT: msg_len = PROMPT_LEN[7:0];
                MSG_PASS:   msg_len = PASS_LEN[7:0];
                MSG_FAIL:   msg_len = FAIL_LEN[7:0];
                MSG_MEM0:   msg_len = MEM_LEN[7:0];
                MSG_MEM1:   msg_len = MEM_LEN[7:0];
                MSG_MEM2:   msg_len = MEM_LEN[7:0];
                MSG_BAD:    msg_len = BAD_LEN[7:0];
                MSG_CRLF:   msg_len = CRLF_LEN[7:0];
                default:    msg_len = 8'd0;
            endcase
        end
    endfunction

    function [7:0] msg_char;
        input [3:0] msg;
        input [7:0] idx;
        begin
            case (msg)
                MSG_BANNER: msg_char = BANNER_TEXT[(BANNER_LEN - 1 - idx) * 8 +: 8];
                MSG_HELP:   msg_char = HELP_TEXT[(HELP_LEN - 1 - idx) * 8 +: 8];
                MSG_PROMPT: msg_char = PROMPT_TEXT[(PROMPT_LEN - 1 - idx) * 8 +: 8];
                MSG_PASS:   msg_char = PASS_TEXT[(PASS_LEN - 1 - idx) * 8 +: 8];
                MSG_FAIL:   msg_char = FAIL_TEXT[(FAIL_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM0:   msg_char = MEM0_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM1:   msg_char = MEM1_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_MEM2:   msg_char = MEM2_TEXT[(MEM_LEN - 1 - idx) * 8 +: 8];
                MSG_BAD:    msg_char = BAD_TEXT[(BAD_LEN - 1 - idx) * 8 +: 8];
                MSG_CRLF:   msg_char = CRLF_TEXT[(CRLF_LEN - 1 - idx) * 8 +: 8];
                default:    msg_char = 8'h20;
            endcase
        end
    endfunction

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
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!boot_sent) begin
                        boot_sent  <= 1'b1;
                        active_msg <= MSG_BANNER;
                        msg_index  <= 8'd0;
                        after_msg  <= AFTER_NONE;
                        state      <= ST_SEND_MSG;
                    end else if (rx_valid) begin
                        case (rx_data)
                            "h", "H": begin
                                active_msg <= MSG_HELP;
                                msg_index  <= 8'd0;
                                after_msg  <= AFTER_NONE;
                                state      <= ST_SEND_MSG;
                            end
                            "s", "S": begin
                                active_msg <= test_pass ? MSG_PASS : MSG_FAIL;
                                msg_index  <= 8'd0;
                                after_msg  <= AFTER_CRLF;
                                state      <= ST_SEND_MSG;
                            end
                            "0": begin
                                active_msg <= MSG_MEM0;
                                msg_index  <= 8'd0;
                                hex_value  <= mem0;
                                after_msg  <= AFTER_HEX;
                                state      <= ST_SEND_MSG;
                            end
                            "1": begin
                                active_msg <= MSG_MEM1;
                                msg_index  <= 8'd0;
                                hex_value  <= mem1;
                                after_msg  <= AFTER_HEX;
                                state      <= ST_SEND_MSG;
                            end
                            "2": begin
                                active_msg <= MSG_MEM2;
                                msg_index  <= 8'd0;
                                hex_value  <= mem2;
                                after_msg  <= AFTER_HEX;
                                state      <= ST_SEND_MSG;
                            end
                            8'h0d, 8'h0a: begin
                                active_msg <= MSG_PROMPT;
                                msg_index  <= 8'd0;
                                after_msg  <= AFTER_NONE;
                                state      <= ST_SEND_MSG;
                            end
                            default: begin
                                active_msg <= MSG_BAD;
                                msg_index  <= 8'd0;
                                after_msg  <= AFTER_CRLF;
                                state      <= ST_SEND_MSG;
                            end
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
                            end else if (after_msg == AFTER_CRLF) begin
                                active_msg <= MSG_PROMPT;
                                msg_index  <= 8'd0;
                                after_msg  <= AFTER_NONE;
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
                            active_msg <= MSG_CRLF;
                            msg_index  <= 8'd0;
                            after_msg  <= AFTER_NONE;
                            state      <= ST_SEND_MSG;
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
