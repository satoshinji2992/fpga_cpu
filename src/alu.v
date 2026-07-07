//==================================================
// 算术逻辑单元 (ALU)
//==================================================
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output wire [31:0] result,
    output wire        zero
);

    // 操作码定义
    localparam OP_ADD  = 4'd0;
    localparam OP_SUB  = 4'd1;
    localparam OP_SLL  = 4'd2;
    localparam OP_SRL  = 4'd3;
    localparam OP_SRA  = 4'd4;
    localparam OP_AND  = 4'd5;
    localparam OP_OR   = 4'd6;
    localparam OP_XOR  = 4'd7;
    localparam OP_SLT  = 4'd8;
    localparam OP_SLTU = 4'd9;

    reg [31:0] result_reg;

    always @(*) begin
        case (op)
            OP_ADD :  result_reg = a + b;
            OP_SUB :  result_reg = a - b;
            OP_SLL :  result_reg = a << b[4:0];
            OP_SRL :  result_reg = a >> b[4:0];
            OP_SRA :  result_reg = $signed(a) >>> b[4:0];
            OP_AND :  result_reg = a & b;
            OP_OR  :  result_reg = a | b;
            OP_XOR :  result_reg = a ^ b;
            OP_SLT :  result_reg = {31'b0, ($signed(a) < $signed(b))};
            OP_SLTU:  result_reg = {31'b0, (a < b)};
            default:  result_reg = 32'b0;
        endcase
    end

    assign result = result_reg;
    assign zero   = (result_reg == 32'b0);

endmodule
