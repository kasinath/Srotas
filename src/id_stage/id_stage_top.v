/*
 * Instruction Decode (ID) Stage Top Module for RISC-V Processor
 * 
 * Purpose:
 * - Integrates all ID stage components
 * - Decodes instruction from IF stage
 * - Reads registers, generates control signals, extends immediates
 * - Passes decoded information to EX stage via pipeline register
 * 
 * Components Instantiated:
 * 1. Register File - Read two source registers
 * 2. Control Unit - Generate control signals based on opcode
 * 3. Sign Extend Unit - Extend immediate values
 * 4. ID/EX Pipeline Register - Store data for next stage
 */

module id_stage_top (
    input wire clk,              // Clock signal
    input wire rst_n,            // Active-low asynchronous reset
    
    // Stall and flush control
    input wire stall,            // Stall ID stage (for hazards)
    input wire flush,            // Flush ID/EX pipeline register
    
    // Inputs from IF/ID pipeline register (from IF stage)
    input wire [31:0] instruction,   // Current instruction
    input wire [31:0] pc,            // Current PC value
    
    // Outputs to ID/EX pipeline register (to EX stage)
    // These are driven by the id_ex_register module
    output wire [31:0] ex_pc,                // PC value
    output wire [4:0] ex_rs1_addr,           // Source register 1 address
    output wire [4:0] ex_rs2_addr,           // Source register 2 address
    output wire [4:0] ex_rd_addr,            // Destination register address
    output wire [31:0] ex_rs1_data,          // Data read from rs1
    output wire [31:0] ex_rs2_data,          // Data read from rs2
    output wire [31:0] ex_extended_imm,      // Sign-extended immediate
    output wire [2:0] ex_funct3,             // Function code 3
    output wire [6:0] ex_funct7,             // Function code 7
    output wire ex_reg_write_en,             // Register write enable
    output wire ex_alu_src,                  // ALU source select
    output wire [3:0] ex_alu_op,             // ALU operation
    output wire ex_mem_read,                 // Memory read enable
    output wire ex_mem_write,                // Memory write enable
    output wire ex_mem_to_reg,               // WB source select
    output wire ex_branch,                   // Branch signal
    output wire ex_jump,                     // Jump signal
    output wire ex_pc_src                    // PC source select
);

    // Internal wires for instruction fields
    wire [6:0] opcode;
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [4:0] rd_addr;
    wire [2:0] funct3;
    wire [6:0] funct7;
    
    // Internal wires for register file data
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    
    // Internal wires for control signals
    wire reg_write_en;
    wire alu_src;
    wire [3:0] alu_op;
    wire mem_read;
    wire mem_write;
    wire mem_to_reg;
    wire branch;
    wire jump;
    wire pc_src;
    wire [2:0] imm_format;
    
    // Internal wire for extended immediate
    wire [31:0] extended_imm;
    
    // ================================================================
    // Instruction Field Extraction
    // ================================================================
    // RV32I Instruction Format:
    // [31:25] funct7/immediate bits
    // [24:20] rs2 / immediate bits
    // [19:15] rs1 / immediate bits
    // [14:12] funct3
    // [11:7]  rd / immediate bits
    // [6:0]   opcode
    
    assign opcode = instruction[6:0];
    assign rs1_addr = instruction[19:15];
    assign rs2_addr = instruction[24:20];
    assign rd_addr = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    
    // ================================================================
    // Register File Instance
    // ================================================================
    register_file u_register_file (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(rs1_addr),
        .rs1_data(rs1_data),
        .rs2_addr(rs2_addr),
        .rs2_data(rs2_data),
        .rd_addr(ex_rd_addr),      // Write address comes from EX/WB stage later
        .rd_data(32'b0),           // Will be connected from WB stage in top-level
        .reg_write_en(ex_reg_write_en),  // Will be connected from WB stage
        .mem_to_reg(1'b0)          // Will be connected from WB stage
    );
    
    // Note: For now, register writeback is disabled in ID stage
    // In the complete processor, this will be controlled by WB stage signals
    
    // ================================================================
    // Control Unit Instance
    // ================================================================
    control_unit u_control_unit (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .reg_write_en(reg_write_en),
        .alu_src(alu_src),
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .branch(branch),
        .jump(jump),
        .imm_format(imm_format),
        .pc_src(pc_src)
    );
    
    // ================================================================
    // Sign Extension Unit Instance
    // ================================================================
    sign_extend u_sign_extend (
        .instruction(instruction),
        .imm_format(imm_format),
        .extended_imm(extended_imm)
    );
    
    // ================================================================
    // ID/EX Pipeline Register Instance
    // ================================================================
    id_ex_register u_id_ex_register (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        
        // Inputs from ID stage combinational logic
        .pc(pc),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .extended_imm(extended_imm),
        .funct3(funct3),
        .funct7(funct7),
        .reg_write_en(reg_write_en),
        .alu_src(alu_src),
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .branch(branch),
        .jump(jump),
        .pc_src(pc_src),
        
        // Outputs to EX stage
        .pc_out(ex_pc),
        .rs1_addr_out(ex_rs1_addr),
        .rs2_addr_out(ex_rs2_addr),
        .rd_addr_out(ex_rd_addr),
        .rs1_data_out(ex_rs1_data),
        .rs2_data_out(ex_rs2_data),
        .extended_imm_out(ex_extended_imm),
        .funct3_out(ex_funct3),
        .funct7_out(ex_funct7),
        .reg_write_en_out(ex_reg_write_en),
        .alu_src_out(ex_alu_src),
        .alu_op_out(ex_alu_op),
        .mem_read_out(ex_mem_read),
        .mem_write_out(ex_mem_write),
        .mem_to_reg_out(ex_mem_to_reg),
        .branch_out(ex_branch),
        .jump_out(ex_jump),
        .pc_src_out(ex_pc_src)
    );

endmodule

/*
 * ID Stage Operation Summary:
 * 
 * 1. Instruction arrives from IF stage (via IF/ID pipeline register)
 * 2. Instruction fields are extracted (opcode, rs1, rs2, rd, funct3, funct7)
 * 3. Register file reads two source registers (rs1_data, rs2_data)
 * 4. Control unit decodes opcode and generates control signals
 * 5. Sign extension unit creates 32-bit immediate from instruction
 * 6. All data and control signals are stored in ID/EX pipeline register
 * 7. On next clock cycle, data moves to EX stage
 * 
 * Hazard Handling:
 * - Stall: Holds current values in ID/EX register (for data hazards)
 * - Flush: Clears control signals in ID/EX register (for control hazards)
 * 
 * Next Steps (Day 3):
 * - Build Execute (EX) stage with ALU
 * - Implement branch comparison logic
 * - Create EX/MEM pipeline register
 */
