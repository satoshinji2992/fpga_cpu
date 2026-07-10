//==================================================
// 顶层模块 - TEC-PLUS 核心板
// CPU 通过内存映射 IO (MMIO) 自己驱动 UART 和 LED,
// 并运行一个 8x8 手写数字推理 demo (程序见 asm/cnn_digit.s)。
//
// 数据总线地址空间 (字节地址):
//   0x000 - 0xFFF : 数据 RAM  (1024 字, 字节写; 含 CNN float32 权重)
//   0x1000 UART_TX : 写一个字节 -> 串口发送
//   0x1004 UART_RX : 读 -> 收到的字节; 写 -> 应答 (清 rx_pending)
//   0x1008 UART_STAT: 读 -> {30'b0, tx_busy, rx_pending}
//   0x100C LED_OUT  : 写 -> LED[3:0]
//   0x1010 KEY_IN   : 读 -> {28'b0, ~key4, ~key3, ~key2, ~key1} (按下为1)
//   0x1014 IC_HIT   : 读 -> I-Cache hit 计数
//   0x1018 IC_MISS  : 读 -> I-Cache miss 计数
//   0x2000_0000     : 片上扩展存储窗口 (保留 SDRAM 地址语义, 通过 ready 建模慢存储)
//==================================================
module top #(
    parameter CLK_FREQ         = 10000000,  // 10MHz 分频后时钟
    parameter BAUD             = 115200,
    parameter USE_2WAY_ICACHE  = 0,
    parameter USE_SDRAM_WINDOW = 1,
    parameter SDRAM_LATENCY    = 4,
    parameter SDRAM_AW         = 6
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
    output wire led4        // 核心板LED4
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam CLK_DIVIDER = 5;  // 50MHz -> 10MHz

    //----------------------------------------------
    // 时钟分频 (50MHz -> 10MHz)
    //----------------------------------------------
    reg [2:0] clk_div_cnt;
    reg clk_div;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cnt <= 3'd0;
            clk_div <= 1'b0;
        end else begin
            if (clk_div_cnt == CLK_DIVIDER - 1) begin
                clk_div_cnt <= 3'd0;
                clk_div <= ~clk_div;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
            end
        end
    end

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
    wire        data_we;
    wire        data_valid;
    wire [31:0] data_rdata;
    wire        data_ready;

    wire        halt;

    //----------------------------------------------
    // 五级流水线 CPU (perf 计数器输出此处不用, 留空)
    //----------------------------------------------
    riscv_pipeline_core u_cpu (
        .clk        (clk_div),
        .rst_n      (rst_n),
        .instr_addr (instr_addr),
        .instr_data (instr_data),
        .instr_valid(instr_valid),
        .data_addr  (data_addr),
        .data_wdata (data_wdata),
        .data_be    (data_be),
        .data_we    (data_we),
        .data_valid (data_valid),
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        .halt       (halt)
    );

    //----------------------------------------------
    // 指令 ROM (异步读) + 直接映射 I-Cache
    //----------------------------------------------
    reg [31:0] instr_mem [0:1023];
    assign instr_rom_data = instr_mem[instr_rom_addr[11:2]];

    generate
        if (USE_2WAY_ICACHE) begin : gen_icache_2way
            icache_2way #(
                .LINES(8)
            ) u_icache (
                .clk        (clk_div),
                .rst_n      (rst_n),
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
                .clk        (clk_div),
                .rst_n      (rst_n),
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
    //   RAM   区域 : data_addr[31:12] == 0         (0x0000_0000-0x0000_0FFF)
    //   SDRAM 区域 : data_addr[31:12] == 20'h20000 (当前仅实现低 64 words 的片上验证窗口)
    //   IO    区域 : 其余 (0x1000+)
    //----------------------------------------------
    reg [7:0] data_mem_b0 [0:1023];
    reg [7:0] data_mem_b1 [0:1023];
    reg [7:0] data_mem_b2 [0:1023];
    reg [7:0] data_mem_b3 [0:1023];
    reg [7:0] sdram_mem_b0 [0:(1<<SDRAM_AW)-1];
    reg [7:0] sdram_mem_b1 [0:(1<<SDRAM_AW)-1];
    reg [7:0] sdram_mem_b2 [0:(1<<SDRAM_AW)-1];
    reg [7:0] sdram_mem_b3 [0:(1<<SDRAM_AW)-1];
    reg       sdram_pending;
    reg [7:0] sdram_wait_ctr;
    reg [SDRAM_AW-1:0] sdram_req_idx;
    reg [31:0] sdram_req_wdata;
    reg [3:0]  sdram_req_be;
    reg        sdram_req_we;

    wire        ram_sel   = data_valid && (data_addr[31:12] == 20'b0);
    wire        sdram_sel = data_valid && USE_SDRAM_WINDOW && (data_addr[31:12] == 20'h20000);
    wire [9:0]  data_idx = data_addr[11:2];
    wire [SDRAM_AW-1:0] sdram_data_idx = data_addr[SDRAM_AW+1:2];
    wire        io_sel   = data_valid && ~ram_sel && ~sdram_sel;
    wire [11:0] io_word  = data_addr[13:2];   // 0x1000->0x400, 0x1004->0x401 ...
    wire        is_tx    = io_sel & (io_word == 12'h400); // 0x1000
    wire        is_rx    = io_sel & (io_word == 12'h401); // 0x1004
    wire        is_stat  = io_sel & (io_word == 12'h402); // 0x1008
    wire        is_led   = io_sel & (io_word == 12'h403); // 0x100C
    wire        is_key   = io_sel & (io_word == 12'h404); // 0x1010
    wire        is_hit   = io_sel & (io_word == 12'h405); // 0x1014
    wire        is_miss  = io_sel & (io_word == 12'h406); // 0x1018
    wire [SDRAM_AW-1:0] sdram_idx = sdram_pending ? sdram_req_idx : sdram_data_idx;
    wire        sdram_ready = sdram_sel &&
                              (sdram_pending ? (sdram_wait_ctr == 8'd0) :
                                               (SDRAM_LATENCY == 0));

    always @(posedge clk_div) begin
        if (ram_sel && data_we && data_be[0]) data_mem_b0[data_idx] <= data_wdata[7:0];
        if (ram_sel && data_we && data_be[1]) data_mem_b1[data_idx] <= data_wdata[15:8];
        if (ram_sel && data_we && data_be[2]) data_mem_b2[data_idx] <= data_wdata[23:16];
        if (ram_sel && data_we && data_be[3]) data_mem_b3[data_idx] <= data_wdata[31:24];
    end

    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            sdram_pending  <= 1'b0;
            sdram_wait_ctr <= 8'd0;
            sdram_req_idx  <= {SDRAM_AW{1'b0}};
            sdram_req_wdata <= 32'd0;
            sdram_req_be   <= 4'd0;
            sdram_req_we   <= 1'b0;
        end else if (!USE_SDRAM_WINDOW) begin
            sdram_pending  <= 1'b0;
            sdram_wait_ctr <= 8'd0;
            sdram_req_idx  <= {SDRAM_AW{1'b0}};
            sdram_req_wdata <= 32'd0;
            sdram_req_be   <= 4'd0;
            sdram_req_we   <= 1'b0;
        end else if (!sdram_pending) begin
            if (sdram_sel) begin
                if (SDRAM_LATENCY == 0) begin
                    if (data_we && data_be[0]) sdram_mem_b0[sdram_data_idx] <= data_wdata[7:0];
                    if (data_we && data_be[1]) sdram_mem_b1[sdram_data_idx] <= data_wdata[15:8];
                    if (data_we && data_be[2]) sdram_mem_b2[sdram_data_idx] <= data_wdata[23:16];
                    if (data_we && data_be[3]) sdram_mem_b3[sdram_data_idx] <= data_wdata[31:24];
                end else begin
                    sdram_pending  <= 1'b1;
                    sdram_wait_ctr <= SDRAM_LATENCY - 1;
                    sdram_req_idx  <= sdram_data_idx;
                    sdram_req_wdata <= data_wdata;
                    sdram_req_be   <= data_be;
                    sdram_req_we   <= data_we;
                end
            end
        end else if (sdram_ready) begin
            if (sdram_req_we && sdram_req_be[0]) sdram_mem_b0[sdram_req_idx] <= sdram_req_wdata[7:0];
            if (sdram_req_we && sdram_req_be[1]) sdram_mem_b1[sdram_req_idx] <= sdram_req_wdata[15:8];
            if (sdram_req_we && sdram_req_be[2]) sdram_mem_b2[sdram_req_idx] <= sdram_req_wdata[23:16];
            if (sdram_req_we && sdram_req_be[3]) sdram_mem_b3[sdram_req_idx] <= sdram_req_wdata[31:24];
            sdram_pending <= 1'b0;
        end else begin
            sdram_wait_ctr <= sdram_wait_ctr - 8'd1;
        end
    end

    wire [31:0] ram_rdata = {data_mem_b3[data_idx], data_mem_b2[data_idx],
                             data_mem_b1[data_idx], data_mem_b0[data_idx]};
    wire [31:0] sdram_rdata = {sdram_mem_b3[sdram_idx], sdram_mem_b2[sdram_idx],
                               sdram_mem_b1[sdram_idx], sdram_mem_b0[sdram_idx]};

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

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk(clk_div), .rst_n(rst_n), .rx(uart_rx), .data(rx_data), .valid(rx_valid)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(clk_div), .rst_n(rst_n), .start(tx_start), .data(tx_data),
        .tx(uart_tx), .busy(tx_busy)
    );

    // MMIO 寄存器: rx 锁存 (valid 是单拍脉冲, 需要粘住的 rx_pending);
    // CPU 写 UART_RX 作为应答, 清除 rx_pending (无需读选通, 不用改 CPU 核)。
    // 写 UART_TX 启动发送; 写 LED_OUT 驱动 LED。
    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            rx_byte    <= 8'd0;
            rx_pending <= 1'b0;
            tx_data    <= 8'd0;
            tx_start   <= 1'b0;
            led_out    <= 4'd0;
        end else begin
            tx_start <= 1'b0;                       // 默认单拍脉冲
            if (rx_valid) begin
                rx_byte    <= rx_data;
                rx_pending <= 1'b1;
            end
            if (is_rx && data_we) begin             // 写 UART_RX = 应答
                rx_pending <= 1'b0;
            end
            if (is_tx && data_we) begin
                tx_data  <= data_wdata[7:0];
                tx_start <= 1'b1;
            end
            if (is_led && data_we) begin
                led_out <= data_wdata[3:0];
            end
        end
    end

    wire [31:0] io_rdata =
        is_rx   ? {24'b0, rx_byte} :
        is_stat ? {30'b0, tx_busy, rx_pending} :
        is_key  ? {28'b0, ~key4, ~key3, ~key2, ~key1} :
        is_hit  ? icache_hit_count :
        is_miss ? icache_miss_count :
                  32'b0;

    assign data_rdata = ram_sel   ? ram_rdata :
                        sdram_sel ? sdram_rdata :
                                    io_rdata;
    assign data_ready = !data_valid ? 1'b1 :
                        ram_sel     ? 1'b1 :
                        io_sel      ? 1'b1 :
                        sdram_sel   ? sdram_ready :
                                      1'b1;

    //----------------------------------------------
    // 指令 ROM 初始化: NOP 填充 + 数据 RAM 清零 + MNIST8 float32 模型/程序
//----------------------------------------------
    integer j;
    integer k;
    initial begin
        for (j = 0; j < 1024; j = j + 1) instr_mem[j] = 32'h00000013; // NOP
        for (j = 0; j < 1024; j = j + 1) begin
            data_mem_b0[j] = 8'h0;
            data_mem_b1[j] = 8'h0;
            data_mem_b2[j] = 8'h0;
            data_mem_b3[j] = 8'h0;
        end
        for (k = 0; k < (1<<SDRAM_AW); k = k + 1) begin
            sdram_mem_b0[k] = 8'h0;
            sdram_mem_b1[k] = 8'h0;
            sdram_mem_b2[k] = 8'h0;
            sdram_mem_b3[k] = 8'h0;
        end
`include "src/cnn_weights.vh"
`ifdef SDRAM_DIAG_PROGRAM
`include "src/sdram_diag_prog.vh"
`else
`include "src/cnn_prog.vh"
`endif
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
