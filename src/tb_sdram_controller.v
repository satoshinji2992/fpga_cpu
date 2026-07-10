`timescale 1ns/1ps
module tb_sdram_controller;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg req = 1'b0;
    reg we = 1'b0;
    reg [25:0] addr = 0;
    reg [31:0] wdata = 0;
    reg [3:0] be = 0;
    wire [31:0] rdata;
    wire ready, init_done;
    wire [31:0] refresh_count;
    wire sclk, cke, cs_n, ras_n, cas_n, we_n;
    wire [12:0] saddr;
    wire [1:0] ba;
    wire [3:0] dqm;
    wire [31:0] dq;

    reg model_oe = 1'b0;
    reg [31:0] model_dq = 0;
    reg [31:0] mem [0:32767];
    reg [12:0] open_row [0:3];
    reg [14:0] read_index;
    reg [2:0] read_count = 0;
    integer i;
    assign dq = model_oe ? model_dq : 32'bz;

    sdram_controller #(.INIT_US(1), .REFRESH_CYCLES(30)) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .we(we), .addr(addr),
        .wdata(wdata), .be(be), .rdata(rdata), .ready(ready),
        .init_done(init_done), .refresh_count(refresh_count),
        .sdram_clk(sclk), .sdram_cke(cke), .sdram_cs_n(cs_n),
        .sdram_ras_n(ras_n), .sdram_cas_n(cas_n), .sdram_we_n(we_n),
        .sdram_addr(saddr), .sdram_ba(ba), .sdram_dqm(dqm), .sdram_dq(dq)
    );

    always #10 clk = ~clk;

    // Model the low 128 KiB without row aliasing. This is enough to verify the
    // address range used by Paint while keeping simulation memory modest.
    always @(posedge sclk) begin
        if (read_count != 0) begin
            read_count <= read_count - 1'b1;
            if (read_count == 1) begin
                model_dq <= mem[read_index];
                model_oe <= 1'b1;
            end
        end else if (model_oe) begin
            model_oe <= 1'b0;
        end

        if (cke && !cs_n) begin
            case ({ras_n, cas_n, we_n})
                3'b011: open_row[ba] <= saddr; // ACTIVE
                3'b101: begin                 // READ
                    read_index <= {open_row[ba][5:0], saddr[8:0]};
                    read_count <= 3'd2;
                end
                3'b100: begin                 // WRITE
                    if (!dqm[0]) mem[{open_row[ba][5:0], saddr[8:0]}][7:0]   <= dq[7:0];
                    if (!dqm[1]) mem[{open_row[ba][5:0], saddr[8:0]}][15:8]  <= dq[15:8];
                    if (!dqm[2]) mem[{open_row[ba][5:0], saddr[8:0]}][23:16] <= dq[23:16];
                    if (!dqm[3]) mem[{open_row[ba][5:0], saddr[8:0]}][31:24] <= dq[31:24];
                end
                default: begin end
            endcase
        end
    end

    task write_word;
        input [25:0] a;
        input [31:0] d;
        input [3:0] mask;
        begin
            @(negedge clk); addr=a; wdata=d; be=mask; we=1; req=1;
            while (!ready) @(negedge clk);
            req=0; we=0; be=0;
            @(negedge clk);
        end
    endtask

    task read_word;
        input [25:0] a;
        begin
            @(negedge clk); addr=a; we=0; req=1;
            while (!ready) @(negedge clk);
            req=0;
            @(negedge clk);
        end
    endtask

    initial begin
        for (i=0; i<32768; i=i+1) mem[i]=0;
        repeat (5) @(posedge clk);
        rst_n=1;
        wait(init_done);

        write_word(26'h0000000, 32'h12345678, 4'b1111);
        read_word (26'h0000000);
        if (rdata !== 32'h12345678) begin
            $display("SDRAM CTRL FAIL word read=%08h", rdata); $finish;
        end
        write_word(26'h0000000, 32'hAABBCCDD, 4'b0101);
        read_word (26'h0000000);
        if (rdata !== 32'h12BB56DD) begin
            $display("SDRAM CTRL FAIL mask read=%08h", rdata); $finish;
        end
        write_word(26'h0000800, 32'hCAFEBABE, 4'b1111);
        read_word (26'h0000000);
        if (rdata !== 32'h12BB56DD) begin
            $display("SDRAM CTRL FAIL row alias low=%08h", rdata); $finish;
        end
        read_word (26'h0000800);
        if (rdata !== 32'hCAFEBABE) begin
            $display("SDRAM CTRL FAIL row alias high=%08h", rdata); $finish;
        end
        repeat (100) @(posedge clk);
        if (refresh_count == 0) begin
            $display("SDRAM CTRL FAIL no refresh"); $finish;
        end
        $display("SDRAM CONTROLLER PASS data=%08h refresh=%0d", rdata, refresh_count);
        $finish;
    end
endmodule
