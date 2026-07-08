//==================================================
// tb_dungeon.v — end-to-end verification of the CPU-driven UART dungeon.
//
// Drives W/A/S/D into top.uart_rx as real serial frames (8N1, CLKS_PER_BIT
// matching top.v) and captures every byte from top.uart_tx into a log buffer.
// After a scripted play sequence it asserts the captured log contains the
// player glyph, the monster glyph, the prompt, a combat line, and the win
// banner — proving render + UART MMIO (both directions) + movement + MUL/DIV
// combat + RDCYCLE/POPCOUNT RNG + the win branch all work on the real core.
//
//   iverilog -I src -o tb_dungeon src/top.v src/riscv_pipeline_core.v \
//       src/icache_direct_mapped.v src/uart_rx.v src/uart_tx.v src/tb_dungeon.v
//   vvp tb_dungeon
//==================================================
`timescale 1ns/1ps
module tb_dungeon;
    localparam integer CLKS_PER_BIT = 16;    // accelerated UART for simulation
    localparam integer BIT_TIMEOUT   = CLKS_PER_BIT * 15;
    localparam integer TURN_CYCLES   = 20000;   // > one render at accelerated baud
    localparam integer LOG_SIZE      = 4096;

    reg         clk = 1'b0;
    reg         rst_n;
    wire        uart_tx;
    reg         uart_rx_line = 1'b1;   // RS232 idles high
    wire [3:0]  led;

    // capture buffer
    reg [7:0]   log [0:LOG_SIZE-1];
    integer     log_len = 0;
    integer     i, j, match;
    wire [7:0]  cap_data;
    wire        cap_valid;

    top #(
        .CLK_FREQ(1600000),
        .BAUD(100000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .key1(1'b1), .key2(1'b1), .key3(1'b1), .key4(1'b1),
        .uart_rx(uart_rx_line), .uart_tx(uart_tx),
        .led1(led[0]), .led2(led[1]), .led3(led[2]), .led4(led[3])
    );

    always #5 clk = ~clk;            // 100 MHz sim clock (baud is cycle-count based)

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_capture_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_tx), .data(cap_data), .valid(cap_valid)
    );

    // ---------- send one byte as a serial frame into uart_rx ----------
    task send_byte;
        input [7:0] b;
        integer k;
        begin
            uart_rx_line = 1'b0;                 // start bit
            repeat(CLKS_PER_BIT) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_line = b[k];
                repeat(CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx_line = 1'b1;                 // stop bit
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // ---------- continuous tx capture (runs in parallel) ----------
    always @(posedge clk) begin
        if (cap_valid && log_len < LOG_SIZE) begin
            log[log_len] = cap_data;
            log_len = log_len + 1;
        end
    end

    // ---------- substring checks in the captured log ----------
    function integer has_cmd;
        input integer unused;
        integer ii;
        begin
            has_cmd = 0;
            for (ii = 0; ii + 2 < log_len; ii = ii + 1)
                if (log[ii] == "c" && log[ii+1] == "m" && log[ii+2] == "d") has_cmd = 1;
        end
    endfunction

    function integer has_hit;
        input integer unused;
        integer ii;
        begin
            has_hit = 0;
            for (ii = 0; ii + 2 < log_len; ii = ii + 1)
                if (log[ii] == "h" && log[ii+1] == "i" && log[ii+2] == "t") has_hit = 1;
        end
    endfunction

    function integer has_you_win;
        input integer unused;
        integer ii;
        begin
            has_you_win = 0;
            for (ii = 0; ii + 6 < log_len; ii = ii + 1)
                if (log[ii] == "Y" && log[ii+1] == "O" && log[ii+2] == "U" &&
                    log[ii+3] == " " && log[ii+4] == "W" && log[ii+5] == "I" &&
                    log[ii+6] == "N") has_you_win = 1;
        end
    endfunction

    function integer has_byte;
        input [7:0] b;
        integer ii;
        begin
            has_byte = 0;
            for (ii = 0; ii < log_len; ii = ii + 1)
                if (log[ii] === b) has_byte = 1;
        end
    endfunction

    // ---------- global safety timeout ----------
    initial begin
        #200_000_000;   // 200 ms sim wallclock safety net
        $display("DUNGEON FAIL (global timeout; log_len=%0d)", log_len);
        $finish;
    end

    // ---------- main: reset, boot, play, assert ----------
    integer fails;
    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;

        // boot render + first prompt
        repeat(TURN_CYCLES) @(posedge clk);

        // move right 5 times to reach column 6, row 1 (monster is at (6,2))
        send_byte(8'h64); repeat(TURN_CYCLES) @(posedge clk);  // d
        send_byte(8'h64); repeat(TURN_CYCLES) @(posedge clk);  // d
        send_byte(8'h64); repeat(TURN_CYCLES) @(posedge clk);  // d
        send_byte(8'h64); repeat(TURN_CYCLES) @(posedge clk);  // d
        send_byte(8'h64); repeat(TURN_CYCLES) @(posedge clk);  // d
        // move down into the monster -> combat; repeat to kill it
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s (attack)
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s
        send_byte(8'h73); repeat(TURN_CYCLES) @(posedge clk);  // s

        // let the final render + win banner flush
        repeat(TURN_CYCLES*2) @(posedge clk);

        // ---- assertions ----
        $display("captured %0d tx bytes", log_len);
        if (!has_byte(8'h40)) begin $display("  missing '@' (player glyph / render)"); fails = fails + 1; end
        if (!has_byte(8'h4D)) begin $display("  missing 'M' (monster / render)");      fails = fails + 1; end
        if (!has_cmd(0))          begin $display("  missing 'cmd' prompt");            fails = fails + 1; end
        if (!has_hit(0))          begin $display("  missing 'hit' (combat / MUL)");    fails = fails + 1; end
        if (!has_you_win(0))      begin $display("  missing 'YOU WIN' (win branch)");  fails = fails + 1; end

        if (fails == 0) $display("DUNGEON PASS");
        else begin
            $display("DUNGEON FAIL (%0d missing)", fails);
            $write("--- captured log preview ---\n");
            for (i = 0; i < (log_len < 600 ? log_len : 600); i = i + 1)
                $write("%c", log[i]);
            $write("\n--- end preview ---\n");
        end
        $finish;
    end
endmodule
