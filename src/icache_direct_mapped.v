//==================================================
// Small direct-mapped instruction cache for a synchronous instruction ROM.
//==================================================
module icache_direct_mapped #(
    parameter LINES = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] cpu_addr,
    output wire [31:0] mem_addr,
    input  wire [31:0] mem_data,
    output reg  [31:0] cpu_data,
    output wire        cpu_valid
);
    localparam INDEX_BITS = 3;
    localparam ST_LOOKUP = 2'd0, ST_MISS = 2'd1, ST_RESP = 2'd2;

    wire [INDEX_BITS-1:0] index = cpu_addr[INDEX_BITS+1:2];
    wire [31-INDEX_BITS-2:0] tag = cpu_addr[31:INDEX_BITS+2];
    wire hit = valid[index] && (tags[index] == tag);

    reg                    valid [0:LINES-1];
    reg [31-INDEX_BITS-2:0] tags [0:LINES-1];
    reg [31:0]             data [0:LINES-1];
    reg [1:0]              state;
    reg [31:0]             miss_addr;
    reg [31:0]             response_addr;
    reg [INDEX_BITS-1:0]   miss_index;
    reg [31-INDEX_BITS-2:0] miss_tag;
    integer i;

    // During lookup the ROM sees the current CPU address soon enough to
    // capture it on the same edge that records a miss.
    assign mem_addr = (state == ST_LOOKUP) ? cpu_addr : miss_addr;
    assign cpu_valid = (state == ST_RESP) && (cpu_addr == response_addr);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_LOOKUP;
            cpu_data <= 32'd0;
            miss_addr <= 32'd0;
            response_addr <= 32'd0;
            miss_index <= {INDEX_BITS{1'b0}};
            miss_tag <= {(30-INDEX_BITS){1'b0}};
            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                tags[i] <= {(30-INDEX_BITS){1'b0}};
                data[i] <= 32'd0;
            end
        end else begin
            case (state)
                ST_LOOKUP: begin
                    if (hit) begin
                        cpu_data <= data[index];
                        response_addr <= cpu_addr;
                        state <= ST_RESP;
                    end else begin
                        miss_addr <= cpu_addr;
                        miss_index <= index;
                        miss_tag <= tag;
                        state <= ST_MISS;
                    end
                end
                ST_MISS: begin
                    valid[miss_index] <= 1'b1;
                    tags[miss_index] <= miss_tag;
                    data[miss_index] <= mem_data;
                    cpu_data <= mem_data;
                    response_addr <= miss_addr;
                    state <= ST_RESP;
                end
                default: state <= ST_LOOKUP;
            endcase
        end
    end
endmodule
