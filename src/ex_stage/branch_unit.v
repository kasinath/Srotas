// ============================================================================
// Module: branch_unit
// File: branch_unit.v
// Stage: EX
//
// Resolves conditional branches and computes the redirect target for taken
// branches, JAL, and JALR.
//
// The control unit already steers alu_op to SUB for BEQ/BNE, SLT for
// BLT/BGE, and SLTU for BLTU/BGEU - so the ALU's result already *is* the
// comparison we need (zero flag for equality, result bit 0 for less-than).
// No separate/duplicated comparator is needed, and unlike a "reuse the sign
// bit" shortcut, this is correct for the unsigned cases too.
//
// Targets:
//   - Branch taken / JAL : pc + imm      (PC-relative)
//   - JALR               : (rs1 + imm) & ~1, which is exactly alu_result
//                           with the LSB cleared, since the ALU already
//                           computed rs1+imm for a JALR instruction.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module branch_unit (
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire [31:0] alu_result,
    input  wire        alu_zero,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    input  wire        is_jalr,

    output wire        redirect,       // 1 = PC must be redirected & flush 2 stages
    output wire [31:0] redirect_target
);

    reg branch_taken;
    always @(*) begin
        case (funct3)
            `FUNCT3_BEQ:  branch_taken = alu_zero;
            `FUNCT3_BNE:  branch_taken = ~alu_zero;
            `FUNCT3_BLT:  branch_taken = alu_result[0];
            `FUNCT3_BGE:  branch_taken = ~alu_result[0];
            `FUNCT3_BLTU: branch_taken = alu_result[0];
            `FUNCT3_BGEU: branch_taken = ~alu_result[0];
            default:      branch_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_rel_target = pc + imm;
    wire [31:0] jalr_target   = {alu_result[31:1], 1'b0};

    assign redirect_target = is_jalr ? jalr_target : pc_rel_target;
    assign redirect        = jump || (branch && branch_taken);

endmodule
