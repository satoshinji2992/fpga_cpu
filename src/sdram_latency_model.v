//==================================================
// sdram_latency_model.v — SDRAM-like variable-latency memory model.
//
// This is not a pin-level SDRAM controller. It is a small bus-facing model used
// to verify that the CPU can stall on data_ready while a slow external memory
// transaction is in flight. A board-specific SDRAM controller can replace this
// module behind the same word bus once the actual SDRAM pins/chip are known.
//==================================================
`timescale 1ns/1ps
module sdram_latency_model #(
    parameter WORDS = 256,
    parameter LATENCY = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  be,
    output reg  [31:0] rdata,
    output wire        ready
);
    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0]  state;
    reg [7:0]  cnt;
    reg        lat_we;
    reg [31:0] lat_addr;
    reg [31:0] lat_wdata;
    reg [3:0]  lat_be;
    reg [31:0] mem [0:WORDS-1];
    integer i;

    wire [31:0] word_index = lat_addr[31:2] % WORDS;
    assign ready = (state == ST_DONE);

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h00000000;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cnt <= 8'd0;
            rdata <= 32'h00000000;
            lat_we <= 1'b0;
            lat_addr <= 32'h00000000;
            lat_wdata <= 32'h00000000;
            lat_be <= 4'b0000;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req) begin
                        lat_we <= we;
                        lat_addr <= addr;
                        lat_wdata <= wdata;
                        lat_be <= be;
                        cnt <= LATENCY[7:0];
                        state <= ST_RUN;
                    end
                end
                ST_RUN: begin
                    if (cnt != 8'd0) begin
                        cnt <= cnt - 8'd1;
                    end else begin
                        rdata <= mem[word_index];
                        if (lat_we) begin
                            if (lat_be[0]) mem[word_index][7:0]   <= lat_wdata[7:0];
                            if (lat_be[1]) mem[word_index][15:8]  <= lat_wdata[15:8];
                            if (lat_be[2]) mem[word_index][23:16] <= lat_wdata[23:16];
                            if (lat_be[3]) mem[word_index][31:24] <= lat_wdata[31:24];
                        end
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
