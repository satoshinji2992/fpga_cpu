//==================================================
// HY57V2562 dual-chip SDRAM controller (clock-frequency parameterized).
//
// The TEC-PLUS board has two independent x16 chips. They receive identical
// commands/addresses and form one x32 word. The controller uses burst length 1,
// CAS latency 2, auto-precharge and a closed-page policy. CPU requests remain
// asserted until ready; one request is accepted at a time.
//==================================================
module sdram_controller #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer INIT_US = 200,
    parameter integer REFRESH_CYCLES = CLK_FREQ_HZ / 128000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [25:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  be,
    output reg  [31:0] rdata,
    output wire        ready,
    output reg         init_done,
    output reg  [31:0] refresh_count,

    output wire        sdram_clk,
    output reg         sdram_cke,
    output reg         sdram_cs_n,
    output reg         sdram_ras_n,
    output reg         sdram_cas_n,
    output reg         sdram_we_n,
    output reg  [12:0] sdram_addr,
    output reg  [1:0]  sdram_ba,
    output reg  [3:0]  sdram_dqm,
    inout  wire [31:0] sdram_dq
);
    localparam integer INIT_CYCLES = (CLK_FREQ_HZ / 1000000) * INIT_US;
    localparam [3:0] ST_INIT_WAIT = 4'd0,
                     ST_INIT_RP   = 4'd1,
                     ST_INIT_RF1  = 4'd2,
                     ST_INIT_RF2  = 4'd3,
                     ST_INIT_MRS  = 4'd4,
                     ST_IDLE      = 4'd5,
                     ST_RFC       = 4'd6,
                     ST_RCD       = 4'd7,
                     ST_READ      = 4'd8,
                     ST_WRITE     = 4'd9,
                     ST_READ_WAIT = 4'd10,
                     ST_WRITE_WAIT= 4'd11,
                     ST_DONE      = 4'd12;

    reg [3:0] state;
    reg [15:0] wait_count;
    reg [15:0] refresh_timer;
    reg        lat_we;
    reg [8:0]  lat_col;
    reg [1:0]  lat_bank;
    reg [31:0] lat_wdata;
    reg [3:0]  lat_be;
    reg        dq_oe;
    reg [31:0] dq_out;

    wire [31:0] dq_in = sdram_dq;
    assign sdram_dq = dq_oe ? dq_out : 32'bz;
    // Launch commands/data on clk's rising edge, then let SDRAM capture them
    // half a cycle later.  This also places read sampling near the middle of
    // the SDRAM data-valid window instead of on the SDRAM output transition.
    assign sdram_clk = ~clk;
    assign ready = (state == ST_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_INIT_WAIT;
            wait_count    <= INIT_CYCLES[15:0];
            refresh_timer <= 16'd0;
            refresh_count <= 32'd0;
            init_done      <= 1'b0;
            rdata          <= 32'd0;
            lat_we         <= 1'b0;
            lat_col        <= 9'd0;
            lat_bank       <= 2'd0;
            lat_wdata      <= 32'd0;
            lat_be         <= 4'd0;
            dq_oe          <= 1'b0;
            dq_out         <= 32'd0;
            sdram_cke      <= 1'b0;
            sdram_cs_n     <= 1'b1;
            sdram_ras_n    <= 1'b1;
            sdram_cas_n    <= 1'b1;
            sdram_we_n     <= 1'b1;
            sdram_addr     <= 13'd0;
            sdram_ba       <= 2'd0;
            sdram_dqm      <= 4'hF;
        end else begin
            sdram_cs_n  <= 1'b0;
            sdram_ras_n <= 1'b1;
            sdram_cas_n <= 1'b1;
            sdram_we_n  <= 1'b1;
            dq_oe      <= 1'b0;
            sdram_dqm  <= 4'h0;

            case (state)
                ST_INIT_WAIT: begin
                    sdram_cke <= 1'b1;
                    if (wait_count != 0) begin
                        wait_count <= wait_count - 1'b1;
                    end else begin
                        // PRECHARGE ALL (A10=1)
                        sdram_ras_n <= 1'b0;
                        sdram_we_n  <= 1'b0;
                        sdram_addr  <= 13'b0010000000000;
                        wait_count  <= 16'd2;
                        state       <= ST_INIT_RP;
                    end
                end
                ST_INIT_RP: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else begin
                        sdram_ras_n <= 1'b0;
                        sdram_cas_n <= 1'b0; // AUTO REFRESH
                        wait_count <= 16'd4;
                        state <= ST_INIT_RF1;
                    end
                end
                ST_INIT_RF1: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else begin
                        sdram_ras_n <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        wait_count <= 16'd4;
                        state <= ST_INIT_RF2;
                    end
                end
                ST_INIT_RF2: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else begin
                        // MODE: BL=1, sequential, CL=2, single-location write.
                        sdram_ras_n <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        sdram_we_n  <= 1'b0;
                        sdram_ba    <= 2'b00;
                        sdram_addr  <= 13'h220;
                        wait_count  <= 16'd2;
                        state       <= ST_INIT_MRS;
                    end
                end
                ST_INIT_MRS: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else begin
                        init_done <= 1'b1;
                        refresh_timer <= 16'd0;
                        state <= ST_IDLE;
                    end
                end
                ST_IDLE: begin
                    if (refresh_timer >= REFRESH_CYCLES - 1) begin
                        sdram_ras_n <= 1'b0;
                        sdram_cas_n <= 1'b0;
                        refresh_timer <= 16'd0;
                        refresh_count <= refresh_count + 1'b1;
                        wait_count <= 16'd4;
                        state <= ST_RFC;
                    end else if (req) begin
                        lat_we    <= we;
                        lat_col   <= addr[10:2];
                        lat_bank  <= addr[25:24];
                        lat_wdata <= wdata;
                        lat_be    <= be;
                        // ACTIVE uses the incoming address directly.
                        sdram_ras_n <= 1'b0;
                        sdram_ba    <= addr[25:24];
                        sdram_addr  <= addr[23:11];
                        wait_count  <= 16'd2;
                        state       <= ST_RCD;
                    end else begin
                        refresh_timer <= refresh_timer + 1'b1;
                    end
                end
                ST_RFC: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else state <= ST_IDLE;
                end
                ST_RCD: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else if (lat_we) state <= ST_WRITE;
                    else state <= ST_READ;
                end
                ST_READ: begin
                    sdram_cas_n <= 1'b0;
                    sdram_ba    <= lat_bank;
                    sdram_addr  <= {2'b00, 1'b1, 1'b0, lat_col}; // A10 auto-precharge
                    sdram_dqm   <= 4'h0;
                    // With the forwarded clock inverted, CL=2 data is driven
                    // at the second SDRAM edge and sampled on the following
                    // controller edge (half a clock later).
                    wait_count  <= 16'd2;
                    state       <= ST_READ_WAIT;
                end
                ST_WRITE: begin
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b0;
                    sdram_ba    <= lat_bank;
                    sdram_addr  <= {2'b00, 1'b1, 1'b0, lat_col};
                    sdram_dqm   <= ~lat_be;
                    dq_out      <= lat_wdata;
                    dq_oe       <= 1'b1;
                    wait_count  <= 16'd4;
                    state       <= ST_WRITE_WAIT;
                end
                ST_READ_WAIT: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else begin
                        rdata <= dq_in;
                        state <= ST_DONE;
                    end
                end
                ST_WRITE_WAIT: begin
                    if (wait_count != 0) wait_count <= wait_count - 1'b1;
                    else state <= ST_DONE;
                end
                ST_DONE: begin
                    state <= ST_IDLE;
                end
                default: state <= ST_INIT_WAIT;
            endcase
        end
    end
endmodule
