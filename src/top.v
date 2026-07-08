//==================================================
// 顶层模块 - TEC-PLUS 核心板
// CPU 通过内存映射 IO (MMIO) 自己驱动 UART 和 LED,
// 并运行一个回合制地牢游戏 (程序见 asm/dungeon.s)。
//
// 数据总线地址空间 (字节地址):
//   0x000 - 0x3FF : 数据 RAM  (256 字, 字节写)
//   0x400 UART_TX : 写一个字节 -> 串口发送
//   0x404 UART_RX : 读 -> 收到的字节; 写 -> 应答 (清 rx_pending)
//   0x408 UART_STAT: 读 -> {30'b0, tx_busy, rx_pending}
//   0x40C LED_OUT  : 写 -> LED[3:0]
//   0x410 KEY_IN   : 读 -> {28'b0, ~key4, ~key3, ~key2, ~key1} (按下为1)
// CPU 核心不做任何修改: MMIO 读是组合逻辑, data_ready 恒为 1。
//==================================================
module top #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD     = 115200
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

    //----------------------------------------------
    // CPU 数据/取指总线
    //----------------------------------------------
    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_valid;
    wire [31:0] instr_rom_addr;
    wire [31:0] instr_rom_data;

    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire        data_we;
    wire [31:0] data_rdata;
    wire        data_ready;

    wire        halt;

    //----------------------------------------------
    // 五级流水线 CPU (perf 计数器输出此处不用, 留空)
    //----------------------------------------------
    riscv_pipeline_core u_cpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr_addr (instr_addr),
        .instr_data (instr_data),
        .instr_valid(instr_valid),
        .data_addr  (data_addr),
        .data_wdata (data_wdata),
        .data_be    (data_be),
        .data_we    (data_we),
        .data_rdata (data_rdata),
        .data_ready (data_ready),
        .halt       (halt)
    );

    //----------------------------------------------
    // 指令 ROM (异步读) + 直接映射 I-Cache
    //----------------------------------------------
    reg [31:0] instr_mem [0:1023];
    assign instr_rom_data = instr_mem[instr_rom_addr[11:2]];

    icache_direct_mapped #(
        .LINES(8)
    ) u_icache (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_addr   (instr_addr),
        .mem_addr   (instr_rom_addr),
        .mem_data   (instr_rom_data),
        .cpu_data   (instr_data),
        .cpu_valid  (instr_valid)
    );

    //----------------------------------------------
    // 数据 RAM (256 字, 按字节拆成 4 个字节宽阵列
    // 以便 XST 稳定推断为分布式 RAM) + MMIO 译码
    //
    //   RAM 区域 : data_addr[31:10] == 0  (0x000-0x3FF)
    //   IO  区域 : 其余 (0x400+)
    //----------------------------------------------
    reg [7:0] data_mem_b0 [0:255];
    reg [7:0] data_mem_b1 [0:255];
    reg [7:0] data_mem_b2 [0:255];
    reg [7:0] data_mem_b3 [0:255];

    wire        ram_sel  = (data_addr[31:10] == 22'b0);
    wire [7:0]  data_idx = data_addr[9:2];
    wire        io_sel   = ~ram_sel;
    wire [9:0]  io_word  = data_addr[11:2];   // 0x400->0x100, 0x404->0x101 ...
    wire        is_tx    = io_sel & (io_word == 10'h100); // 0x400
    wire        is_rx    = io_sel & (io_word == 10'h101); // 0x404
    wire        is_stat  = io_sel & (io_word == 10'h102); // 0x408
    wire        is_led   = io_sel & (io_word == 10'h103); // 0x40C
    wire        is_key   = io_sel & (io_word == 10'h104); // 0x410

    always @(posedge clk) begin
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

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data), .valid(rx_valid)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data),
        .tx(uart_tx), .busy(tx_busy)
    );

    // MMIO 寄存器: rx 锁存 (valid 是单拍脉冲, 需要粘住的 rx_pending);
    // CPU 写 UART_RX 作为应答, 清除 rx_pending (无需读选通, 不用改 CPU 核)。
    // 写 UART_TX 启动发送; 写 LED_OUT 驱动 LED。
    always @(posedge clk or negedge rst_n) begin
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
                  32'b0;

    assign data_rdata = ram_sel ? ram_rdata : io_rdata;
    assign data_ready = 1'b1;

    //----------------------------------------------
    // 指令 ROM 初始化: NOP 填充 + 数据 RAM 清零 + 游戏程序
//----------------------------------------------
    integer j;
    initial begin
        for (j = 0; j < 1024; j = j + 1) instr_mem[j] = 32'h00000013; // NOP
        for (j = 0; j < 256; j = j + 1) begin
            data_mem_b0[j] = 8'h0;
            data_mem_b1[j] = 8'h0;
            data_mem_b2[j] = 8'h0;
            data_mem_b3[j] = 8'h0;
        end
`include "src/dungeon_prog.vh"
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
