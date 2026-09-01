// ============================================================================
// Module: control_unit
// File: control_unit.v
// Stage: ID
//
// Decodes opcode/funct3/funct7 into the control signals that drive the rest
// of the datapath. All encodings come from rv32i_defines.vh so this unit
// and the ALU can never disagree about what an alu_op value means.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    output reg        reg_write,
    output reg  [1:0] alu_src_a,   // ASEL_RS1 / ASEL_PC / ASEL_ZERO
    output reg        alu_src_b,   // 0 = rs2, 1 = immediate
    output reg  [3:0] alu_op,
    output reg        mem_read,
    output reg        mem_write,
    output reg  [1:0] result_src,  // RESULT_ALU / RESULT_MEM / RESULT_LINK
    output reg        branch,
    output reg        jump,
    output reg        is_jalr,     // distinguishes JALR target calc from JAL
    output reg  [2:0] imm_format
);

    always @(*) begin
        // Safe defaults: no side effects.
        reg_write  = 1'b0;
        alu_src_a  = `ASEL_RS1;
        alu_src_b  = 1'b0;
        alu_op     = `ALU_ADD;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        result_src = `RESULT_ALU;
        branch     = 1'b0;
        jump       = 1'b0;
        is_jalr    = 1'b0;
        imm_format = `IMM_I;

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

            default: begin
                // Unknown opcode: behave as a NOP (no writes, no side effects)
            end
        endcase
    end

endmodule
