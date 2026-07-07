//==================================================
// 乘法器 - RV32M扩展
// 支持有符号/无符号乘法
//==================================================
module multiplier (
    input  wire        clk,
    input  wire        rst,
    input  wire        valid_in,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op,       // 000=MUL, 001=MULH, 010=MULHU, 011=MULHSU
    output reg         valid_out,
    output reg  [31:0] result
);

    // 操作码定义
    localparam OP_MUL    = 3'd0;
    localparam OP_MULH   = 3'd1;
    localparam OP_MULHU  = 3'd2;
    localparam OP_MULHSU = 3'd3;

    // 乘积结果
    wire signed [63:0] prod_ss;   // signed * signed
    wire        [63:0] prod_uu;   // unsigned * unsigned
    wire signed [63:0] prod_su;   // signed * unsigned

    assign prod_ss = $signed(a) * $signed(b);
    assign prod_uu = a * b;
    assign prod_su = $signed(a) * b;

    // 状态机
    localparam IDLE = 1'b0;
    localparam BUSY = 1'b1;
    reg state;
    reg [2:0] op_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            valid_out  <= 1'b0;
            result     <= 32'b0;
            op_reg     <= 3'b0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                    if (valid_in) begin
                        op_reg <= op;
                        state  <= BUSY;
                    end
                end

                BUSY: begin
                    case (op_reg)
                        OP_MUL:    result <= prod_ss[31:0];
                        OP_MULH:   result <= prod_ss[63:32];
                        OP_MULHU:  result <= prod_uu[63:32];
                        OP_MULHSU: result <= prod_su[63:32];
                        default:   result <= 32'b0;
                    endcase
                    valid_out <= 1'b1;
                    state     <= IDLE;
                end
            endcase
        end
    end

endmodule
