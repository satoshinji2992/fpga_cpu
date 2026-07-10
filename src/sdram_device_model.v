`timescale 1ns/1ps
// Low-128-KiB command-level model for SoC integration testbenches.
// It models ACTIVE/READ/WRITE and byte masks; initialization and refresh
// commands are accepted but need no storage-side behavior here.
module sdram_device_model (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [1:0]  dqm_lo,
    input  wire [1:0]  dqm_hi,
    input  wire [1:0]  ba,
    input  wire [12:0] addr,
    inout  wire [15:0] dq_lo,
    inout  wire [15:0] dq_hi
);
    reg [31:0] mem [0:32767];
    reg [12:0] open_row [0:3];
    reg [14:0] read_index;
    reg [2:0] read_count = 0;
    reg [31:0] read_data = 0;
    reg read_oe = 0;
    integer i;

    wire [31:0] dq = {dq_hi, dq_lo};
    assign dq_lo = read_oe ? read_data[15:0] : 16'bz;
    assign dq_hi = read_oe ? read_data[31:16] : 16'bz;

    initial begin
        for (i = 0; i < 32768; i = i + 1)
            mem[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (read_count != 0) begin
            read_count <= read_count - 1'b1;
            if (read_count == 1) begin
                read_data <= mem[read_index];
                read_oe <= 1'b1;
            end
        end else if (read_oe) begin
            read_oe <= 1'b0;
        end

        if (cke && !cs_n) begin
            case ({ras_n, cas_n, we_n})
                3'b011: open_row[ba] <= addr;
                3'b101: begin
                    read_index <= {open_row[ba][5:0], addr[8:0]};
                    read_count <= 3'd2;
                end
                3'b100: begin
                    if (!dqm_lo[0]) mem[{open_row[ba][5:0], addr[8:0]}][7:0]   <= dq[7:0];
                    if (!dqm_lo[1]) mem[{open_row[ba][5:0], addr[8:0]}][15:8]  <= dq[15:8];
                    if (!dqm_hi[0]) mem[{open_row[ba][5:0], addr[8:0]}][23:16] <= dq[23:16];
                    if (!dqm_hi[1]) mem[{open_row[ba][5:0], addr[8:0]}][31:24] <= dq[31:24];
                end
                default: begin end
            endcase
        end
    end
endmodule
