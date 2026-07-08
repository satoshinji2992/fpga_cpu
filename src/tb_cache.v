//==================================================
// Stage 3 regression: cache associativity.
//
// Drives a conflict address stream (0, 32, 0, 32, ...) where both addresses
// map to the same set. A direct-mapped cache thrashes (every access misses);
// a 2-way cache holds both lines and hits after warm-up.
//   addr 0  -> index 0, tag 0
//   addr 32 -> index 0, tag 1   (same set, different tag)
// Direct-mapped hit/miss is tallied in the TB via a hierarchical reference
// to u_dm.hit, so icache_direct_mapped is left unchanged.
//==================================================
`timescale 1ns/1ps
module tb_cache;

    reg clk, rst_n;
    reg [31:0] cpu_addr;

    // direct-mapped instance
    wire [31:0] dm_mem_addr;
    wire [31:0] dm_rom_data = dm_mem_addr;     // ROM returns addr-as-data
    wire [31:0] dm_cpu_data;
    wire        dm_cpu_valid;
    icache_direct_mapped #(.LINES(8)) u_dm (
        .clk(clk), .rst_n(rst_n), .cpu_addr(cpu_addr),
        .mem_addr(dm_mem_addr), .mem_data(dm_rom_data),
        .cpu_data(dm_cpu_data), .cpu_valid(dm_cpu_valid)
    );

    // 2-way instance
    wire [31:0] tw_mem_addr;
    wire [31:0] tw_rom_data = tw_mem_addr;
    wire [31:0] tw_cpu_data, tw_hit, tw_miss;
    wire        tw_cpu_valid;
    icache_2way #(.LINES(8)) u_tw (
        .clk(clk), .rst_n(rst_n), .cpu_addr(cpu_addr),
        .mem_addr(tw_mem_addr), .mem_data(tw_rom_data),
        .cpu_data(tw_cpu_data), .cpu_valid(tw_cpu_valid),
        .hit_count(tw_hit), .miss_count(tw_miss)
    );

    // TB-side tally of direct-mapped hit/miss (hierarchical ref to internal hit)
    reg [31:0] dm_hit, dm_miss;
    always @(posedge clk) if (rst_n) begin
        if (u_dm.hit) dm_hit <= dm_hit + 32'd1;
        else          dm_miss <= dm_miss + 32'd1;
    end

    initial begin clk = 1'b0; forever #5 clk = ~clk; end
    initial begin rst_n = 1'b0; dm_hit = 0; dm_miss = 0; #20 rst_n = 1'b1; end

    // conflict address stream: 0 and 32 share set 0 but differ in tag
    reg [31:0] addrs [0:11];
    integer a;
    initial begin
        addrs[0]=32'd0;  addrs[1]=32'd32; addrs[2]=32'd0;  addrs[3]=32'd32;
        addrs[4]=32'd0;  addrs[5]=32'd32; addrs[6]=32'd0;  addrs[7]=32'd32;
        addrs[8]=32'd0;  addrs[9]=32'd32; addrs[10]=32'd0; addrs[11]=32'd32;
    end

    // drive one address per cycle
    reg [31:0] cyc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc <= 32'd0; cpu_addr <= 32'd0;
        end else if (cyc < 12) begin
            cpu_addr <= addrs[cyc];
            cyc <= cyc + 32'd1;
        end
    end

    real dm_rate, tw_rate;
    initial begin
        #400;
        dm_rate = (dm_hit + dm_miss > 0) ? (100.0 * dm_hit / (dm_hit + dm_miss)) : 0.0;
        tw_rate = (tw_hit + tw_miss > 0) ? (100.0 * tw_hit / (tw_hit + tw_miss)) : 0.0;
        $display("");
        $display("=======================================");
        $display("Conflict stream (0,32,0,32,...) on same set:");
        $display("  DIRECT-MAPPED 8-line: hit=%0d miss=%0d rate=%.1f%%", dm_hit, dm_miss, dm_rate);
        $display("  2-WAY + LRU      8-line: hit=%0d miss=%0d rate=%.1f%%", tw_hit, tw_miss, tw_rate);
        if ((tw_miss < dm_miss) && (tw_miss <= 32'd2))
            $display("CACHE PASS (2-way resolves conflict misses)");
        else
            $display("CACHE FAIL");
        $display("=======================================");
        $finish;
    end

endmodule
