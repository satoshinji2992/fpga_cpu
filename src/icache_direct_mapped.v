//==================================================
// Small direct-mapped instruction cache.
//
// This is a look-through cache for the on-chip instruction ROM:
// on a hit it returns the cached line, on a miss it returns the ROM
// data in the same cycle and fills the line on the next clock edge.
// (Hit/miss counters were removed: they were unused in the top-level
// and the two 32-bit updaters cost ~100 LUT each.)
//==================================================
module icache_direct_mapped #(
    parameter LINES = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] cpu_addr,
    output wire [31:0] mem_addr,
    input  wire [31:0] mem_data,
    output wire [31:0] cpu_data,
    output wire        cpu_valid
);

    localparam INDEX_BITS = 3;

    wire [INDEX_BITS-1:0] index;
    wire [31-INDEX_BITS-2:0] tag;
    wire hit;

    reg                    valid [0:LINES-1];
    reg [31-INDEX_BITS-2:0] tags  [0:LINES-1];
    reg [31:0]             data  [0:LINES-1];

    integer i;

    assign index = cpu_addr[INDEX_BITS+1:2];
    assign tag   = cpu_addr[31:INDEX_BITS+2];
    assign hit   = valid[index] && (tags[index] == tag);

    assign mem_addr  = cpu_addr;
    assign cpu_data  = hit ? data[index] : mem_data;
    assign cpu_valid = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                tags[i]  <= {30-INDEX_BITS{1'b0}};
                data[i]  <= 32'b0;
            end
        end else if (!hit) begin
            valid[index] <= 1'b1;
            tags[index]  <= tag;
            data[index]  <= mem_data;
        end
    end

endmodule
