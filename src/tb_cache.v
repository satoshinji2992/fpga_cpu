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
    reg [31:0] dm_addr, tw_addr;

    // direct-mapped instance
    wire [31:0] dm_mem_addr;
    reg [31:0] dm_rom_data;
    wire [31:0] dm_cpu_data;
    wire        dm_cpu_valid;
    icache_direct_mapped #(.LINES(8)) u_dm (
        .clk(clk), .rst_n(rst_n), .cpu_addr(dm_addr),
        .mem_addr(dm_mem_addr), .mem_data(dm_rom_data),
        .cpu_data(dm_cpu_data), .cpu_valid(dm_cpu_valid)
    );

    // 2-way instance
    wire [31:0] tw_mem_addr;
    reg [31:0] tw_rom_data;
    wire [31:0] tw_cpu_data, tw_hit, tw_miss;
    wire        tw_cpu_valid;
    icache_2way #(.LINES(8)) u_tw (
        .clk(clk), .rst_n(rst_n), .cpu_addr(tw_addr),
        .mem_addr(tw_mem_addr), .mem_data(tw_rom_data),
        .cpu_data(tw_cpu_data), .cpu_valid(tw_cpu_valid),
        .hit_count(tw_hit), .miss_count(tw_miss)
    );

    // Synchronous ROMs return addr-as-data one cycle after the request.
    always @(posedge clk) begin
        dm_rom_data <= dm_mem_addr;
        tw_rom_data <= tw_mem_addr;
    end

    // TB-side tally of direct-mapped lookups.
    reg [31:0] dm_hit, dm_miss;
    always @(posedge clk) if (rst_n) begin
        if (u_dm.state == 0) begin
            if (u_dm.hit) dm_hit <= dm_hit + 32'd1;
            else          dm_miss <= dm_miss + 32'd1;
        end
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

    reg dm_done, tw_done;
    reg [31:0] dm_hit_final, dm_miss_final, tw_hit_final, tw_miss_final;
    task run_dm;
        integer k;
        begin
            for (k = 0; k < 12; k = k + 1) begin
                @(negedge clk); dm_addr = addrs[k];
                @(posedge clk);
                while (!dm_cpu_valid) @(posedge clk);
                if (dm_cpu_data !== addrs[k]) begin
                    $display("CACHE FAIL direct data addr=%08h got=%08h", addrs[k], dm_cpu_data);
                    $finish;
                end
            end
            dm_hit_final = dm_hit;
            dm_miss_final = dm_miss;
            dm_done = 1'b1;
        end
    endtask

    task run_tw;
        integer k;
        begin
            for (k = 0; k < 12; k = k + 1) begin
                @(negedge clk); tw_addr = addrs[k];
                @(posedge clk);
                while (!tw_cpu_valid) @(posedge clk);
                if (tw_cpu_data !== addrs[k]) begin
                    $display("CACHE FAIL 2way data addr=%08h got=%08h", addrs[k], tw_cpu_data);
                    $finish;
                end
            end
            tw_hit_final = tw_hit;
            tw_miss_final = tw_miss;
            tw_done = 1'b1;
        end
    endtask

    real dm_rate, tw_rate;
    initial begin
        dm_addr = 32'd0; tw_addr = 32'd0;
        dm_done = 1'b0; tw_done = 1'b0;
        dm_hit_final = 0; dm_miss_final = 0;
        tw_hit_final = 0; tw_miss_final = 0;
        wait(rst_n);
        fork
            run_dm();
            run_tw();
        join
        dm_rate = 100.0 * dm_hit_final / (dm_hit_final + dm_miss_final);
        tw_rate = 100.0 * tw_hit_final / (tw_hit_final + tw_miss_final);
        $display("");
        $display("=======================================");
        $display("Conflict stream (0,32,0,32,...) on same set:");
        $display("  DIRECT-MAPPED 8-line: hit=%0d miss=%0d rate=%.1f%%", dm_hit_final, dm_miss_final, dm_rate);
        $display("  2-WAY + LRU      8-line: hit=%0d miss=%0d rate=%.1f%%", tw_hit_final, tw_miss_final, tw_rate);
        if ((tw_miss_final < dm_miss_final) && (tw_miss_final <= 32'd2))
            $display("CACHE PASS (2-way resolves conflict misses)");
        else
            $display("CACHE FAIL");
        $display("=======================================");
        $finish;
    end

endmodule
