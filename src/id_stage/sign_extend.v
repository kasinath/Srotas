// ============================================================================
// Module: sign_extend
// File: sign_extend.v
// Stage: ID
//
// Produces the 32-bit sign-extended immediate for each RV32I instruction
// format. imm_format is chosen by the control unit based on opcode.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module sign_extend (
    input  wire [31:0] instruction,
    input  wire [2:0]  imm_format,
    output reg  [31:0] extended_imm
);

    always @(*) begin
        case (imm_format)
            `IMM_I:
                extended_imm = {{20{instruction[31]}}, instruction[31:20]};

            `IMM_S:
                extended_imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

            `IMM_B:
                extended_imm = {{19{instruction[31]}}, instruction[31], instruction[7],
                                 instruction[30:25], instruction[11:8], 1'b0};

            `IMM_U:
                extended_imm = {instruction[31:12], 12'b0};

            `IMM_J:
                extended_imm = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                                 instruction[20], instruction[30:21], 1'b0};

            default:
                extended_imm = 32'b0;
        endcase
    end

endmodule
