//==================================================
// RISC-V RV32I subset processor - five-stage pipeline
//
// Stages:
//   IF  - instruction fetch
//   ID  - decode / register read
//   EX  - ALU / branch decision
//   MEM - data memory access
//   WB  - register write back
//
// Forwarding is implemented from EX/MEM and MEM/WB to EX. Branches and
// jumps are resolved in EX and flush younger stages.
//==================================================
module riscv_pipeline_core #(
    parameter PC_INIT = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_data,
    input  wire        instr_valid,
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    output wire [3:0]  data_be,
    output wire        data_we,
    input  wire [31:0] data_rdata,
    input  wire        data_ready,
    output reg         halt
);

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

    reg [31:0] pc_reg;
    assign instr_addr = pc_reg;

    reg [31:0] regs [0:31];
    integer i;

    // Power-up init (NOT a clocked reset): this becomes the distributed-RAM
    // INIT attribute, so XST still infers DRAM while keeping the array
    // deterministic in sim and at FPGA power-on. A clocked for-reset here
    // would instead force XST to build 1024 FFs + wide read muxes.
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    // IF/ID
    reg        ifid_valid;
    reg [31:0] ifid_pc;
    reg [31:0] ifid_instr;

    // ID/EX
    reg        idex_valid;
    reg [31:0] idex_pc;
    reg [31:0] idex_rs1_data;
    reg [31:0] idex_rs2_data;
    reg [31:0] idex_imm;
    reg [4:0]  idex_rs1;
    reg [4:0]  idex_rs2;
    reg [4:0]  idex_rd;
    reg [2:0]  idex_funct3;
    reg [3:0]  idex_alu_ctrl;
    reg        idex_use_imm;
    reg        idex_reg_write;
    reg        idex_mem_read;
    reg        idex_mem_write;
    reg        idex_branch;
    reg        idex_jal;
    reg        idex_jalr;
    reg        idex_lui;
    reg        idex_auipc;
    reg [31:0] idex_instr;

    // EX/MEM
    reg        exmem_valid;
    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_store_data;
    reg [31:0] exmem_pc_plus4;
    reg [4:0]  exmem_rd;
    reg [2:0]  exmem_funct3;
    reg        exmem_reg_write;
    reg        exmem_mem_read;
    reg        exmem_mem_write;
    reg        exmem_jal_or_jalr;
    reg        exmem_lui;
    reg [31:0] exmem_lui_data;

    // MEM/WB
    reg        memwb_valid;
    reg [31:0] memwb_result;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_write;

    wire [6:0] id_opcode = ifid_instr[6:0];
    wire [4:0] id_rd     = ifid_instr[11:7];
    wire [2:0] id_funct3 = ifid_instr[14:12];
    wire [4:0] id_rs1    = ifid_instr[19:15];
    wire [4:0] id_rs2    = ifid_instr[24:20];
    wire [6:0] id_funct7 = ifid_instr[31:25];

    // Register-file reads are async (continuous assign) so XST infers a clean
    // dual-port distributed RAM. The array itself is intentionally not reset
    // (Spartan-6 SLICEM DRAM has no reset), so x0 is forced to 0 here at the
    // read port instead. The mux sits after the DRAM read, so inference is
    // unaffected; regs[0] is also never written (write port gates rd != 0).
    wire [31:0] rf_rs1_data = (id_rs1 == 5'd0) ? 32'b0 : regs[id_rs1];
    wire [31:0] rf_rs2_data = (id_rs2 == 5'd0) ? 32'b0 : regs[id_rs2];

    wire [31:0] imm_i = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
    wire [31:0] imm_s = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
    wire [31:0] imm_b = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                         ifid_instr[30:25], ifid_instr[11:8], 1'b0};
    wire [31:0] imm_u = {ifid_instr[31:12], 12'b0};
    wire [31:0] imm_j = {{12{ifid_instr[31]}}, ifid_instr[19:12], ifid_instr[20],
                         ifid_instr[30:21], 1'b0};

    wire id_is_load    = (id_opcode == 7'b0000011);
    wire id_is_store   = (id_opcode == 7'b0100011);
    wire id_is_branch  = (id_opcode == 7'b1100011);
    wire id_is_jal     = (id_opcode == 7'b1101111);
    wire id_is_jalr    = (id_opcode == 7'b1100111);
    wire id_is_lui     = (id_opcode == 7'b0110111);
    wire id_is_auipc   = (id_opcode == 7'b0010111);
    wire id_is_alu_imm = (id_opcode == 7'b0010011);
    wire id_is_alu_reg = (id_opcode == 7'b0110011);

    reg [3:0] id_alu_ctrl;
    reg [31:0] id_imm;

    always @(*) begin
        if (id_is_alu_imm || id_is_alu_reg) begin
            case (id_funct3)
                3'b000: id_alu_ctrl = (id_is_alu_reg && id_funct7[5]) ? ALU_SUB : ALU_ADD;
                3'b001: id_alu_ctrl = ALU_SLL;
                3'b010: id_alu_ctrl = ALU_SLT;
                3'b011: id_alu_ctrl = ALU_SLTU;
                3'b100: id_alu_ctrl = ALU_XOR;
                3'b101: id_alu_ctrl = id_funct7[5] ? ALU_SRA : ALU_SRL;
                3'b110: id_alu_ctrl = ALU_OR;
                3'b111: id_alu_ctrl = ALU_AND;
                default: id_alu_ctrl = ALU_ADD;
            endcase
        end else begin
            id_alu_ctrl = ALU_ADD;
        end

        if (id_is_store)
            id_imm = imm_s;
        else if (id_is_branch)
            id_imm = imm_b;
        else if (id_is_lui || id_is_auipc)
            id_imm = imm_u;
        else if (id_is_jal)
            id_imm = imm_j;
        else
            id_imm = imm_i;
    end

    wire [31:0] wb_forward_data = memwb_result;

    wire [31:0] exmem_forward_data =
        exmem_jal_or_jalr ? exmem_pc_plus4 :
        exmem_lui         ? exmem_lui_data :
                             exmem_alu_result;

    wire [31:0] ex_rs1_value =
        (idex_rs1 != 5'd0 && exmem_valid && exmem_reg_write && !exmem_mem_read && exmem_rd == idex_rs1) ? exmem_forward_data :
        (idex_rs1 != 5'd0 && memwb_valid && memwb_reg_write && memwb_rd == idex_rs1) ? wb_forward_data :
        idex_rs1_data;

    wire [31:0] ex_rs2_value =
        (idex_rs2 != 5'd0 && exmem_valid && exmem_reg_write && !exmem_mem_read && exmem_rd == idex_rs2) ? exmem_forward_data :
        (idex_rs2 != 5'd0 && memwb_valid && memwb_reg_write && memwb_rd == idex_rs2) ? wb_forward_data :
        idex_rs2_data;

    wire [31:0] ex_alu_src1 = idex_auipc ? idex_pc : ex_rs1_value;
    wire [31:0] ex_alu_src2 = idex_use_imm ? idex_imm : ex_rs2_value;

    reg [31:0] ex_alu_result;
    always @(*) begin
        case (idex_alu_ctrl)
            ALU_ADD:  ex_alu_result = ex_alu_src1 + ex_alu_src2;
            ALU_SUB:  ex_alu_result = ex_alu_src1 - ex_alu_src2;
            ALU_SLL:  ex_alu_result = ex_alu_src1 << ex_alu_src2[4:0];
            ALU_SRL:  ex_alu_result = ex_alu_src1 >> ex_alu_src2[4:0];
            ALU_SRA:  ex_alu_result = $signed(ex_alu_src1) >>> ex_alu_src2[4:0];
            ALU_AND:  ex_alu_result = ex_alu_src1 & ex_alu_src2;
            ALU_OR:   ex_alu_result = ex_alu_src1 | ex_alu_src2;
            ALU_XOR:  ex_alu_result = ex_alu_src1 ^ ex_alu_src2;
            ALU_SLT:  ex_alu_result = {31'b0, ($signed(ex_alu_src1) < $signed(ex_alu_src2))};
            ALU_SLTU: ex_alu_result = {31'b0, (ex_alu_src1 < ex_alu_src2)};
            default:  ex_alu_result = 32'b0;
        endcase
    end

    reg ex_branch_cond;
    always @(*) begin
        case (idex_funct3)
            3'b000: ex_branch_cond = (ex_rs1_value == ex_rs2_value);
            3'b001: ex_branch_cond = (ex_rs1_value != ex_rs2_value);
            3'b100: ex_branch_cond = ($signed(ex_rs1_value) <  $signed(ex_rs2_value));
            3'b101: ex_branch_cond = ($signed(ex_rs1_value) >= $signed(ex_rs2_value));
            3'b110: ex_branch_cond = (ex_rs1_value <  ex_rs2_value);
            3'b111: ex_branch_cond = (ex_rs1_value >= ex_rs2_value);
            default: ex_branch_cond = 1'b0;
        endcase
    end

    wire ex_branch_taken = idex_valid && idex_branch && ex_branch_cond;
    wire ex_jump_taken   = idex_valid && (idex_jal || idex_jalr);
    wire [31:0] ex_branch_target = idex_pc + idex_imm;
    wire [31:0] ex_jump_target   = idex_jalr ? ((ex_rs1_value + idex_imm) & 32'hFFFF_FFFE) :
                                               (idex_pc + idex_imm);
    wire [31:0] redirect_pc = ex_branch_taken ? ex_branch_target : ex_jump_target;
    wire redirect = ex_branch_taken || ex_jump_taken;

    wire [31:0] store_addr = exmem_alu_result;
    wire [31:0] store_shifted =
        (exmem_funct3 == 3'b000) ? ({24'b0, exmem_store_data[7:0]}  << {store_addr[1:0], 3'b000}) :
        (exmem_funct3 == 3'b001) ? ({16'b0, exmem_store_data[15:0]} << {store_addr[1], 4'b0000}) :
                                   exmem_store_data;
    wire [3:0] store_be =
        (exmem_funct3 == 3'b000) ? (4'b0001 << store_addr[1:0]) :
        (exmem_funct3 == 3'b001) ? (store_addr[1] ? 4'b1100 : 4'b0011) :
        (exmem_funct3 == 3'b010) ? 4'b1111 :
                                   4'b0000;

    assign data_addr  = exmem_alu_result;
    assign data_wdata = store_shifted;
    assign data_we    = exmem_valid && exmem_mem_write;
    assign data_be    = data_we ? store_be : 4'b0000;

    wire [7:0] load_byte =
        (exmem_alu_result[1:0] == 2'b00) ? data_rdata[7:0]   :
        (exmem_alu_result[1:0] == 2'b01) ? data_rdata[15:8]  :
        (exmem_alu_result[1:0] == 2'b10) ? data_rdata[23:16] :
                                           data_rdata[31:24];
    wire [15:0] load_half = exmem_alu_result[1] ? data_rdata[31:16] : data_rdata[15:0];
    wire [31:0] mem_load_data =
        (exmem_funct3 == 3'b000) ? {{24{load_byte[7]}}, load_byte} :
        (exmem_funct3 == 3'b001) ? {{16{load_half[15]}}, load_half} :
        (exmem_funct3 == 3'b010) ? data_rdata :
        (exmem_funct3 == 3'b100) ? {24'b0, load_byte} :
        (exmem_funct3 == 3'b101) ? {16'b0, load_half} :
                                   data_rdata;

    wire [31:0] mem_result =
        exmem_mem_read    ? mem_load_data :
        exmem_jal_or_jalr ? exmem_pc_plus4 :
        exmem_lui         ? exmem_lui_data :
                             exmem_alu_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= PC_INIT;
            halt <= 1'b0;
            ifid_valid <= 1'b0;
            idex_valid <= 1'b0;
            exmem_valid <= 1'b0;
            memwb_valid <= 1'b0;
            // Register file is intentionally NOT reset here. Spartan-6
            // distributed RAM (SLICEM) has no per-bit reset, so resetting the
            // array makes XST build 1024 FFs + wide read muxes instead of
            // inferring DRAM. The self-test writes every register before
            // reading it, and x0 is forced to 0 at the read port, so no reset
            // is needed.
        end else begin
            if (memwb_valid && memwb_reg_write && (memwb_rd != 5'd0))
                regs[memwb_rd] <= memwb_result;

            memwb_valid     <= exmem_valid;
            memwb_reg_write <= exmem_reg_write;
            memwb_rd        <= exmem_rd;
            memwb_result    <= mem_result;

            exmem_valid       <= idex_valid;
            exmem_alu_result  <= idex_lui ? idex_imm : ex_alu_result;
            exmem_store_data  <= ex_rs2_value;
            exmem_pc_plus4    <= idex_pc + 32'd4;
            exmem_rd          <= idex_rd;
            exmem_funct3      <= idex_funct3;
            exmem_reg_write   <= idex_reg_write;
            exmem_mem_read    <= idex_mem_read;
            exmem_mem_write   <= idex_mem_write;
            exmem_jal_or_jalr <= idex_jal || idex_jalr;
            exmem_lui         <= idex_lui;
            exmem_lui_data    <= idex_imm;

            if (idex_valid && (idex_instr == 32'h0000006F))
                halt <= 1'b1;

            if (redirect) begin
                pc_reg      <= redirect_pc;
                ifid_valid  <= 1'b0;
                idex_valid  <= 1'b0;
            end else if (!halt && instr_valid) begin
                pc_reg      <= pc_reg + 32'd4;
                ifid_valid  <= 1'b1;
                ifid_pc     <= pc_reg;
                ifid_instr  <= instr_data;

                idex_valid     <= ifid_valid;
                idex_pc        <= ifid_pc;
                idex_instr     <= ifid_instr;
                idex_rs1       <= id_rs1;
                idex_rs2       <= id_rs2;
                idex_rd        <= id_rd;
                idex_funct3    <= id_funct3;
                idex_rs1_data  <= rf_rs1_data;
                idex_rs2_data  <= rf_rs2_data;
                idex_imm       <= id_imm;
                idex_alu_ctrl  <= id_alu_ctrl;
                idex_use_imm   <= id_is_alu_imm || id_is_load || id_is_store || id_is_lui || id_is_auipc || id_is_jalr;
                idex_reg_write <= id_is_alu_imm || id_is_alu_reg || id_is_load || id_is_lui || id_is_auipc || id_is_jal || id_is_jalr;
                idex_mem_read  <= id_is_load;
                idex_mem_write <= id_is_store;
                idex_branch    <= id_is_branch;
                idex_jal       <= id_is_jal;
                idex_jalr      <= id_is_jalr;
                idex_lui       <= id_is_lui;
                idex_auipc     <= id_is_auipc;
            end
        end
    end

endmodule
