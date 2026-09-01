/**
 * EX Stage Top Module - Execute Stage Integration
 * 
 * This is the top-level module for the Execute stage. It integrates:
 * - ALU: Performs arithmetic and logical operations
 * - Branch Unit: Determines branch conditions and calculates target addresses
 * - EX/MEM Pipeline Register: Passes data to Memory stage
 * 
 * The EX stage receives decoded instruction data from ID stage, performs
 * calculations, and prepares data for the MEM stage.
 * 
 * @author Srotas Project
 * @day Day 3 - Execute Stage
 */

module ex_stage_top (
    input wire             clk,
    input wire             reset,
    
    // Stall and Flush control signals
    input wire             stall,
    input wire             flush,
    
    // Inputs from ID/EX pipeline register
    input wire [31:0]      operand_a,        // First operand from register file
    input wire [31:0]      operand_b,        // Second operand from register file or immediate
    input wire [31:0]      imm,              // Sign-extended immediate
    input wire [31:0]      pc,               // Current PC value
    input wire [4:0]       rd,               // Destination register number
    input wire [3:0]       alu_control,      // ALU operation control
    input wire [2:0]       branch_type,      // Branch type for branch instructions
    input wire             mem_read,         // Control: memory read enable
    input wire             mem_write,        // Control: memory write enable
    input wire [2:0]       mem_funct3,       // Memory function code
    input wire             reg_write,        // Control: register write enable
    
    // Outputs to MEM stage (via EX/MEM register)
    output wire [31:0]     alu_result_out,
    output wire [31:0]     write_data_out,
    output wire [31:0]     pc_out,
    output wire [4:0]      rd_out,
    output wire            mem_read_out,
    output wire            mem_write_out,
    output wire [2:0]      mem_funct3_out,
    output wire            reg_write_out,
    output wire            branch_taken_out,
    output wire [31:0]     branch_target_out
);

    // Internal wires for ALU
    wire [31:0] alu_result;
    wire        alu_zero;
    wire        alu_overflow;
    
    // Internal wires for Branch Unit
    wire        branch_taken;
    wire [31:0] branch_target;
    
    // Wire for write data (either operand_b for stores or ALU result for writes)
    wire [31:0] write_data;
    
    // Instantiate ALU
    alu u_alu (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (alu_zero),
        .overflow    (alu_overflow)
    );
    
    // Instantiate Branch Unit
    branch_unit u_branch_unit (
        .pc            (pc),
        .imm           (imm),
        .zero          (alu_zero),
        .sign          (alu_result[31]),     // Sign bit of ALU result
        .branch_type   (branch_type),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );
    
    // Determine write data:
    // - For store instructions: use operand_b (data to store)
    // - For other instructions: use alu_result (will be written to register)
    assign write_data = mem_write ? operand_b : alu_result;
    
    // Instantiate EX/MEM Pipeline Register
    ex_mem_register u_ex_mem_register (
        .clk                (clk),
        .reset              (reset),
        .stall              (stall),
        .flush              (flush),
        
        // Inputs from EX stage
        .alu_result         (alu_result),
        .write_data         (write_data),
        .pc                 (pc),
        .rd                 (rd),
        .mem_read           (mem_read),
        .mem_write          (mem_write),
        .mem_funct3         (mem_funct3),
        .reg_write          (reg_write),
        .branch_taken       (branch_taken),
        .branch_target      (branch_target),
        
        // Outputs to MEM stage
        .alu_result_out     (alu_result_out),
        .write_data_out     (write_data_out),
        .pc_out             (pc_out),
        .rd_out             (rd_out),
        .mem_read_out       (mem_read_out),
        .mem_write_out      (mem_write_out),
        .mem_funct3_out     (mem_funct3_out),
        .reg_write_out      (reg_write_out),
        .branch_taken_out   (branch_taken_out),
        .branch_target_out  (branch_target_out)
    );

endmodule
