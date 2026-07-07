//==================================================
// 寄存器堆 (32个32位通用寄存器)
//==================================================
module regfile (
    input  wire        clk,
    input  wire        we,       // 写使能
    input  wire [4:0]  ra1,      // 读地址1
    input  wire [4:0]  ra2,      // 读地址2
    input  wire [4:0]  wa,       // 写地址
    input  wire [31:0] wd,       // 写数据
    output wire [31:0] rd1,      // 读数据1
    output wire [31:0] rd2       // 读数据2
);

    // 寄存器数组
    reg [31:0] regs [0:31];

    // 异步读取 (x0恒为0)
    assign rd1 = (ra1 == 5'd0) ? 32'b0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'b0 : regs[ra2];

    // 同步写入
    always @(posedge clk) begin
        if (we && (wa != 5'd0)) begin
            regs[wa] <= wd;
        end
    end

endmodule
