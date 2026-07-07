//==================================================
// RISC-V处理器核心 - RV32I基础实现
// 单周期执行
//==================================================
module riscv_core #(
    parameter PC_INIT = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    // 指令接口
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_data,
    input  wire        instr_valid,
    // 数据接口
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    output wire [3:0]  data_be,
    output wire        data_we,
    input  wire [31:0] data_rdata,
    input  wire        data_ready,
    // 状态输出
    output wire        halt
);

    //----------------------------------------------
    // 内部信号
    //----------------------------------------------
    reg  [31:0] pc_reg;
    reg  [31:0] pc_next;
    wire [31:0] pc_plus4;
    wire [31:0] branch_target;
    wire [31:0] jump_target;
    wire        branch_taken;
    wire        jump_taken;

    // 指令译码
    wire [31:0] instr;
    wire [6:0]  opcode;
    wire [4:0]  rd;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [31:0] imm_i;
    wire [31:0] imm_s;
    wire [31:0] imm_b;
    wire [31:0] imm_u;
    wire [31:0] imm_j;

    // 寄存器堆
    reg  [31:0] regfile [0:31];
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] rd_data;
    wire        rd_we;
    wire [31:0] load_data;

    // ALU
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    reg  [3:0]  alu_ctrl;
    wire [31:0] alu_result;

    // 控制信号
    wire        is_load;
    wire        is_store;
    wire        is_branch;
    wire        is_alu_imm;
    wire        is_alu_reg;
    wire        is_lui;
    wire        is_auipc;
    wire        is_jal;
    wire        is_jalr;
    wire        reg_write;
    reg         branch_cond;
    wire [31:0] mem_addr;
    wire [31:0] store_wdata;
    wire [3:0]  store_be;
    wire [7:0]  load_byte;
    wire [15:0] load_half;

    //----------------------------------------------
    // ALU操作码定义
    //----------------------------------------------
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SRL  = 4'd3;
    localparam ALU_SRA  = 4'd4;
    localparam ALU_AND  = 4'd5;
    localparam ALU_OR   = 4'd6;
    localparam ALU_XOR  = 4'd7;
    localparam ALU_SLT  = 4'd8;
    localparam ALU_SLTU = 4'd9;

    //----------------------------------------------
    // PC生成
    //----------------------------------------------
    assign pc_plus4       = pc_reg + 32'd4;
    assign branch_target  = pc_reg + imm_b;
    assign jump_target    = is_jalr ? ((rs1_data + imm_i) & 32'hFFFF_FFFE) : (pc_reg + imm_j);
    assign branch_taken   = is_branch && branch_cond;
    assign jump_taken     = is_jal || is_jalr;

    always @(*) begin
        if (branch_taken)
            pc_next = branch_target;
        else if (jump_taken)
            pc_next = jump_target;
        else
            pc_next = pc_plus4;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg <= PC_INIT;
        else
            pc_reg <= pc_next;
    end

    assign instr_addr = pc_reg;

    //----------------------------------------------
    // 指令译码
    //----------------------------------------------
    assign instr  = instr_valid ? instr_data : 32'h0000_0013; // NOP
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    // 立即数生成
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7],
                    instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign imm_j = {{12{instr[31]}}, instr[19:12], instr[20],
                    instr[30:21], 1'b0};

    //----------------------------------------------
    // 控制单元
    //----------------------------------------------
    assign is_load    = (opcode == 7'b0000011);
    assign is_store   = (opcode == 7'b0100011);
    assign is_branch  = (opcode == 7'b1100011);
    assign is_jal     = (opcode == 7'b1101111);
    assign is_jalr    = (opcode == 7'b1100111);
    assign is_lui     = (opcode == 7'b0110111);
    assign is_auipc   = (opcode == 7'b0010111);
    assign is_alu_imm = (opcode == 7'b0010011);
    assign is_alu_reg = (opcode == 7'b0110011);

    assign reg_write = is_alu_imm | is_alu_reg | is_lui |
                       is_auipc | is_jal | is_jalr | is_load;

    //----------------------------------------------
    // ALU控制
    //----------------------------------------------
    always @(*) begin
        if (is_alu_imm || is_alu_reg) begin
            case (funct3)
                3'b000:  alu_ctrl = (is_alu_reg && funct7[5]) ? ALU_SUB : ALU_ADD;
                3'b001:  alu_ctrl = ALU_SLL;
                3'b010:  alu_ctrl = ALU_SLT;
                3'b011:  alu_ctrl = ALU_SLTU;
                3'b100:  alu_ctrl = ALU_XOR;
                3'b101:  alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                3'b110:  alu_ctrl = ALU_OR;
                3'b111:  alu_ctrl = ALU_AND;
                default: alu_ctrl = ALU_ADD;
            endcase
        end else begin
            alu_ctrl = ALU_ADD;
        end
    end

    //----------------------------------------------
    // 分支条件判断
    //----------------------------------------------
    always @(*) begin
        case (funct3)
            3'b000:  branch_cond = (rs1_data == rs2_data);        // BEQ
            3'b001:  branch_cond = (rs1_data != rs2_data);        // BNE
            3'b100:  branch_cond = ($signed(rs1_data) <  $signed(rs2_data)); // BLT
            3'b101:  branch_cond = ($signed(rs1_data) >= $signed(rs2_data)); // BGE
            3'b110:  branch_cond = (rs1_data <  rs2_data);        // BLTU
            3'b111:  branch_cond = (rs1_data >= rs2_data);        // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    //----------------------------------------------
    // 寄存器堆 (异步读取, 同步写入)
    //----------------------------------------------
    integer k;
    assign rs1_data = (rs1 == 5'd0) ? 32'b0 : regfile[rs1];
    assign rs2_data = (rs2 == 5'd0) ? 32'b0 : regfile[rs2];

    assign rd_we = reg_write && instr_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 32; k = k + 1)
                regfile[k] <= 32'b0;
        end else if (rd_we && (rd != 5'd0)) begin
            regfile[rd] <= rd_data;
        end
    end

    //----------------------------------------------
    // 写回数据选择
    //----------------------------------------------
    assign rd_data = is_load   ? load_data :
                     is_lui    ? imm_u :
                     is_auipc  ? (pc_reg + imm_u) :
                     is_jal    ? pc_plus4 :
                     is_jalr   ? pc_plus4 :
                                 alu_result;

    //----------------------------------------------
    // ALU源操作数
    //----------------------------------------------
    assign alu_src1 = is_auipc ? pc_reg   : rs1_data;
    assign alu_src2 = is_alu_imm ? imm_i  :
                      is_store   ? imm_s  : rs2_data;

    //----------------------------------------------
    // ALU实现
    //----------------------------------------------
    assign alu_result =
        (alu_ctrl == ALU_ADD)  ? (alu_src1 + alu_src2) :
        (alu_ctrl == ALU_SUB)  ? (alu_src1 - alu_src2) :
        (alu_ctrl == ALU_SLL)  ? (alu_src1 << alu_src2[4:0]) :
        (alu_ctrl == ALU_SRL)  ? (alu_src1 >> alu_src2[4:0]) :
        (alu_ctrl == ALU_SRA)  ? ($signed(alu_src1) >>> alu_src2[4:0]) :
        (alu_ctrl == ALU_AND)  ? (alu_src1 & alu_src2) :
        (alu_ctrl == ALU_OR)   ? (alu_src1 | alu_src2) :
        (alu_ctrl == ALU_XOR)  ? (alu_src1 ^ alu_src2) :
        (alu_ctrl == ALU_SLT)  ? {31'b0, ($signed(alu_src1) < $signed(alu_src2))} :
        (alu_ctrl == ALU_SLTU) ? {31'b0, (alu_src1 < alu_src2)} :
                                 32'b0;

    //----------------------------------------------
    // 数据访问接口
    //----------------------------------------------
    assign mem_addr   = is_store ? (rs1_data + imm_s) : (rs1_data + imm_i);
    assign data_addr  = mem_addr;

    assign load_byte =
        (mem_addr[1:0] == 2'b00) ? data_rdata[7:0]   :
        (mem_addr[1:0] == 2'b01) ? data_rdata[15:8]  :
        (mem_addr[1:0] == 2'b10) ? data_rdata[23:16] :
                                   data_rdata[31:24];
    assign load_half = mem_addr[1] ? data_rdata[31:16] : data_rdata[15:0];
    assign load_data =
        (funct3 == 3'b000) ? {{24{load_byte[7]}}, load_byte} :  // LB
        (funct3 == 3'b001) ? {{16{load_half[15]}}, load_half} : // LH
        (funct3 == 3'b010) ? data_rdata :                       // LW
        (funct3 == 3'b100) ? {24'b0, load_byte} :               // LBU
        (funct3 == 3'b101) ? {16'b0, load_half} :               // LHU
                             data_rdata;

    assign store_wdata =
        (funct3 == 3'b000) ? ({24'b0, rs2_data[7:0]}  << {mem_addr[1:0], 3'b000}) :
        (funct3 == 3'b001) ? ({16'b0, rs2_data[15:0]} << {mem_addr[1], 4'b0000}) :
                             rs2_data;
    assign data_wdata = store_wdata;
    assign data_we    = is_store && instr_valid;
    assign store_be =
        (funct3 == 3'b000) ? (4'b0001 << mem_addr[1:0]) : // SB
        (funct3 == 3'b001) ? (mem_addr[1] ? 4'b1100 : 4'b0011) : // SH
        (funct3 == 3'b010) ? 4'b1111 : // SW
                             4'b0000;
    assign data_be = store_be;

    //----------------------------------------------
    // 停机检测 (JAL x0, 0)
    //----------------------------------------------
    assign halt = (instr == 32'h0000006F) && instr_valid;

endmodule
