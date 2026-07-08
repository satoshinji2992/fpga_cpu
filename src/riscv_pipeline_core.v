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
    parameter PC_INIT   = 32'h0000_0000,
    parameter ENABLE_BP = 1            // Stage 2: 1=dynamic BHT prediction, 0=baseline (predict not-taken)
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
    output reg         halt,
    // Performance counters (observable state, not part of the bus).
    //   cycle    : total clock cycles elapsed
    //   instret  : retired instructions (anything reaching WB)
    //   branch   : conditional branches that reached EX
    //   flush    : control-flow redirects (taken branch/jump in the
    //              no-predictor baseline == misprediction count)
    output reg [31:0]  perf_cycle,
    output reg [31:0]  perf_instret,
    output reg [31:0]  perf_branch,
    output reg [31:0]  perf_flush,
    // Stage 1: load-use hazard stall count (also reused by mul/div in S4).
    output reg [31:0]  perf_load_use_stall,
    // Stage 2: conditional-branch misprediction count (JAL/JALR excluded).
    output reg [31:0]  perf_bp_miss,
    // Stage 4: RV32M mul/div instruction count (single-cycle combinational
    // implementation; a multi-cycle divider FSM is a documented extension).
    output reg [31:0]  perf_mdu_inst
);

    // ALU op编码宽到 5 位，为后续自定义指令(RV32M/POPCOUNT 等)预留空间。
    localparam ALU_ADD  = 5'd0;
    localparam ALU_SUB  = 5'd1;
    localparam ALU_SLL  = 5'd2;
    localparam ALU_SRL  = 5'd3;
    localparam ALU_SRA  = 5'd4;
    localparam ALU_AND  = 5'd5;
    localparam ALU_OR   = 5'd6;
    localparam ALU_XOR  = 5'd7;
    localparam ALU_SLT  = 5'd8;
    localparam ALU_SLTU = 5'd9;
    // Stage 5: custom-0 extension opcodes (POPCOUNT / BITREVERSE).
    localparam ALU_POPCOUNT = 5'd10;
    localparam ALU_BITREV   = 5'd11;

    // Stage 5: custom-0 combinational helpers (functions => XST-friendly).
    function [31:0] popcount;
        input [31:0] x;
        integer p;
        reg [31:0] c;
        begin
            c = 32'b0;
            for (p = 0; p < 32; p = p + 1)
                c = c + {31'b0, x[p]};
            popcount = c;
        end
    endfunction
    function [31:0] bitreverse;
        input [31:0] x;
        integer p;
        begin
            for (p = 0; p < 32; p = p + 1)
                bitreverse[31-p] = x[p];
        end
    endfunction

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

    // Stage 2: branch history table — 16 entries of 2-bit saturating
    // counters, indexed by pc[5:2], initialised weakly not-taken (2'b01).
    // JAL is predicted directly (target computable in IF); JALR is NOT
    // predicted (its target depends on rs1, resolved in EX like baseline).
    reg [1:0] bht [0:15];
    integer k;
    initial begin
        for (k = 0; k < 16; k = k + 1)
            bht[k] = 2'b01;
    end

    // IF/ID
    reg        ifid_valid;
    reg [31:0] ifid_pc;
    reg [31:0] ifid_instr;
    reg        ifid_pred_taken;    // Stage 2: prediction made in IF for this instr
    reg [31:0] ifid_pred_target;

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
    reg [4:0]  idex_alu_ctrl;
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
    reg        idex_pred_taken;    // Stage 2
    reg [31:0] idex_pred_target;
    reg        idex_mul_div;       // Stage 4: RV32M op
    reg        idex_is_csr;        // Stage 7: CSR read
    reg [11:0] idex_csr_addr;

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
    // Register-file reads are async (continuous assign) so XST infers a clean
    // dual-port distributed RAM. The array itself is intentionally not reset
    // (Spartan-6 SLICEM DRAM has no reset), so x0 is forced to 0 here at the
    // read port instead. The mux sits after the DRAM read, so inference is
    // unaffected; regs[0] is also never written (write port gates rd != 0).
    // Write-through (MEM/WB -> read port) closes the 2-cycle RAW hazard where
    // a consumer in ID reads a register on the very cycle its producer writes
    // back: the non-blocking write would otherwise hand the ID stage the stale
    // value. The EX-stage forwarders below still cover the 1-cycle cases.
    wire [31:0] rf_rs1_data = (id_rs1 == 5'd0) ? 32'b0 :
                              (memwb_valid && memwb_reg_write && (memwb_rd == id_rs1)) ? memwb_result :
                              regs[id_rs1];
    wire [31:0] rf_rs2_data = (id_rs2 == 5'd0) ? 32'b0 :
                              (memwb_valid && memwb_reg_write && (memwb_rd == id_rs2)) ? memwb_result :
                              regs[id_rs2];

    wire [31:0] imm_i = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
    wire [31:0] imm_s = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
    wire [31:0] imm_b = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                         ifid_instr[30:25], ifid_instr[11:8], 1'b0};
    wire [31:0] imm_u = {ifid_instr[31:12], 12'b0};
    wire [31:0] imm_j = {{12{ifid_instr[31]}}, ifid_instr[19:12], ifid_instr[20],
                         ifid_instr[30:21], 1'b0};

    // Stage 2: IF-stage immediate decoders for prediction. The IF stage sees
    // instr_data (the word at pc_reg), not ifid_instr, so we decode separately.
    // Written as functions — XST treats them as pure combinational logic
    // (unlike tasks, which CLAUDE.md warns can break synthesis).
    function [31:0] imm_b_of;
        input [31:0] in;
        begin
            imm_b_of = {{19{in[31]}}, in[31], in[7], in[30:25], in[11:8], 1'b0};
        end
    endfunction
    function [31:0] imm_j_of;
        input [31:0] in;
        begin
            imm_j_of = {{12{in[31]}}, in[19:12], in[20], in[30:21], 1'b0};
        end
    endfunction

    wire id_is_load    = (id_opcode == 7'b0000011);
    wire id_is_store   = (id_opcode == 7'b0100011);
    wire id_is_branch  = (id_opcode == 7'b1100011);
    wire id_is_jal     = (id_opcode == 7'b1101111);
    wire id_is_jalr    = (id_opcode == 7'b1100111);
    wire id_is_lui     = (id_opcode == 7'b0110111);
    wire id_is_auipc   = (id_opcode == 7'b0010111);
    wire id_is_alu_imm = (id_opcode == 7'b0010011);
    wire id_is_alu_reg = (id_opcode == 7'b0110011);
    wire id_is_m_ext   = id_is_alu_reg && (id_funct7 == 7'b0000001); // Stage 4: RV32M
    wire id_is_custom0 = (id_opcode == 7'b0001011);                  // Stage 5: custom-0
    wire id_is_system  = (id_opcode == 7'b1110011);                  // Stage 7: SYSTEM/CSR
    wire [11:0] id_csr_addr  = ifid_instr[31:20];
    wire id_is_csr_read = id_is_system && (id_funct3 == 3'b010);     // CSRRS (RDCYCLE/RDINSTRET)

    reg [4:0] id_alu_ctrl;
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
        end else if (id_is_custom0) begin
            case (id_funct3)
                3'b001:  id_alu_ctrl = ALU_POPCOUNT;   // Stage 5
                3'b010:  id_alu_ctrl = ALU_BITREV;     // Stage 5
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
            ALU_SLTU:     ex_alu_result = {31'b0, (ex_alu_src1 < ex_alu_src2)};
            ALU_POPCOUNT: ex_alu_result = popcount(ex_alu_src1);     // Stage 5
            ALU_BITREV:   ex_alu_result = bitreverse(ex_alu_src1);   // Stage 5
            default:      ex_alu_result = 32'b0;
        endcase
    end

    // Stage 4: RV32M. Multiply is single-cycle (infers a DSP48). Divide uses a
    // 32-cycle restoring-division FSM — the combinational / and % it replaced
    // synthesized to a giant carry chain that overflowed XC6SLX9. The FSM is
    // inlined here so no new file needs adding to the ISE project.
    wire [63:0] m_prod_ss = $signed(ex_rs1_value) * $signed(ex_rs2_value);
    wire [63:0] m_prod_uu = ex_rs1_value * ex_rs2_value;
    wire [63:0] m_prod_su = $signed(ex_rs1_value) * $signed({32'd0, ex_rs2_value});
    reg  [31:0] mul_result;
    always @(*) begin
        case (idex_funct3)
            3'b000:  mul_result = m_prod_ss[31:0];   // MUL
            3'b001:  mul_result = m_prod_ss[63:32];  // MULH
            3'b010:  mul_result = m_prod_su[63:32];  // MULHSU
            default: mul_result = m_prod_uu[63:32];  // MULHU
        endcase
    end

    localparam MDU_IDLE = 1'b0, MDU_RUN = 1'b1;
    reg        mdu_state;
    reg [5:0]  mdu_cnt;
    reg [31:0] mdu_divd;     // latched dividend (raw, for REM div-by-zero)
    reg [31:0] mdu_divs;     // latched divisor
    reg [63:0] mdu_rq;       // {remainder[31:0], quotient[31:0]}
    reg [2:0]  mdu_opq;
    reg        mdu_a_neg, mdu_b_neg, mdu_div0, mdu_ovf;
    reg [31:0] mdu_result;
    reg        mdu_done;

    wire [31:0] ex_divd_abs  = ex_rs1_value[31] ? (~ex_rs1_value + 1'b1) : ex_rs1_value;
    wire [31:0] mdu_divs_abs = mdu_divs[31] ? (~mdu_divs + 1'b1) : mdu_divs;
    wire [63:0] mdu_rq_sh    = mdu_rq << 1;
    wire [32:0] mdu_rem_sub  = {1'b0, mdu_rq_sh[63:32]} - {1'b0, mdu_divs_abs};
    wire        mdu_rem_ok   = ~mdu_rem_sub[32];

    wire mdu_is_div  = idex_mul_div && idex_funct3[2];      // funct3 100..111
    wire mdu_req     = idex_valid && mdu_is_div;
    wire mdu_running = (mdu_state == MDU_RUN);
    wire mdu_stall   = mdu_req && !mdu_done;

    // Stage 7: CSR read. Map MCYCLE(0xC00)/MINSTRET(0xC02) to the live perf
    // counters; other CSRs read 0.
    wire [31:0] csr_rdata = (idex_csr_addr == 12'hC00) ? perf_cycle :
                            (idex_csr_addr == 12'hC02) ? perf_instret :
                                                          32'b0;
    wire [31:0] ex_result = idex_is_csr  ? csr_rdata :
                            idex_mul_div ? (idex_funct3[2] ? mdu_result : mul_result) :
                                           ex_alu_result;

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
    wire        actual_taken = ex_branch_taken || ex_jump_taken;
    // Stage 2: redirect fires only when the prediction was wrong. With
    // ENABLE_BP=0 nothing is predicted (pred_taken always 0), so this
    // degenerates to "redirect on any taken" (the baseline). When actually
    // taken the fix-up target is the real branch/jump target; when we wrongly
    // predicted taken but the branch fell through, it is pc+4.
    wire [31:0] actual_target = ex_branch_taken ? ex_branch_target : ex_jump_target;
    wire [31:0] bp_redirect_pc = actual_taken ? actual_target : (idex_pc + 32'd4);
    wire        mispredict = idex_valid && (
                             (actual_taken != idex_pred_taken) ||
                             (actual_taken && (actual_target != idex_pred_target)));
    wire        redirect = ENABLE_BP ? mispredict : actual_taken;
    // Branch-only misprediction (excludes JAL/JALR), for accuracy stats.
    wire        branch_mispredict = idex_valid && idex_branch &&
                                    (ex_branch_taken != idex_pred_taken);

    // Stage 1: load-use hazard. A load in EX whose destination register is
    // read by the instruction currently in ID must stall one cycle, because
    // the load result is not yet ready for EX/MEM forwarding (that forward is
    // gated by !exmem_mem_read above). Priority order: redirect > stall >
    // normal advance. id_uses_rs1/rs2 mask out instr fields that are not real
    // register specifiers (LUI/AUIPC/JAL have no rs1; only store/branch/R-type
    // read rs2) so we never stall on a false match.
    wire id_uses_rs1 = !(id_is_lui || id_is_auipc || id_is_jal);
    wire id_uses_rs2 = id_is_store || id_is_branch || id_is_alu_reg;
    wire load_use_hazard =
        idex_valid && idex_mem_read && ifid_valid && (idex_rd != 5'd0) &&
        ((id_uses_rs1 && (idex_rd == id_rs1)) ||
         (id_uses_rs2 && (idex_rd == id_rs2)));
    wire stall = load_use_hazard;

    // Stage 2: IF-stage branch prediction. instr_data is the async-fetched
    // word at pc_reg, so its opcode and branch/jump target are known here.
    wire [6:0]  if_opcode    = instr_data[6:0];
    wire        if_is_branch = (if_opcode == 7'b1100011);
    wire        if_is_jal    = (if_opcode == 7'b1101111);
    wire [3:0]  bht_index_if = pc_reg[5:2];
    wire        bht_pred_if  = bht[bht_index_if][1]; // MSB => predict taken
    wire [31:0] pred_target  = if_is_jal    ? (pc_reg + imm_j_of(instr_data)) :
                                 if_is_branch ? (pc_reg + imm_b_of(instr_data)) :
                                                (pc_reg + 32'd4);
    wire        pred_taken   = !ENABLE_BP   ? 1'b0 :
                                 if_is_jal    ? 1'b1 :
                                 if_is_branch ? bht_pred_if :
                                                1'b0;

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
            perf_cycle   <= 32'd0;
            perf_instret <= 32'd0;
            perf_branch  <= 32'd0;
            perf_flush   <= 32'd0;
            perf_load_use_stall <= 32'd0;
            perf_bp_miss        <= 32'd0;
            perf_mdu_inst       <= 32'd0;
            mdu_state  <= MDU_IDLE;
            mdu_cnt    <= 6'd0;
            mdu_done   <= 1'b0;
            mdu_result <= 32'd0;
            // Register file is intentionally NOT reset here. Spartan-6
            // distributed RAM (SLICEM) has no per-bit reset, so resetting the
            // array makes XST build 1024 FFs + wide read muxes instead of
            // inferring DRAM. The self-test writes every register before
            // reading it, and x0 is forced to 0 at the read port, so no reset
            // is needed.
        end else begin
            // Cycle counter stops once the core halts, so CPI reflects the
            // program's own run rather than idle spins after halt.
            if (!halt)
                perf_cycle <= perf_cycle + 32'd1;
            // Stage 4: multi-cycle divider FSM (runs every cycle; a stall just
            // waits). mdu_stall = a divide is in EX and not yet done.
            mdu_done <= 1'b0;
            if (mdu_state == MDU_IDLE) begin
                if (mdu_req && !mdu_done) begin
                    mdu_divd  <= ex_rs1_value;
                    mdu_divs  <= ex_rs2_value;
                    mdu_opq   <= idex_funct3;
                    mdu_a_neg <= ex_rs1_value[31];
                    mdu_b_neg <= ex_rs2_value[31];
                    mdu_div0  <= (ex_rs2_value == 32'b0);
                    mdu_ovf   <= (ex_rs1_value == 32'h80000000) && (ex_rs2_value == 32'hFFFFFFFF);
                    mdu_rq    <= {32'b0, ex_divd_abs};
                    mdu_cnt   <= 6'd0;
                    mdu_state <= MDU_RUN;
                end
            end else begin
                mdu_rq <= mdu_rem_ok ? {mdu_rem_sub[31:0], mdu_rq_sh[31:1], 1'b1}
                                     : {mdu_rq_sh[63:32], mdu_rq_sh[31:1], 1'b0};
                if (mdu_cnt == 6'd31) begin
                    case (mdu_opq)
                        3'b100:  mdu_result <= mdu_div0 ? 32'hFFFFFFFF :
                                               mdu_ovf  ? 32'h80000000 :
                                               ((mdu_a_neg ^ mdu_b_neg) ? (~{mdu_rq_sh[31:1], mdu_rem_ok} + 32'd1) : {mdu_rq_sh[31:1], mdu_rem_ok});
                        3'b101:  mdu_result <= mdu_div0 ? 32'hFFFFFFFF : {mdu_rq_sh[31:1], mdu_rem_ok};
                        3'b110:  mdu_result <= mdu_div0 ? mdu_divd :
                                               mdu_ovf  ? 32'b0 :
                                               (mdu_a_neg ? (~(mdu_rem_ok ? mdu_rem_sub[31:0] : mdu_rq_sh[63:32]) + 32'd1)
                                                          : (mdu_rem_ok ? mdu_rem_sub[31:0] : mdu_rq_sh[63:32]));
                        default: mdu_result <= mdu_div0 ? mdu_divd : (mdu_rem_ok ? mdu_rem_sub[31:0] : mdu_rq_sh[63:32]);
                    endcase
                    mdu_done  <= 1'b1;
                    mdu_state <= MDU_IDLE;
                end
                mdu_cnt <= mdu_cnt + 6'd1;
            end

            if (!mdu_stall) begin
                if (memwb_valid)
                    perf_instret <= perf_instret + 32'd1;
                if (memwb_valid && memwb_reg_write && (memwb_rd != 5'd0))
                    regs[memwb_rd] <= memwb_result;

                memwb_valid     <= exmem_valid;
                memwb_reg_write <= exmem_reg_write;
                memwb_rd        <= exmem_rd;
                memwb_result    <= mem_result;

                exmem_valid       <= idex_valid;
                exmem_alu_result  <= idex_lui ? idex_imm : ex_result;
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

                if (idex_valid && (idex_instr == 32'h0000006F ||
                                   idex_instr == 32'h00000073 ||  // ECALL
                                   idex_instr == 32'h00100073)) begin  // EBREAK
                    halt <= 1'b1;
                    idex_valid <= 1'b0;
                end
                // After halt, keep idex drained: ECALL/EBREAK advance PC to a
                // NOP (unlike JAL x0,0 which re-fetches itself), so without
                // this the post-halt NOP would keep retiring and inflate instret.
                if (halt)
                    idex_valid <= 1'b0;

                if (idex_valid && idex_branch) begin
                    if (ex_branch_taken)
                        bht[idex_pc[5:2]] <= (bht[idex_pc[5:2]] == 2'b11) ? 2'b11 : bht[idex_pc[5:2]] + 2'b01;
                    else
                        bht[idex_pc[5:2]] <= (bht[idex_pc[5:2]] == 2'b00) ? 2'b00 : bht[idex_pc[5:2]] - 2'b01;
                end

                if (redirect) begin
                    perf_flush  <= perf_flush + 32'd1;
                    if (branch_mispredict)
                        perf_bp_miss <= perf_bp_miss + 32'd1;
                    pc_reg      <= bp_redirect_pc;
                    ifid_valid  <= 1'b0;
                    idex_valid  <= 1'b0;
                end else if (stall) begin
                    perf_load_use_stall <= perf_load_use_stall + 32'd1;
                    idex_valid <= 1'b0;
                end else if (!halt && instr_valid) begin
                    if (ifid_valid && id_is_branch)
                        perf_branch <= perf_branch + 32'd1;
                    pc_reg      <= pred_taken ? pred_target : (pc_reg + 32'd4);
                    ifid_valid  <= 1'b1;
                    ifid_pc     <= pc_reg;
                    ifid_instr  <= instr_data;
                    ifid_pred_taken  <= pred_taken;
                    ifid_pred_target <= pred_target;

                    idex_valid       <= ifid_valid;
                    idex_pc          <= ifid_pc;
                    idex_instr       <= ifid_instr;
                    idex_pred_taken  <= ifid_pred_taken;
                    idex_pred_target <= ifid_pred_target;
                    idex_rs1         <= id_rs1;
                    idex_rs2       <= id_rs2;
                    idex_rd        <= id_rd;
                    idex_funct3    <= id_funct3;
                    idex_rs1_data  <= rf_rs1_data;
                    idex_rs2_data  <= rf_rs2_data;
                    idex_imm       <= id_imm;
                    idex_alu_ctrl  <= id_alu_ctrl;
                    idex_use_imm   <= id_is_alu_imm || id_is_load || id_is_store || id_is_lui || id_is_auipc || id_is_jalr;
                    idex_reg_write <= id_is_alu_imm || id_is_alu_reg || id_is_load || id_is_lui || id_is_auipc || id_is_jal || id_is_jalr || id_is_custom0 || id_is_csr_read;
                    idex_mem_read  <= id_is_load;
                    idex_mem_write <= id_is_store;
                    idex_branch    <= id_is_branch;
                    idex_jal       <= id_is_jal;
                    idex_jalr      <= id_is_jalr;
                    idex_lui       <= id_is_lui;
                    idex_auipc     <= id_is_auipc;
                    idex_mul_div   <= id_is_m_ext;
                    idex_is_csr    <= id_is_csr_read;     // Stage 7
                    idex_csr_addr  <= id_csr_addr;        // Stage 7
                    if (ifid_valid && id_is_m_ext)
                        perf_mdu_inst <= perf_mdu_inst + 32'd1;
                end
            end
        end
    end

endmodule
