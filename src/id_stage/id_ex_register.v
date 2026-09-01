/*
 * ID/EX Pipeline Register for RISC-V Processor
 * 
 * Purpose:
 * - Stores all data and control signals between ID and EX stages
 * - Supports stall and flush operations for hazard handling
 * 
 * Data Stored:
 * - PC value (for branch/jump target calculation)
 * - Instruction fields (rs1, rs2, rd, funct3, etc.)
 * - Read data from register file
 * - Sign-extended immediate
 * - All control signals from control unit
 */

module id_ex_register (
    input wire clk,              // Clock signal
    input wire rst_n,            // Active-low asynchronous reset
    input wire stall,            // Stall signal (hold current value)
    input wire flush,            // Flush signal (clear pipeline bubble)
    
    // Inputs from ID stage
    input wire [31:0] pc,                    // Current PC value
    input wire [4:0] rs1_addr,               // Source register 1 address
    input wire [4:0] rs2_addr,               // Source register 2 address
    input wire [4:0] rd_addr,                // Destination register address
    input wire [31:0] rs1_data,              // Data read from rs1
    input wire [31:0] rs2_data,              // Data read from rs2
    input wire [31:0] extended_imm,          // Sign-extended immediate
    input wire [2:0] funct3,                 // Function code 3
    input wire [6:0] funct7,                 // Function code 7
    
    // Control signals from control unit
    input wire reg_write_en,                 // Register write enable
    input wire alu_src,                      // ALU source select
    input wire [3:0] alu_op,                 // ALU operation
    input wire mem_read,                     // Memory read enable
    input wire mem_write,                    // Memory write enable
    input wire mem_to_reg,                   // WB source select
    input wire branch,                       // Branch signal
    input wire jump,                         // Jump signal
    input wire pc_src,                       // PC source select
    
    // Outputs to EX stage
    output reg [31:0] pc_out,                // PC value
    output reg [4:0] rs1_addr_out,           // Source register 1 address
    output reg [4:0] rs2_addr_out,           // Source register 2 address
    output reg [4:0] rd_addr_out,            // Destination register address
    output reg [31:0] rs1_data_out,          // Data read from rs1
    output reg [31:0] rs2_data_out,          // Data read from rs2
    output reg [31:0] extended_imm_out,      // Sign-extended immediate
    output reg [2:0] funct3_out,             // Function code 3
    output reg [6:0] funct7_out,             // Function code 7
    
    // Control signals to EX stage
    output reg reg_write_en_out,             // Register write enable
    output reg alu_src_out,                  // ALU source select
    output reg [3:0] alu_op_out,             // ALU operation
    output reg mem_read_out,                 // Memory read enable
    output reg mem_write_out,                // Memory write enable
    output reg mem_to_reg_out,               // WB source select
    output reg branch_out,                   // Branch signal
    output reg jump_out,                     // Jump signal
    output reg pc_src_out                    // PC source select
);

    // Internal storage registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all outputs to zero
            pc_out <= 32'b0;
            rs1_addr_out <= 5'b0;
            rs2_addr_out <= 5'b0;
            rd_addr_out <= 5'b0;
            rs1_data_out <= 32'b0;
            rs2_data_out <= 32'b0;
            extended_imm_out <= 32'b0;
            funct3_out <= 3'b0;
            funct7_out <= 7'b0;
            reg_write_en_out <= 1'b0;
            alu_src_out <= 1'b0;
            alu_op_out <= 4'b0;
            mem_read_out <= 1'b0;
            mem_write_out <= 1'b0;
            mem_to_reg_out <= 1'b0;
            branch_out <= 1'b0;
            jump_out <= 1'b0;
            pc_src_out <= 1'b0;
        end
        else if (flush) begin
            // Flush: Clear all control signals (create bubble)
            // Keep data but disable operations to prevent incorrect writes
            reg_write_en_out <= 1'b0;
            alu_src_out <= 1'b0;
            mem_read_out <= 1'b0;
            mem_write_out <= 1'b0;
            mem_to_reg_out <= 1'b0;
            branch_out <= 1'b0;
            jump_out <= 1'b0;
            pc_src_out <= 1'b0;
            // Optional: Clear data paths too for complete bubble
            // rd_addr_out <= 5'b0;
            // alu_op_out <= 4'b0;
        end
        else if (!stall) begin
            // Normal operation: Update with new values
            pc_out <= pc;
            rs1_addr_out <= rs1_addr;
            rs2_addr_out <= rs2_addr;
            rd_addr_out <= rd_addr;
            rs1_data_out <= rs1_data;
            rs2_data_out <= rs2_data;
            extended_imm_out <= extended_imm;
            funct3_out <= funct3;
            funct7_out <= funct7;
            reg_write_en_out <= reg_write_en;
            alu_src_out <= alu_src;
            alu_op_out <= alu_op;
            mem_read_out <= mem_read;
            mem_write_out <= mem_write;
            mem_to_reg_out <= mem_to_reg;
            branch_out <= branch;
            jump_out <= jump;
            pc_src_out <= pc_src;
        end
        // If stall is active, hold current values (no assignment needed)
    end

endmodule

/*
 * Operation Modes:
 * 
 * 1. Normal Operation (stall=0, flush=0):
 *    - Data passes through the register on each clock edge
 *    - Standard pipeline flow
 * 
 * 2. Stall (stall=1, flush=0):
 *    - Register holds its current value
 *    - Used for data hazards when waiting for previous instruction
 *    - Creates a "bubble" in the pipeline
 * 
 * 3. Flush (stall=0, flush=1):
 *    - Control signals are cleared to prevent incorrect operations
 *    - Used for control hazards (mispredicted branches)
 *    - Invalidates the current instruction in the pipeline
 * 
 * 4. Reset (rst_n=0):
 *    - All outputs cleared to zero
 *    - Initializes pipeline to known state
 * 
 * Testbench Tips:
 * - Test normal data propagation
 * - Test stall functionality (data should not change)
 * - Test flush functionality (control signals should clear)
 * - Test reset functionality
 * - Test combinations of stall and flush
 */
