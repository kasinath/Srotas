/**
 * EX/MEM Pipeline Register
 * 
 * This register holds all data needed by the Memory stage.
 * It captures data at the end of the Execute stage and passes it to MEM stage.
 * 
 * Features:
 * - Stall support: Hold current value when stall is asserted
 * - Flush support: Clear/zero out values when flush is asserted
 * - Stores all necessary control signals and data for MEM stage
 * 
 * @author Srotas Project
 * @day Day 3 - Execute Stage
 */

module ex_mem_register (
    input wire             clk,
    input wire             reset,
    
    // Stall and Flush control
    input wire             stall,      // Hold current value when high
    input wire             flush,      // Zero out outputs when high
    
    // Inputs from EX stage
    input wire [31:0]      alu_result,       // Result from ALU
    input wire [31:0]      write_data,       // Data to write to memory/register
    input wire [31:0]      pc,               // Current PC (for branch target calculation)
    input wire [4:0]       rd,               // Destination register number
    input wire             mem_read,         // Control: memory read enable
    input wire             mem_write,        // Control: memory write enable
    input wire [2:0]       mem_funct3,       // Memory function code (byte/half/word)
    input wire             reg_write,        // Control: register write enable
    input wire             branch_taken,     // Branch decision from branch unit
    input wire [31:0]      branch_target,    // Target address if branch taken
    
    // Outputs to MEM stage
    output reg [31:0]      alu_result_out,
    output reg [31:0]      write_data_out,
    output reg [31:0]      pc_out,
    output reg [4:0]       rd_out,
    output reg             mem_read_out,
    output reg             mem_write_out,
    output reg [2:0]       mem_funct3_out,
    output reg             reg_write_out,
    output reg             branch_taken_out,
    output reg [31:0]      branch_target_out
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset all outputs to zero
            alu_result_out    <= 32'b0;
            write_data_out    <= 32'b0;
            pc_out            <= 32'b0;
            rd_out            <= 5'b0;
            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            mem_funct3_out    <= 3'b0;
            reg_write_out     <= 1'b0;
            branch_taken_out  <= 1'b0;
            branch_target_out <= 32'b0;
        end
        else if (flush) begin
            // Flush: zero out all outputs (bubble in pipeline)
            alu_result_out    <= 32'b0;
            write_data_out    <= 32'b0;
            pc_out            <= 32'b0;
            rd_out            <= 5'b0;
            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            mem_funct3_out    <= 3'b0;
            reg_write_out     <= 1'b0;
            branch_taken_out  <= 1'b0;
            branch_target_out <= 32'b0;
        end
        else if (!stall) begin
            // Normal operation: capture inputs on clock edge
            alu_result_out    <= alu_result;
            write_data_out    <= write_data;
            pc_out            <= pc;
            rd_out            <= rd;
            mem_read_out      <= mem_read;
            mem_write_out     <= mem_write;
            mem_funct3_out    <= mem_funct3;
            reg_write_out     <= reg_write;
            branch_taken_out  <= branch_taken;
            branch_target_out <= branch_target;
        end
        // If stall is high, maintain current values (no assignment needed)
    end

endmodule
