// ============================================================================
// Module: control_unit
// File: control_unit.v
// Stage: ID
//
// Decodes opcode/funct3/funct7 into the control signals that drive the rest
// of the datapath. All encodings come from rv32i_defines.vh so this unit
// and the ALU can never disagree about what an alu_op value means.
//
// CSR instructions (csrrw/csrrs/csrrc and their _i immediate forms, all
// under OP_SYSTEM) decode into csr_op/csr_use_imm, executed in EX
// (ex_stage_top.v).
//
// OP_SYSTEM with funct3 == 3'b000 is ECALL/EBREAK/MRET, distinguished by
// the imm[11:0] field (instruction[31:20] - the csr_addr input, reused
// here for its raw bit pattern rather than as a CSR address). WFI is
// treated as a NOP (legal per spec). Anything else in this space, and any
// entirely unrecognized opcode, sets `illegal` - RV32I doesn't implement
// compressed or M-extension opcodes, or several other CSR addresses, and
// encountering one should trap rather than silently misbehave.
//
// ecall/ebreak/mret/illegal are decoded here but resolved in EX, the same
// way branches are: control_unit.v only classifies the instruction, and
// ex_stage_top.v is where a resulting PC redirect and pipeline squash
// actually happen (see docs/roadmap.md, Phase 1).
//
// M extension (mul/div, Phase 2): shares OP_REG's opcode with the base
// R-type ALU ops, distinguished by funct7 == FUNCT7_MULDIV (0000001) rather
// than the funct7[5] bit the base ops use for SUB/SRA. This check must come
// before the base R-type funct3 case, not after: FUNCT7_MULDIV has bit 5
// clear, so without an explicit check a muldiv encoding falls straight
// through the existing case and silently decodes as ADD/SLL/etc. instead of
// as a multiply/divide - the same class of bug Phase 1 found with FENCE
// falling into the illegal-instruction default. alu_op is left at its
// default for a muldiv instruction; it's never consumed, since
// ex_stage_top.v routes muldiv_unit's result in place of the ALU's.
//
// A extension (atomics, Phase 2): OP_AMO is its own opcode (no base-ISA
// opcode to share/collide with, unlike M). alu_op = ALU_PASS_A gives an
// address of rs1 alone - AMO's R-type-shaped encoding has no immediate
// field at all (funct5/aq/rl/rs2 occupy those bit positions instead), so
// routing through the usual alu_src_b (imm-or-rs2) mux would either read
// garbage as an immediate or wrongly add rs2 into the address. mem_read is
// asserted for every one of the 11 variants, including sc.w: none of
// their results are ready before MEM, so this is what makes the existing
// load-use hazard protect a consumer for free, exactly as it does for an
// ordinary load - see hazard_detection.v. mem_write is asserted for every
// variant except lr.w (which never writes); amo_unit.v (MEM stage) is
// what turns sc.w's mem_write intent into a real, conditional write based
// on its reservation.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module control_unit (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [11:0] csr_addr,  // instruction[31:20]; only used to identify ECALL/EBREAK/MRET/WFI

    output reg        reg_write,
    output reg  [1:0] alu_src_a,   // ASEL_RS1 / ASEL_PC / ASEL_ZERO
    output reg        alu_src_b,   // 0 = rs2, 1 = immediate
    output reg  [3:0] alu_op,
    output reg        mem_read,
    output reg        mem_write,
    output reg  [1:0] result_src,  // RESULT_ALU / RESULT_MEM / RESULT_LINK / RESULT_CSR
    output reg        branch,
    output reg        jump,
    output reg        is_jalr,     // distinguishes JALR target calc from JAL
    output reg  [2:0] imm_format,
    output reg  [1:0] csr_op,      // CSR_OP_RW / CSR_OP_RS / CSR_OP_RC (don't-care unless result_src == RESULT_CSR)
    output reg        csr_use_imm, // 1 = operand is the zero-extended rs1-field immediate (csrr__i), 0 = the rs1 register value

    output reg        ecall,
    output reg        ebreak,
    output reg        mret,
    output reg        illegal,
    output reg        is_muldiv,
    output reg        is_amo
);

    always @(*) begin
        // Safe defaults: no side effects.
        reg_write   = 1'b0;
        alu_src_a   = `ASEL_RS1;
        alu_src_b   = 1'b0;
        alu_op      = `ALU_ADD;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        result_src  = `RESULT_ALU;
        branch      = 1'b0;
        jump        = 1'b0;
        is_jalr     = 1'b0;
        imm_format  = `IMM_I;
        csr_op      = 2'b00;
        csr_use_imm = 1'b0;
        ecall       = 1'b0;
        ebreak      = 1'b0;
        mret        = 1'b0;
        illegal     = 1'b0;
        is_muldiv   = 1'b0;
        is_amo      = 1'b0;

        case (opcode)
            `OP_LUI: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_ZERO;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_format = `IMM_U;
            end

            `OP_AUIPC: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_PC;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_format = `IMM_U;
            end

            `OP_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                result_src = `RESULT_LINK;
                imm_format = `IMM_J;
            end

            `OP_JALR: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                jump       = 1'b1;
                is_jalr    = 1'b1;
                result_src = `RESULT_LINK;
                imm_format = `IMM_I;
            end

            `OP_BRANCH: begin
                branch     = 1'b1;
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b0;
                imm_format = `IMM_B;
                case (funct3)
                    `FUNCT3_BEQ:  alu_op = `ALU_SUB;
                    `FUNCT3_BNE:  alu_op = `ALU_SUB;
                    `FUNCT3_BLT:  alu_op = `ALU_SLT;
                    `FUNCT3_BGE:  alu_op = `ALU_SLT;
                    `FUNCT3_BLTU: alu_op = `ALU_SLTU;
                    `FUNCT3_BGEU: alu_op = `ALU_SLTU;
                    default:      alu_op = `ALU_SUB;
                endcase
            end

            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                mem_read   = 1'b1;
                result_src = `RESULT_MEM;
                imm_format = `IMM_I;
            end

            `OP_STORE: begin
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                mem_write  = 1'b1;
                imm_format = `IMM_S;
            end

            `OP_IMM: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b1;
                imm_format = `IMM_I;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;                                    // ADDI
                    3'b010: alu_op = `ALU_SLT;                                    // SLTI
                    3'b011: alu_op = `ALU_SLTU;                                   // SLTIU
                    3'b100: alu_op = `ALU_XOR;                                    // XORI
                    3'b110: alu_op = `ALU_OR;                                     // ORI
                    3'b111: alu_op = `ALU_AND;                                    // ANDI
                    3'b001: alu_op = `ALU_SLL;                                    // SLLI
                    3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;             // SRAI/SRLI
                    default: alu_op = `ALU_ADD;
                endcase
            end

            `OP_REG: begin
                reg_write  = 1'b1;
                alu_src_a  = `ASEL_RS1;
                alu_src_b  = 1'b0;
                imm_format = `IMM_I; // don't-care for R-type
                if (funct7 == `FUNCT7_MULDIV) begin
                    is_muldiv = 1'b1; // funct3 selects the specific op in EX
                end else begin
                    case (funct3)
                        3'b000: alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;             // SUB/ADD
                        3'b001: alu_op = `ALU_SLL;                                    // SLL
                        3'b010: alu_op = `ALU_SLT;                                    // SLT
                        3'b011: alu_op = `ALU_SLTU;                                   // SLTU
                        3'b100: alu_op = `ALU_XOR;                                    // XOR
                        3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;             // SRA/SRL
                        3'b110: alu_op = `ALU_OR;                                     // OR
                        3'b111: alu_op = `ALU_AND;                                    // AND
                        default: alu_op = `ALU_ADD;
                    endcase
                end
            end

            `OP_SYSTEM: begin
                if (funct3 != 3'b000) begin
                    reg_write   = 1'b1;
                    result_src  = `RESULT_CSR;
                    csr_op      = funct3[1:0]; // 01=RW, 10=RS, 11=RC for both register and immediate forms
                    csr_use_imm = funct3[2];   // 1 for csrrwi/csrrsi/csrrci, 0 for csrrw/csrrs/csrrc
                end else begin
                    case (csr_addr)
                        `SYS_IMM_ECALL:  ecall  = 1'b1;
                        `SYS_IMM_EBREAK: ebreak = 1'b1;
                        `SYS_IMM_MRET:   mret   = 1'b1;
                        `SYS_IMM_WFI:    ;       // legal NOP: nothing to wait for yet
                        default:         illegal = 1'b1; // SFENCE.VMA or garbage - not yet supported
                    endcase
                end
            end

            `OP_AMO: begin
                if (funct3 != 3'b010) begin
                    illegal = 1'b1;  // RV32A is word-only; 3'b011 (doubleword) is RV64A-only
                end else begin
                    case (funct7[6:2])  // funct5: instruction[31:27]
                        `AMO_F5_LR, `AMO_F5_SC, `AMO_F5_SWAP, `AMO_F5_ADD,
                        `AMO_F5_XOR, `AMO_F5_AND, `AMO_F5_OR,
                        `AMO_F5_MIN, `AMO_F5_MAX, `AMO_F5_MINU, `AMO_F5_MAXU: begin
                            is_amo    = 1'b1;
                            reg_write = 1'b1;
                            alu_src_a = `ASEL_RS1;
                            alu_op    = `ALU_PASS_A;
                            result_src = `RESULT_MEM;
                            mem_read  = 1'b1;
                            mem_write = (funct7[6:2] != `AMO_F5_LR);
                        end
                        default: illegal = 1'b1;  // unrecognized funct5
                    endcase
                end
            end

            `OP_MISC_MEM: begin
                // FENCE (funct3=000, base RV32I) and FENCE.I (funct3=001,
                // Zifencei) are both true no-ops here: a single in-order
                // hart with no caches has no memory reordering to fence
                // and no instruction cache to invalidate. Every signal
                // stays at its safe default - not illegal, since both are
                // legitimate, fully-supported instructions.
            end

            default: begin
                // Unrecognized opcode: no compressed/M-extension support,
                // and this covers any other malformed encoding too.
                illegal = 1'b1;
            end
        endcase
    end

endmodule
