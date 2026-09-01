/**
 * Branch Unit - Execute Stage Branch Logic
 * 
 * This module determines if a branch should be taken based on:
 * - The branch type (BEQ, BNE, BLT, BGE, BLTU, BGEU)
 * - The ALU zero flag and sign comparisons
 * 
 * It calculates the branch target address for taken branches.
 * 
 * @author Srotas Project
 * @day Day 3 - Execute Stage
 */

module branch_unit (
    input wire [31:0] pc,               // Current PC value
    input wire [31:0] imm,              // Sign-extended immediate (already shifted left by 1)
    input wire        zero,             // ALU zero flag (for BEQ/BNE)
    input wire        sign,             // Sign of result (for signed comparisons)
    input wire [2:0]  branch_type,      // Type of branch instruction
                                        // 000: BEQ  - Branch if Equal
                                        // 001: BNE  - Branch if Not Equal
                                        // 100: BLT  - Branch if Less Than (signed)
                                        // 101: BGE  - Branch if Greater or Equal (signed)
                                        // 110: BLTU - Branch if Less Than (unsigned)
                                        // 111: BGEU - Branch if Greater or Equal (unsigned)
    output reg        branch_taken,     // High if branch condition is met
    output reg [31:0] branch_target     // Target address if branch is taken
);

    // Calculate branch target address: PC + immediate
    // Note: The immediate from ID stage is already shifted left by 1 (for half-word alignment)
    assign branch_target = pc + imm;

    // Determine if branch should be taken based on branch type and flags
    always @(*) begin
        branch_taken = 1'b0;  // Default: don't take branch
        
        case (branch_type)
            // BEQ: Branch if Equal (zero flag set)
            3'b000: branch_taken = zero;
            
            // BNE: Branch if Not Equal (zero flag not set)
            3'b001: branch_taken = ~zero;
            
            // BLT: Branch if Less Than (signed)
            // Taken when sign bit is 1 (negative result)
            3'b100: branch_taken = sign;
            
            // BGE: Branch if Greater or Equal (signed)
            // Taken when sign bit is 0 (positive or zero result)
            3'b101: branch_taken = ~sign;
            
            // BLTU: Branch if Less Than (unsigned)
            // For unsigned comparison, we need to check borrow
            // This is handled by checking if operand_a < operand_b in ALU
            3'b110: branch_taken = sign;  // Reusing sign flag for simplicity
            
            // BGEU: Branch if Greater or Equal (unsigned)
            3'b111: branch_taken = ~sign;
            
            default: branch_taken = 1'b0;
        endcase
    end

endmodule
