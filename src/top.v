//==================================================
// 顶层模块 - TEC-PLUS 核心板
// CPU 通过内存映射 IO (MMIO) 自己驱动 UART 和 LED,
// 并运行板端 shell/CNN/Pong/Paint 固件 (程序见 asm/soc_firmware.s)。
//
// 数据总线地址空间 (字节地址):
//   0x000 - 0xFFF : 数据 RAM  (1024 字, 字节写; 含 CNN float32 权重)
//   0x1000 UART_TX : 写一个字节 -> 串口发送
//   0x1004 UART_RX : 读 -> 收到的字节; 写 -> 应答 (清 rx_pending)
//   0x1008 UART_STAT: 读 -> {30'b0, tx_busy, rx_pending}
//   0x100C LED_OUT  : 写 -> LED[3:0]
//   0x1010 KEY_IN   : 读 -> {28'b0, ~key4, ~key3, ~key2, ~key1} (按下为1)
//   0x1014 IRQ_ENABLE, 0x1018 IRQ_PENDING, 0x1040 SDRAM_STATUS
//   0x101C-0x103C   : CPU/I-Cache performance counters
//   0x10000000-0x13FFFFFF : dual HY57V2562 SDRAM (64 MiB, 32-bit)
//==================================================
`ifdef __ICARUS__
// Spartan-6 primitive model used only by Icarus simulation.
module BUFG(input wire I, output wire O);
    assign O = I;
endmodule

module ODDR2 #(
    parameter DDR_ALIGNMENT = "NONE",
    parameter INIT = 1'b0,
    parameter SRTYPE = "ASYNC"
)(
    output wire Q,
    input wire C0, C1, CE, D0, D1, R, S
);
    assign Q = R ? INIT : S ? 1'b1 : CE ? (C0 ? D0 : D1) : INIT;
endmodule
`endif

module top #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD     = 115200,
    parameter USE_2WAY_ICACHE = 1,
    parameter PONG_TICK_CYCLES = (CLK_FREQ / 4) / 4
)(
    input  wire clk,        // 核心板50MHz时钟 (T8)
    input  wire rst_n,      // 核心板RESET按键, 低有效 (L3)
    input  wire key1,       // 核心板KEY1, 按下为0
    input  wire key2,       // 核心板KEY2, 按下为0
    input  wire key3,       // 核心板KEY3, 按下为0
    input  wire key4,       // 核心板KEY4, 按下为0
    input  wire uart_rx,    // CP2102 RXD -> FPGA
    output wire uart_tx,    // FPGA -> CP2102 TXD
    output wire led1,       // 核心板LED1
    output wire led2,       // 核心板LED2
    output wire led3,       // 核心板LED3
    output wire led4,       // 核心板LED4

    output wire sh_clk, output wire sh_cke, output wire sh_ncs,
    output wire sh_nwe, output wire sh_ncas, output wire sh_nras,
    output wire [1:0] sh_dqm, output wire [1:0] sh_ba,
    output wire [12:0] sh_a, inout wire [15:0] sh_db,
    output wire sl_clk, output wire sl_cke, output wire sl_ncs,
    output wire sl_nwe, output wire sl_ncas, output wire sl_nras,
    output wire [1:0] sl_dqm, output wire [1:0] sl_ba,
    output wire [12:0] sl_a, inout wire [15:0] sl_db
);

    localparam SYS_CLK_FREQ = CLK_FREQ / 4;
    localparam CLKS_PER_BIT = SYS_CLK_FREQ / BAUD;

    // The board oscillator remains 50 MHz, while the complete SoC runs from a
    // single 12.5 MHz global clock. The extra margin is intentional: physical
    // tests showed data-path bit errors at 25 MHz despite functional RTL sims.
    reg [1:0] clk_div4 = 2'b00;
    // Keep the generated clock running during reset so every downstream
    // sequential block observes reset even when rst_n starts low at power-up.
    always @(posedge clk)
        clk_div4 <= clk_div4 + 1'b1;
    wire sys_clk;
    BUFG u_sys_clk_buf (.I(clk_div4[1]), .O(sys_clk));

    // Assert reset asynchronously, but release it synchronously in the only
    // clock domain used by the SoC. This prevents different pipeline/cache/RAM
    // registers leaving reset on different edges after the mechanical button.
    reg [2:0] reset_sync = 3'b000;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            reset_sync <= 3'b000;
        else
            reset_sync <= {reset_sync[1:0], 1'b1};
    end
    wire sys_rst_n = reset_sync[2];

    //----------------------------------------------
    // CPU 数据/取指总线
    //----------------------------------------------
    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_valid;
    wire [31:0] instr_rom_addr;
    wire [31:0] instr_rom_data;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;

    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire        data_valid;
    wire        data_we;
    wire [31:0] data_rdata;
    wire        data_ready;

    wire        halt;
    wire [31:0] perf_cycle;
    wire [31:0] perf_instret;
    wire [31:0] perf_branch;
    wire [31:0] perf_flush;
    wire [31:0] perf_load_use_stall;
    wire [31:0] perf_bp_miss;
    wire [31:0] perf_mdu_inst;
    wire        irq_line;

    //----------------------------------------------
    // 五级流水线 CPU (perf 计数器输出此处不用, 留空)
    //----------------------------------------------
    riscv_pipeline_core u_cpu (
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .instr_addr (instr_addr),
        .instr_data (instr_data),
        .instr_valid(instr_valid),
        .data_addr  (data_addr),
        .data_wdata (data_wdata),
        .data_be    (data_be),
        .data_valid (data_valid),
        .data_we    (data_we),
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        .irq_external(irq_line),
        .halt       (halt),
        .perf_cycle (perf_cycle),
        .perf_instret(perf_instret),
        .perf_branch(perf_branch),
        .perf_flush (perf_flush),
        .perf_load_use_stall(perf_load_use_stall),
        .perf_bp_miss(perf_bp_miss),
        .perf_mdu_inst(perf_mdu_inst)
    );

    //----------------------------------------------
    // 指令 ROM (异步读) + 直接映射 I-Cache
    //----------------------------------------------
    reg [31:0] instr_mem [0:2047];
    assign instr_rom_data = instr_mem[instr_rom_addr[12:2]];

    generate
        if (USE_2WAY_ICACHE) begin : gen_icache_2way
            icache_2way #(
                .LINES(8)
            ) u_icache (
                .clk        (sys_clk),
                .rst_n      (sys_rst_n),
                .cpu_addr   (instr_addr),
                .mem_addr   (instr_rom_addr),
                .mem_data   (instr_rom_data),
                .cpu_data   (instr_data),
                .cpu_valid  (instr_valid),
                .hit_count  (icache_hit_count),
                .miss_count (icache_miss_count)
            );
        end else begin : gen_icache_direct
            icache_direct_mapped #(
                .LINES(8)
            ) u_icache (
                .clk        (sys_clk),
                .rst_n      (sys_rst_n),
                .cpu_addr   (instr_addr),
                .mem_addr   (instr_rom_addr),
                .mem_data   (instr_rom_data),
                .cpu_data   (instr_data),
                .cpu_valid  (instr_valid)
            );
            assign icache_hit_count  = 32'd0;
            assign icache_miss_count = 32'd0;
        end
    endgenerate

    //----------------------------------------------
    // 数据 RAM (1024 字, 按字节拆成 4 个字节宽阵列
    // 以便 XST 稳定推断为分布式 RAM) + MMIO 译码
    //
    //   RAM 区域 : 0x00000000-0x00000FFF
    //   IO  区域 : 0x00001000-0x00001043
    //   SDRAM    : 0x10000000-0x13FFFFFF
    //----------------------------------------------
    reg [7:0] data_mem_b0 [0:1023];
    reg [7:0] data_mem_b1 [0:1023];
    reg [7:0] data_mem_b2 [0:1023];
    reg [7:0] data_mem_b3 [0:1023];

    wire        ram_sel  = (data_addr[31:12] == 20'b0);
    wire        sdram_sel = (data_addr[31:26] == 6'h04);
    wire [9:0]  data_idx = data_addr[11:2];
    wire        io_sel   = (data_addr[31:12] == 20'h00001);
    wire [11:0] io_word  = data_addr[13:2];   // 0x1000->0x400, 0x1004->0x401 ...
    wire        is_tx    = io_sel & (io_word == 12'h400); // 0x1000
    wire        is_rx    = io_sel & (io_word == 12'h401); // 0x1004
    wire        is_stat  = io_sel & (io_word == 12'h402); // 0x1008
    wire        is_led   = io_sel & (io_word == 12'h403); // 0x100C
    wire        is_key   = io_sel & (io_word == 12'h404); // 0x1010
    wire        is_irq_en  = io_sel & (io_word == 12'h405); // 0x1014
    wire        is_irq_pnd = io_sel & (io_word == 12'h406); // 0x1018
    wire        is_perf_cycle = io_sel & (io_word == 12'h407); // 0x101C
    wire        is_perf_inst  = io_sel & (io_word == 12'h408); // 0x1020
    wire        is_perf_br    = io_sel & (io_word == 12'h409); // 0x1024
    wire        is_perf_fl    = io_sel & (io_word == 12'h40A); // 0x1028
    wire        is_perf_stall = io_sel & (io_word == 12'h40B); // 0x102C
    wire        is_perf_bpm   = io_sel & (io_word == 12'h40C); // 0x1030
    wire        is_perf_mdu   = io_sel & (io_word == 12'h40D); // 0x1034
    wire        is_ic_hit     = io_sel & (io_word == 12'h40E); // 0x1038
    wire        is_ic_miss    = io_sel & (io_word == 12'h40F); // 0x103C
    wire        is_sdram_stat = io_sel & (io_word == 12'h410); // 0x1040

    always @(posedge sys_clk) begin
        if (ram_sel && data_we && data_be[0]) data_mem_b0[data_idx] <= data_wdata[7:0];
        if (ram_sel && data_we && data_be[1]) data_mem_b1[data_idx] <= data_wdata[15:8];
        if (ram_sel && data_we && data_be[2]) data_mem_b2[data_idx] <= data_wdata[23:16];
        if (ram_sel && data_we && data_be[3]) data_mem_b3[data_idx] <= data_wdata[31:24];
    end

    wire [31:0] ram_rdata = {data_mem_b3[data_idx], data_mem_b2[data_idx],
                             data_mem_b1[data_idx], data_mem_b0[data_idx]};

    //----------------------------------------------
    // UART 收发器 (直接挂在 MMIO 上)
    //----------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;
    reg [7:0]  rx_byte;
    reg        rx_pending;
    reg [3:0]  led_out;
    reg [2:0]  irq_enable;
    reg [2:0]  irq_pending_mmio;
    reg [31:0] pong_tick_counter;
    reg [3:0]  key_prev;
    wire [3:0] key_pressed = {~key4, ~key3, ~key2, ~key1};

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk(sys_clk), .rst_n(sys_rst_n), .rx(uart_rx), .data(rx_data), .valid(rx_valid)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(sys_clk), .rst_n(sys_rst_n), .start(tx_start), .data(tx_data),
        .tx(uart_tx), .busy(tx_busy)
    );

    // MMIO 寄存器: rx 锁存 (valid 是单拍脉冲, 需要粘住的 rx_pending);
    // CPU 写 UART_RX 作为应答, 清除 rx_pending (无需读选通, 不用改 CPU 核)。
    // 写 UART_TX 启动发送; 写 LED_OUT 驱动 LED。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_byte    <= 8'd0;
            rx_pending <= 1'b0;
            tx_data    <= 8'd0;
            tx_start   <= 1'b0;
            led_out    <= 4'd0;
            irq_enable <= 3'b000;
            irq_pending_mmio <= 3'b000;
            pong_tick_counter <= 32'd0;
            key_prev <= 4'b0000;
        end else begin
            tx_start <= 1'b0;                       // 默认单拍脉冲
            if (rx_valid) begin
                rx_byte    <= rx_data;
                rx_pending <= 1'b1;
                irq_pending_mmio[0] <= 1'b1;
            end
            key_prev <= key_pressed;
            if (|(key_pressed & ~key_prev))
                irq_pending_mmio[1] <= 1'b1;
            if (!irq_enable[2]) begin
                pong_tick_counter <= 32'd0;
            end else if (pong_tick_counter == PONG_TICK_CYCLES - 1) begin
                pong_tick_counter <= 32'd0;
                irq_pending_mmio[2] <= 1'b1;
            end else begin
                pong_tick_counter <= pong_tick_counter + 32'd1;
            end
            if (is_rx && data_we) begin             // 写 UART_RX = 应答
                rx_pending <= 1'b0;
            end
            if (is_tx && data_we && !tx_busy && !tx_start) begin
                tx_data  <= data_wdata[7:0];
                tx_start <= 1'b1;
            end
            if (is_led && data_we) begin
                led_out <= data_wdata[3:0];
            end
            if (is_irq_en && data_we)
                irq_enable <= data_wdata[2:0];
            if (is_irq_pnd && data_we)
                irq_pending_mmio <= irq_pending_mmio & ~data_wdata[2:0];
        end
    end

    assign irq_line = |(irq_enable & irq_pending_mmio);

    //----------------------------------------------
    // Two HY57V2562 x16 devices operate in parallel as x32 SDRAM.
    //----------------------------------------------
    wire sdram_cke_i, sdram_cs_n_i;
    wire sdram_ras_n_i, sdram_cas_n_i, sdram_we_n_i;
    wire [12:0] sdram_addr_i;
    wire [1:0] sdram_ba_i;
    wire [3:0] sdram_dqm_i;
    wire [31:0] sdram_rdata;
    wire sdram_ready, sdram_init_done;
    wire [31:0] sdram_refresh_count;

    sdram_controller #(.CLK_FREQ_HZ(SYS_CLK_FREQ)) u_sdram (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .req(data_valid && sdram_sel), .we(data_we),
        .addr(data_addr[25:0]), .wdata(data_wdata), .be(data_be),
        .rdata(sdram_rdata), .ready(sdram_ready),
        .init_done(sdram_init_done), .refresh_count(sdram_refresh_count),
        .sdram_clk(), .sdram_cke(sdram_cke_i),
        .sdram_cs_n(sdram_cs_n_i), .sdram_ras_n(sdram_ras_n_i),
        .sdram_cas_n(sdram_cas_n_i), .sdram_we_n(sdram_we_n_i),
        .sdram_addr(sdram_addr_i), .sdram_ba(sdram_ba_i),
        .sdram_dqm(sdram_dqm_i), .sdram_dq({sh_db, sl_db})
    );

    // Dedicated output DDR cells forward an inverted system clock.  Commands
    // change on sys_clk's rising edge and are captured by SDRAM half a cycle
    // later, without routing the BUFG net through an ordinary LUT/OBUF path.
    ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("ASYNC"))
    u_sh_clk_fwd (
        .Q(sh_clk), .C0(sys_clk), .C1(~sys_clk), .CE(1'b1),
        .D0(1'b0), .D1(1'b1), .R(~sys_rst_n), .S(1'b0)
    );
    ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("ASYNC"))
    u_sl_clk_fwd (
        .Q(sl_clk), .C0(sys_clk), .C1(~sys_clk), .CE(1'b1),
        .D0(1'b0), .D1(1'b1), .R(~sys_rst_n), .S(1'b0)
    );
    assign sh_cke = sdram_cke_i; assign sl_cke = sdram_cke_i;
    assign sh_ncs = sdram_cs_n_i; assign sl_ncs = sdram_cs_n_i;
    assign sh_nras = sdram_ras_n_i; assign sl_nras = sdram_ras_n_i;
    assign sh_ncas = sdram_cas_n_i; assign sl_ncas = sdram_cas_n_i;
    assign sh_nwe = sdram_we_n_i; assign sl_nwe = sdram_we_n_i;
    assign sh_a = sdram_addr_i; assign sl_a = sdram_addr_i;
    assign sh_ba = sdram_ba_i; assign sl_ba = sdram_ba_i;
    assign sh_dqm = sdram_dqm_i[3:2]; assign sl_dqm = sdram_dqm_i[1:0];

    wire [31:0] io_rdata =
        is_rx   ? {24'b0, rx_byte} :
        // tx_start bridges the one-cycle handoff into uart_tx.  Reporting it
        // as busy prevents software from issuing another byte in that window.
        is_stat ? {30'b0, (tx_busy | tx_start), rx_pending} :
        is_key  ? {28'b0, ~key4, ~key3, ~key2, ~key1} :
        is_irq_en  ? {29'b0, irq_enable} :
        is_irq_pnd ? {29'b0, irq_pending_mmio} :
        is_perf_cycle ? perf_cycle :
        is_perf_inst  ? perf_instret :
        is_perf_br    ? perf_branch :
        is_perf_fl    ? perf_flush :
        is_perf_stall ? perf_load_use_stall :
        is_perf_bpm   ? perf_bp_miss :
        is_perf_mdu   ? perf_mdu_inst :
        is_ic_hit     ? icache_hit_count :
        is_ic_miss    ? icache_miss_count :
        is_sdram_stat ? {sdram_refresh_count[30:0], sdram_init_done} :
                  32'b0;

    assign data_rdata = ram_sel ? ram_rdata : sdram_sel ? sdram_rdata : io_rdata;
    // UART TX stores use a real ready/valid handshake. If software reaches the
    // store while TX is busy, the CPU keeps that store in EX/MEM until the
    // byte can be accepted; no character can be silently dropped.
    wire tx_store_wait = data_valid && data_we && is_tx && (tx_busy || tx_start);
    assign data_ready = sdram_sel ? sdram_ready : !tx_store_wait;

    //----------------------------------------------
    // 指令 ROM 初始化: NOP 填充 + 数据 RAM 清零 + MNIST8 float32 模型/程序
//----------------------------------------------
    integer j;
    initial begin
        for (j = 0; j < 2048; j = j + 1) instr_mem[j] = 32'h00000013; // NOP
        for (j = 0; j < 1024; j = j + 1) begin
            data_mem_b0[j] = 8'h0;
            data_mem_b1[j] = 8'h0;
            data_mem_b2[j] = 8'h0;
            data_mem_b3[j] = 8'h0;
        end
`include "src/cnn_weights.vh"
`include "src/soc_firmware.vh"
    end

    //----------------------------------------------
    // LED 输出 (由 CPU 通过 LED_OUT MMIO 写入控制)
//----------------------------------------------
    localparam LED_ACTIVE_LOW = 1'b0;   // TEC-PLUS LED 通常高电平点亮
    wire [3:0] led_drive = LED_ACTIVE_LOW ? ~led_out : led_out;
    assign led1 = led_drive[0];
    assign led2 = led_drive[1];
    assign led3 = led_drive[2];
    assign led4 = led_drive[3];

endmodule
