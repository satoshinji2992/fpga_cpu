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
    // 运行计数器, 用于LED状态显示
    //----------------------------------------------
    reg [24:0] clk_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_cnt <= 25'd0;
        else
            clk_cnt <= clk_cnt + 25'd1;
    end

    //----------------------------------------------
    // 指令存储器 (ROM, 固化测试程序)
    //----------------------------------------------
    reg [31:0] instr_mem [0:63];

    // CPU取指信号
    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_valid;
    wire [31:0] instr_rom_addr;
    wire [31:0] instr_rom_data;

    // 数据存储器信号
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire        data_we;
    wire [31:0] data_rdata;
    wire        data_ready;

    wire        halt;
    wire [31:0] perf_cycle, perf_instret, perf_branch, perf_flush, perf_load_use_stall;
    wire [31:0] perf_bp_miss, perf_mdu_inst;

    //----------------------------------------------
    // 五级流水线CPU实例
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
        .halt       (halt),
        .perf_cycle         (perf_cycle),
        .perf_instret       (perf_instret),
        .perf_branch        (perf_branch),
        .perf_flush         (perf_flush),
        .perf_load_use_stall(perf_load_use_stall),
        .perf_bp_miss       (perf_bp_miss),
        .perf_mdu_inst      (perf_mdu_inst)
    );

    //----------------------------------------------
    // 直接映射I-Cache + 指令存储器 (异步读取)
    //----------------------------------------------
    assign instr_rom_data = instr_mem[instr_rom_addr[7:2]];

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
    // 数据存储器 (按字节拆成 4 个字节宽阵列)
    // 这是 XST 能稳定推断为分布式 RAM 的字节写模板, 避免
    // 把带字节使能的整字回退成触发器 + 宽多路选择器。
    //----------------------------------------------
    reg [7:0] data_mem_b0 [0:63];
    reg [7:0] data_mem_b1 [0:63];
    reg [7:0] data_mem_b2 [0:63];
    reg [7:0] data_mem_b3 [0:63];
    wire [5:0] data_idx = data_addr[7:2];
    wire [31:0] mem0;
    wire [31:0] mem1;
    wire [31:0] mem2;
    wire [31:0] mem3;
    wire        test_pass;

    always @(posedge clk) begin
        if (data_we && data_be[0]) data_mem_b0[data_idx] <= data_wdata[7:0];
        if (data_we && data_be[1]) data_mem_b1[data_idx] <= data_wdata[15:8];
        if (data_we && data_be[2]) data_mem_b2[data_idx] <= data_wdata[23:16];
        if (data_we && data_be[3]) data_mem_b3[data_idx] <= data_wdata[31:24];
    end

    assign data_rdata = {data_mem_b3[data_idx], data_mem_b2[data_idx],
                         data_mem_b1[data_idx], data_mem_b0[data_idx]};
    assign data_ready = 1'b1;
    assign mem0 = {data_mem_b3[6'd0], data_mem_b2[6'd0], data_mem_b1[6'd0], data_mem_b0[6'd0]};
    assign mem1 = {data_mem_b3[6'd1], data_mem_b2[6'd1], data_mem_b1[6'd1], data_mem_b0[6'd1]};
    assign mem2 = {data_mem_b3[6'd2], data_mem_b2[6'd2], data_mem_b1[6'd2], data_mem_b0[6'd2]};
    assign mem3 = {data_mem_b3[6'd3], data_mem_b2[6'd3], data_mem_b1[6'd3], data_mem_b0[6'd3]};
    assign test_pass = halt &&
                       (mem0 == 32'd42) &&    // MUL 7*6
                       (mem1 == 32'd55) &&    // sum 1+..+10
                       (mem2 == 32'd8);       // POPCOUNT(0xFF)

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
        .mem2      (mem2),
        .mem3      (mem3),
        .perf_cycle   (perf_cycle),
        .perf_instret (perf_instret),
        .perf_branch  (perf_branch),
        .perf_flush   (perf_flush),
        .perf_bp_miss (perf_bp_miss)
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
            instr_mem[j]   = 32'h00000013; // NOP
            data_mem_b0[j] = 8'h0;
            data_mem_b1[j] = 8'h0;
            data_mem_b2[j] = 8'h0;
            data_mem_b3[j] = 8'h0;
        end

        // 综合演示程序: 一次跑通 RV32M 乘法 + 计数循环(分支预测) +
        // POPCOUNT(自定义指令)。结果: mem0=MUL, mem1=sum, mem2=POPCOUNT.
        instr_mem[0]  = 32'h00700093; // ADDI x1, x0, 7
        instr_mem[1]  = 32'h00600113; // ADDI x2, x0, 6
        instr_mem[2]  = 32'h022081B3; // MUL  x3, x1, x2      -> 42
        instr_mem[3]  = 32'h00302023; // SW   x3, 0(x0)       -> mem0 = 42
        instr_mem[4]  = 32'h00000213; // ADDI x4, x0, 0       (sum)
        instr_mem[5]  = 32'h00100293; // ADDI x5, x0, 1       (i)
        instr_mem[6]  = 32'h00B00313; // ADDI x6, x0, 11      (bound)
        instr_mem[7]  = 32'h00520233; // ADD  x4, x4, x5      (loop:)
        instr_mem[8]  = 32'h00128293; // ADDI x5, x5, 1
        instr_mem[9]  = 32'hFE62CCE3; // BLT  x5, x6, -8      (-> loop)
        instr_mem[10] = 32'h00402223; // SW   x4, 4(x0)       -> mem1 = 55
        instr_mem[11] = 32'h0FF00393; // ADDI x7, x0, 0xFF
        instr_mem[12] = 32'h0003940B; // POPCOUNT x8, x7      -> 8
        instr_mem[13] = 32'h00802423; // SW   x8, 8(x0)       -> mem2 = 8
        instr_mem[14] = 32'hC00024F3; // RDCYCLE  x9         -> x9 = cycle (CSR read)
        instr_mem[15] = 32'h00902623; // SW       x9, 12(x0) -> Mem[3] = cycle
        instr_mem[16] = 32'h00000073; // ECALL (halt, 异常)
    end

    //----------------------------------------------
    // 核心板LED输出
    // 默认: 4个LED全亮表示测试通过
    // KEY1: Mem[0][3:0]=0xA  (MUL 7*6=42)
    // KEY2: Mem[1][3:0]=0x7  (sum 1+..+10=55)
    // KEY3: Mem[2][3:0]=0x8  (POPCOUNT 0xFF=8)
    // KEY4: halt 状态 (停机=0xF)
    //----------------------------------------------
    localparam LED_ACTIVE_LOW = 1'b0;

    reg [3:0] led_data;
    wire [3:0] led_drive;

    always @(*) begin
        if (!key1)
            led_data = mem0[3:0];
        else if (!key2)
            led_data = mem1[3:0];
        else if (!key3)
            led_data = mem2[3:0];
        else if (!key4)
            led_data = halt ? 4'hF : 4'h0;
        else
            led_data = test_pass ? 4'hF : {halt, clk_cnt[24], 1'b1, 1'b0};
    end

    assign led_drive = LED_ACTIVE_LOW ? ~led_data : led_data;
    assign led1 = led_drive[0];
    assign led2 = led_drive[1];
    assign led3 = led_drive[2];
    assign led4 = led_drive[3];

endmodule
