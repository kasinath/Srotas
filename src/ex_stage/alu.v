/**
 * ALU (Arithmetic Logic Unit) - Execute Stage Core
 * 
 * This is the "calculator" of the processor. It performs all arithmetic 
 * and logical operations based on the ALU control signal.
 * 
 * Supported Operations (RV32I):
 * - ADD, SUB: Addition and Subtraction
 * - AND, OR, XOR: Bitwise logical operations
 * - SLT, SLTU: Set Less Than (signed and unsigned)
 * - SLL, SRL, SRA: Shift operations (logical and arithmetic)
 * 
 * @author Srotas Project
 * @day Day 3 - Execute Stage
 */

module alu (
    input wire [31:0] operand_a,      // First operand (from register rs1)
    input wire [31:0] operand_b,      // Second operand (from register rs2 or immediate)
    input wire [3:0]  alu_control,    // Control signal from main control unit
    output reg [31:0] result,         // Result of the operation
    output wire       zero,           // High when result is zero (for branch equal)
    output wire       overflow        // High when signed overflow occurs (for ADD/SUB)
);

    // Zero flag: asserted when all bits of result are 0
    assign zero = (result == 32'b0);

    // Overflow detection for signed addition/subtraction
    // Overflow occurs when:
    // - Adding two positives gives negative
    // - Adding two negatives gives positive
    assign overflow = (alu_control == 4'b0010 || alu_control == 4'b0110) && 
                      ((operand_a[31] == operand_b[31]) && (result[31] != operand_a[31]));

    // Main ALU operation logic
    always @(*) begin
        case (alu_control)
            // ADD: result = operand_a + operand_b
            4'b0010: result = operand_a + operand_b;
            
            // SUB: result = operand_a - operand_b
            4'b0110: result = operand_a - operand_b;
            
            // AND: bitwise AND
            4'b0111: result = operand_a & operand_b;
            
            // OR: bitwise OR
            4'b0000: result = operand_a | operand_b;
            
            // XOR: bitwise XOR
            4'b0100: result = operand_a ^ operand_b;
            
            // SLT: Set Less Than (signed comparison)
            // result = 1 if operand_a < operand_b (signed), else 0
            4'b0001: result = ($signed(operand_a) < $signed(operand_b)) ? 32'b1 : 32'b0;
            
            // SLTU: Set Less Than Unsigned
            // result = 1 if operand_a < operand_b (unsigned), else 0
            4'b1001: result = (operand_a < operand_b) ? 32'b1 : 32'b0;
            
            // SLL: Shift Left Logical
            // result = operand_a << operand_b[4:0]
            4'b1011: result = operand_a << operand_b[4:0];
            
            // SRL: Shift Right Logical
            // result = operand_a >> operand_b[4:0]
            4'b1101: result = operand_a >> operand_b[4:0];
            
            // SRA: Shift Right Arithmetic (preserves sign bit)
            // result = operand_a >>> operand_b[4:0]
            4'b1110: result = $signed(operand_a) >>> operand_b[4:0];
            
            // Default: pass operand_a through
            default: result = operand_a;
        endcase
    end

endmodule
