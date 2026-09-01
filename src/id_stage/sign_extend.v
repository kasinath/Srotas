/*
 * Sign Extension Unit for RISC-V Processor
 * 
 * Purpose:
 * - Extends immediate values from instruction format to 32-bit signed values
 * - Different instruction formats have different immediate layouts
 * 
 * RV32I Instruction Formats:
 * - I-type: imm[11:0] -> sign extend to 32 bits
 * - S-type: imm[11:5] + imm[4:0] -> sign extend to 32 bits
 * - B-type: imm[12|10:5|4:1|11] -> sign extend to 32 bits (branch offset)
 * - U-type: imm[31:12] -> already 20 bits, shift left by 12
 * - J-type: imm[20|10:1|11|19:12] -> sign extend to 32 bits (jump offset)
 * 
 * Note: This module receives the full 32-bit instruction and extracts
 * the appropriate immediate based on the instruction format.
 */

module sign_extend (
    input wire [31:0] instruction,   // Full 32-bit instruction
    input wire [2:0] imm_format,     // Immediate format selector
    output reg [31:0] extended_imm   // 32-bit sign-extended immediate
);

    // Immediate format selectors (can be customized based on decoder output)
    localparam IMM_I = 3'b000;  // I-type immediate
    localparam IMM_S = 3'b001;  // S-type immediate
    localparam IMM_B = 3'b010;  // B-type immediate
    localparam IMM_U = 3'b011;  // U-type immediate
    localparam IMM_J = 3'b100;  // J-type immediate
    
    // Individual immediate bits extracted from instruction
    wire imm_11 = instruction[31];      // imm[11] for I, S, B types
    wire imm_10_5 = instruction[30:25]; // imm[10:5] for B, J types
    wire imm_4_1 = instruction[11:8];   // imm[4:1] for B type
    wire imm_12 = instruction[7];       // imm[12] for B type
    wire imm_11_uj = instruction[31];   // imm[11] for J type
    wire imm_19_12 = instruction[19:12];// imm[19:12] for J type
    wire imm_20 = instruction[31];      // imm[20] for J type (same bit as imm_11)
    
    always @(*) begin
        case (imm_format)
            IMM_I: begin
                // I-type: imm[11:0] = inst[31:20]
                // Sign extend bit 31 to fill upper 20 bits
                extended_imm = {{20{instruction[31]}}, instruction[31:20]};
            end
            
            IMM_S: begin
                // S-type: imm[11:0] = {inst[31:25], inst[11:7]}
                // Sign extend bit 31 to fill upper 20 bits
                extended_imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end
            
            IMM_B: begin
                // B-type: imm[12:0] = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
                // Bit layout: imm[12|10:5|4:1|11] -> {inst[31], inst[7], inst[30:25], inst[11:8]}
                // Note: LSB is always 0 (branch targets are half-word aligned)
                extended_imm = {{19{instruction[31]}}, instruction[31], instruction[7], 
                               instruction[30:25], instruction[11:8], 1'b0};
            end
            
            IMM_U: begin
                // U-type: imm[31:12] = inst[31:12]
                // Already in correct position, no sign extension needed
                extended_imm = {instruction[31:12], 12'b0};
            end
            
            IMM_J: begin
                // J-type: imm[20:0] = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
                // Bit layout: imm[20|10:1|11|19:12] -> {inst[31], inst[19:12], inst[20], inst[30:21]}
                // Note: LSB is always 0 (jump targets are half-word aligned)
                extended_imm = {{11{instruction[31]}}, instruction[31], instruction[19:12], 
                               instruction[20], instruction[30:21], 1'b0};
            end
            
            default: begin
                extended_imm = 32'b0;
            end
        endcase
    end

endmodule

/*
 * Usage Notes:
 * 1. The decoder should generate the imm_format signal based on opcode
 * 2. For load/store instructions, use IMM_I or IMM_S
 * 3. For branch instructions, use IMM_B
 * 4. For LUI/AUIPC, use IMM_U
 * 5. For JAL/JALR, use IMM_J or IMM_I respectively
 * 
 * Testbench Tips:
 * - Test positive and negative immediates
 * - Test all immediate formats
 * - Verify sign extension works correctly for negative values
 */
