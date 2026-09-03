// ============================================================================
// Module: alu
// File: alu.v
// Stage: EX
//
// Arithmetic Logic Unit. Operation is selected by alu_op using the shared
// encoding in rv32i_defines.vh (matches what control_unit.v produces).
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module alu (
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result,
    output wire         zero
);

    assign zero = (result == 32'b0);

    always @(*) begin
        case (alu_op)
            `ALU_ADD:  result = operand_a + operand_b;
            `ALU_SUB:  result = operand_a - operand_b;
            `ALU_SLL:  result = operand_a << operand_b[4:0];
            `ALU_SLT:  result = {31'b0, ($signed(operand_a) < $signed(operand_b))};
            `ALU_SLTU: result = {31'b0, (operand_a < operand_b)};
            `ALU_XOR:  result = operand_a ^ operand_b;
            `ALU_SRL:  result = operand_a >> operand_b[4:0];
            `ALU_SRA:  result = $signed(operand_a) >>> operand_b[4:0];
            `ALU_OR:   result = operand_a | operand_b;
            `ALU_AND:  result = operand_a & operand_b;
            `ALU_PASS_A: result = operand_a; // AMO address = rs1 alone, no immediate to add
            default:   result = 32'b0;
        endcase
    end

endmodule
