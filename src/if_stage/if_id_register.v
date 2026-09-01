/**
 * IF/ID Pipeline Register
 * 
 * Description:
 * - Captures instruction and PC value at the end of IF stage
 * - Passes data to ID stage on next clock cycle
 * - Supports pipeline stall (hold) and flush (clear) operations
 * 
 * Interface:
 * - clk, rst_n: Clock and reset
 * - stall: When high, hold current values (for hazard handling)
 * - flush: When high, clear to NOP (for branch misprediction)
 * - pc_if: Current PC from IF stage
 * - instr_if: Instruction fetched from memory
 * - pc_id, instr_id: Outputs to ID stage
 */

module if_id_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] pc_if,
    input  wire [31:0] instr_if,
    output reg  [31:0] pc_id,
    output reg  [31:0] instr_id
);

    // NOP instruction for RV32I: ADDI x0, x0, 0 (0x00000013)
    localparam NOP = 32'h00000013;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_id <= 32'h00000000;
            instr_id <= NOP;
        end else if (flush) begin
            // Flush: insert NOP (bubble in pipeline)
            pc_id <= 32'h00000000;
            instr_id <= NOP;
        end else if (!stall) begin
            // Normal operation: capture new values
            pc_id <= pc_if;
            instr_id <= instr_if;
        end
        // If stall is high and flush is low, hold current values
    end

endmodule
