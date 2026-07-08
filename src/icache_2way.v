//==================================================
// Two-way set-associative instruction cache with LRU.
//
// Same look-through interface as icache_direct_mapped: hit returns the
// cached line, miss returns mem_data in the same cycle and fills on the
// next edge. Two ways per set let conflicting tags coexist (a direct-mapped
// cache thrashes them), and a 1-bit LRU picks the victim on a miss.
// Hit/miss counters are exposed for the cache-hit-rate analysis.
//==================================================
module icache_2way #(
    parameter LINES = 8                 // total lines; SETS = LINES/2 (must be even)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] cpu_addr,
    output wire [31:0] mem_addr,
    input  wire [31:0] mem_data,
    output wire [31:0] cpu_data,
    output wire        cpu_valid,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);
    localparam INDEX_BITS = 2;                       // log2(SETS=4)
    localparam TAG_BITS   = 32 - INDEX_BITS - 2;     // 28
    localparam SETS       = (1 << INDEX_BITS);       // 4

    wire [INDEX_BITS-1:0] index = cpu_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   tag   = cpu_addr[31:INDEX_BITS+2];

    reg                    valid0 [0:SETS-1];
    reg                    valid1 [0:SETS-1];
    reg [TAG_BITS-1:0]     tag0   [0:SETS-1];
    reg [TAG_BITS-1:0]     tag1   [0:SETS-1];
    reg [31:0]             data0  [0:SETS-1];
    reg [31:0]             data1  [0:SETS-1];
    reg                    lru    [0:SETS-1];   // 0 => way0 is LRU, 1 => way1 is LRU

    wire hit0 = valid0[index] && (tag0[index] == tag);
    wire hit1 = valid1[index] && (tag1[index] == tag);
    wire hit  = hit0 || hit1;

    assign mem_addr  = cpu_addr;
    assign cpu_data  = hit0 ? data0[index] : hit1 ? data1[index] : mem_data;
    assign cpu_valid = 1'b1;

    integer s;
    initial begin
        for (s = 0; s < SETS; s = s + 1) begin
            valid0[s] = 1'b0; valid1[s] = 1'b0; lru[s] = 1'b0;
        end
        hit_count  = 32'd0;
        miss_count = 32'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_count  <= 32'd0;
            miss_count <= 32'd0;
            for (s = 0; s < SETS; s = s + 1) begin
                valid0[s] <= 1'b0;
                valid1[s] <= 1'b0;
                lru[s]    <= 1'b0;
                tag0[s]   <= {TAG_BITS{1'b0}};
                tag1[s]   <= {TAG_BITS{1'b0}};
                data0[s]  <= 32'b0;
                data1[s]  <= 32'b0;
            end
        end else begin
            if (hit) begin
                hit_count <= hit_count + 32'd1;
                if (hit0) lru[index] <= 1'b1;   // way0 used => evict way1 next
                else      lru[index] <= 1'b0;   // way1 used => evict way0 next
            end else begin
                miss_count <= miss_count + 32'd1;
                if (!lru[index]) begin
                    valid0[index] <= 1'b1; tag0[index] <= tag; data0[index] <= mem_data;
                    lru[index]    <= 1'b1;
                end else begin
                    valid1[index] <= 1'b1; tag1[index] <= tag; data1[index] <= mem_data;
                    lru[index]    <= 1'b0;
                end
            end
        end
    end

endmodule
