//==================================================
// Two-way set-associative instruction cache for a synchronous ROM.
//==================================================
module icache_2way #(
    parameter LINES = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] cpu_addr,
    output wire [31:0] mem_addr,
    input  wire [31:0] mem_data,
    output reg  [31:0] cpu_data,
    output wire        cpu_valid,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);
    localparam INDEX_BITS = 2;
    localparam TAG_BITS = 32 - INDEX_BITS - 2;
    localparam SETS = 1 << INDEX_BITS;
    localparam ST_LOOKUP = 2'd0, ST_MISS = 2'd1, ST_RESP = 2'd2;

    wire [INDEX_BITS-1:0] index = cpu_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0] tag = cpu_addr[31:INDEX_BITS+2];
    wire hit0 = valid0[index] && (tag0[index] == tag);
    wire hit1 = valid1[index] && (tag1[index] == tag);
    wire hit = hit0 || hit1;

    reg valid0 [0:SETS-1];
    reg valid1 [0:SETS-1];
    reg [TAG_BITS-1:0] tag0 [0:SETS-1];
    reg [TAG_BITS-1:0] tag1 [0:SETS-1];
    reg [31:0] data0 [0:SETS-1];
    reg [31:0] data1 [0:SETS-1];
    reg lru [0:SETS-1];
    reg [1:0] state;
    reg [31:0] miss_addr;
    reg [31:0] response_addr;
    reg [INDEX_BITS-1:0] miss_index;
    reg [TAG_BITS-1:0] miss_tag;
    reg miss_way;
    integer s;

    assign mem_addr = (state == ST_LOOKUP) ? cpu_addr : miss_addr;
    assign cpu_valid = (state == ST_RESP) && (cpu_addr == response_addr);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_LOOKUP;
            cpu_data <= 32'd0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
            miss_addr <= 32'd0;
            response_addr <= 32'd0;
            miss_index <= {INDEX_BITS{1'b0}};
            miss_tag <= {TAG_BITS{1'b0}};
            miss_way <= 1'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                valid0[s] <= 1'b0; valid1[s] <= 1'b0; lru[s] <= 1'b0;
                tag0[s] <= {TAG_BITS{1'b0}}; tag1[s] <= {TAG_BITS{1'b0}};
                data0[s] <= 32'd0; data1[s] <= 32'd0;
            end
        end else begin
            case (state)
                ST_LOOKUP: begin
                    if (hit) begin
                        cpu_data <= hit0 ? data0[index] : data1[index];
                        response_addr <= cpu_addr;
                        hit_count <= hit_count + 1'b1;
                        lru[index] <= hit0 ? 1'b1 : 1'b0;
                        state <= ST_RESP;
                    end else begin
                        miss_count <= miss_count + 1'b1;
                        miss_addr <= cpu_addr;
                        miss_index <= index;
                        miss_tag <= tag;
                        miss_way <= !valid0[index] ? 1'b0 :
                                    !valid1[index] ? 1'b1 : lru[index];
                        state <= ST_MISS;
                    end
                end
                ST_MISS: begin
                    if (!miss_way) begin
                        valid0[miss_index] <= 1'b1;
                        tag0[miss_index] <= miss_tag;
                        data0[miss_index] <= mem_data;
                        lru[miss_index] <= 1'b1;
                    end else begin
                        valid1[miss_index] <= 1'b1;
                        tag1[miss_index] <= miss_tag;
                        data1[miss_index] <= mem_data;
                        lru[miss_index] <= 1'b0;
                    end
                    cpu_data <= mem_data;
                    response_addr <= miss_addr;
                    state <= ST_RESP;
                end
                default: state <= ST_LOOKUP;
            endcase
        end
    end
endmodule
