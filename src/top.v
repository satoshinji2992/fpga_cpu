//==================================================
// 顶层模块 - TEC-PLUS 核心板独立运行版
// 功能: CPU执行固化测试程序, 通过核心板4个LED显示验证结果
//==================================================
module top (
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

    //----------------------------------------------
    // 时钟分频 (产生慢速时钟, 让LED可见)
    // 核心板50MHz时钟较快, 用计数器降频便于观察
    //----------------------------------------------
    reg [24:0] clk_cnt;
    wire clk_slow;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_cnt <= 25'd0;
        else
            clk_cnt <= clk_cnt + 25'd1;
    end

    assign clk_slow = clk_cnt[22];

    //----------------------------------------------
    // 指令存储器 (ROM, 固化测试程序)
    //----------------------------------------------
    reg [31:0] instr_mem [0:63];

    // CPU取指信号
    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_valid;

    // 数据存储器信号
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire        data_we;
    wire [31:0] data_rdata;
    wire        data_ready;

    wire        halt;

    //----------------------------------------------
    // CPU实例
    //----------------------------------------------
    riscv_core u_cpu (
        .clk        (clk_slow),
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
    // 指令存储器 (异步读取)
    //----------------------------------------------
    assign instr_data  = instr_mem[instr_addr[7:2]];
    assign instr_valid = 1'b1;

    //----------------------------------------------
    // 数据存储器
    //----------------------------------------------
    reg [31:0] data_mem [0:63];
    wire [31:0] mem0;
    wire [31:0] mem1;
    wire [31:0] mem2;
    wire        test_pass;

    always @(posedge clk_slow) begin
        if (data_we) begin
            if (data_be[0]) data_mem[data_addr[7:2]][7:0]   <= data_wdata[7:0];
            if (data_be[1]) data_mem[data_addr[7:2]][15:8]  <= data_wdata[15:8];
            if (data_be[2]) data_mem[data_addr[7:2]][23:16] <= data_wdata[23:16];
            if (data_be[3]) data_mem[data_addr[7:2]][31:24] <= data_wdata[31:24];
        end
    end

    assign data_rdata = data_mem[data_addr[7:2]];
    assign data_ready = 1'b1;
    assign mem0 = data_mem[0];
    assign mem1 = data_mem[1];
    assign mem2 = data_mem[2];
    assign test_pass = halt &&
                       (mem0 == 32'h3480_1200) &&
                       (mem1 == 32'h0000_FFFE) &&
                       (mem2 == 32'd2);

    //----------------------------------------------
    // 串口交互Shell (115200 8N1)
    //----------------------------------------------
    serial_shell #(
        .CLK_FREQ(50000000),
        .BAUD    (115200)
    ) u_shell (
        .clk       (clk),
        .rst_n     (rst_n),
        .rx        (uart_rx),
        .tx        (uart_tx),
        .halt      (halt),
        .test_pass (test_pass),
        .mem0      (mem0),
        .mem1      (mem1),
        .mem2      (mem2)
    );

    //----------------------------------------------
    // 固化测试程序到指令ROM
    // 结束后:
    //   Mem[0] = 32'h3480_1200, 验证SB/LB/LBU
    //   Mem[1] = 32'h0000_FFFE, 验证SH/LH/LHU
    //   Mem[2] = 32'd2,         验证BEQ/BGE跳转
    //----------------------------------------------
    integer j;
    initial begin
        for (j = 0; j < 64; j = j + 1) begin
            instr_mem[j] = 32'h00000013; // NOP
            data_mem[j] = 32'h0;
        end

        instr_mem[0]  = 32'hFFF00093; // ADDI x1,  x0, -1
        instr_mem[1]  = 32'h01200113; // ADDI x2,  x0, 0x12
        instr_mem[2]  = 32'h002000A3; // SB   x2,  1(x0)
        instr_mem[3]  = 32'h00100183; // LB   x3,  1(x0)
        instr_mem[4]  = 32'h00104203; // LBU  x4,  1(x0)
        instr_mem[5]  = 32'hF8000293; // ADDI x5,  x0, -128
        instr_mem[6]  = 32'h00500123; // SB   x5,  2(x0)
        instr_mem[7]  = 32'h00200303; // LB   x6,  2(x0)
        instr_mem[8]  = 32'h00204383; // LBU  x7,  2(x0)
        instr_mem[9]  = 32'h03400413; // ADDI x8,  x0, 0x34
        instr_mem[10] = 32'h008001A3; // SB   x8,  3(x0)
        instr_mem[11] = 32'hFFE00513; // ADDI x10, x0, -2
        instr_mem[12] = 32'h00A01223; // SH   x10, 4(x0)
        instr_mem[13] = 32'h00401583; // LH   x11, 4(x0)
        instr_mem[14] = 32'h00405603; // LHU  x12, 4(x0)
        instr_mem[15] = 32'h00500693; // ADDI x13, x0, 5
        instr_mem[16] = 32'h00500713; // ADDI x14, x0, 5
        instr_mem[17] = 32'h00E68463; // BEQ  x13, x14, +8
        instr_mem[18] = 32'h00100793; // ADDI x15, x0, 1 (skipped)
        instr_mem[19] = 32'h00200793; // ADDI x15, x0, 2
        instr_mem[20] = 32'h00105463; // BGE  x0,  x1,  +8
        instr_mem[21] = 32'h00300793; // ADDI x15, x0, 3 (skipped)
        instr_mem[22] = 32'h00F02423; // SW   x15, 8(x0)
        instr_mem[23] = 32'h0000006F; // JAL  x0,  0 (halt)
    end

    //----------------------------------------------
    // 核心板LED输出
    // 默认: 4个LED全亮表示测试通过
    // KEY1: 显示Mem[0][31:28] = 4'h3
    // KEY2: 显示Mem[0][23:20] = 4'h8
    // KEY3: 显示Mem[1][3:0]   = 4'hE
    // KEY4: 显示Mem[2][3:0]   = 4'h2
    //----------------------------------------------
    localparam LED_ACTIVE_LOW = 1'b0;

    reg [3:0] led_data;
    wire [3:0] led_drive;

    always @(*) begin
        if (!key1)
            led_data = mem0[31:28];
        else if (!key2)
            led_data = mem0[23:20];
        else if (!key3)
            led_data = mem1[3:0];
        else if (!key4)
            led_data = mem2[3:0];
        else
            led_data = test_pass ? 4'hF : {halt, clk_cnt[24], mem2 == 32'd2, 1'b0};
    end

    assign led_drive = LED_ACTIVE_LOW ? ~led_data : led_data;
    assign led1 = led_drive[0];
    assign led2 = led_drive[1];
    assign led3 = led_drive[2];
    assign led4 = led_drive[3];

endmodule
