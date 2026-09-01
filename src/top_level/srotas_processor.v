// ============================================================================
// Module: Srotas - Complete 5-Stage RISC-V Processor
// File: srotas_processor.v
// Project: Srotas RISC-V Processor - Day 5 (Grand Finale!)
// 
// Description:
//   This is the TOP-LEVEL module that connects all 5 stages of our pipeline:
//   IF (Instruction Fetch) → ID (Instruction Decode) → EX (Execute) → 
//   MEM (Memory) → WB (Writeback)
//
// Features:
//   - RV32I Base Integer ISA support
//   - 5-stage pipelined execution
//   - Basic hazard detection (load-use stalls)
//   - Separate Instruction and Data Memory (Harvard Architecture)
//
// Author: Your Learning Journey with AI Assistant
// Date: Day 5 of Processor Development
// ============================================================================

`timescale 1ns/1ps

module srotas_processor (
    input wire clk,           // Clock signal
    input wire rst_n,         // Active-low reset
    
    // Optional: External memory interface (for future expansion)
    output wire [31:0] instr_addr,    // Instruction address out
    input wire [31:0] instr_data,     // Instruction data in
    output wire mem_read,             // Memory read request
    output wire mem_write,            // Memory write request
    output wire [31:0] mem_addr,      // Memory address
    output wire [31:0] mem_wdata,     // Memory write data
    input wire [31:0] mem_rdata       // Memory read data
);

    // =========================================================================
    // Internal Wires - Pipeline Registers
    // =========================================================================
    
    // IF/ID Pipeline Register Signals
    wire [31:0] if_id_instruction;
    wire [31:0] if_id_pc;
    wire if_id_valid;
    
    // ID/EX Pipeline Register Signals
    wire [31:0] id_ex_pc;
    wire [31:0] id_ex_rs1_data;
    wire [31:0] id_ex_rs2_data;
    wire [31:0] id_ex_imm;
    wire [4:0] id_ex_rs1;
    wire [4:0] id_ex_rs2;
    wire [4:0] id_ex_rd;
    wire id_ex_reg_write;
    wire id_ex_mem_read;
    wire id_ex_mem_write;
    wire [2:0] id_ex_alu_op;
    wire id_ex_branch;
    wire [1:0] id_ex_branch_type;
    wire id_ex_jump;
    wire id_ex_mem_to_reg;
    wire id_ex_valid;
    
    // EX/MEM Pipeline Register Signals
    wire [31:0] ex_mem_alu_result;
    wire [31:0] ex_mem_rs2_data;
    wire [4:0] ex_mem_rd;
    wire ex_mem_reg_write;
    wire ex_mem_mem_read;
    wire ex_mem_mem_write;
    wire ex_mem_branch_taken;
    wire ex_mem_valid;
    
    // MEM/WB Pipeline Register Signals
    wire [31:0] mem_wb_data_mem;
    wire [31:0] mem_wb_data_alu;
    wire [4:0] mem_wb_rd;
    wire mem_wb_reg_write;
    wire mem_wb_valid;
    
    // =========================================================================
    // Control Signals for Hazard Detection
    // =========================================================================
    wire pc_src;
    wire if_id_flush;
    wire id_ex_stall;
    
    // =========================================================================
    // Stage Instantiation
    // =========================================================================
    
    // -------------------------------------------------------------------------
    // STAGE 1: INSTRUCTION FETCH (IF)
    // -------------------------------------------------------------------------
    if_stage_top u_if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .pc_src(pc_src),              // Stall from hazard detection
        .if_id_flush(if_id_flush),    // Flush on branch/stall
        .if_id_instruction(if_id_instruction),
        .if_id_pc(if_id_pc),
        .if_id_valid(if_id_valid)
    );
    
    // -------------------------------------------------------------------------
    // STAGE 2: INSTRUCTION DECODE (ID)
    // -------------------------------------------------------------------------
    id_stage_top u_id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(id_ex_stall),          // Stall from hazard detection
        .flush(if_id_flush),          // Flush from hazard detection
        .instruction(if_id_instruction),
        .pc(if_id_pc),
        .id_valid(if_id_valid),
        
        // Outputs to EX stage
        .id_ex_pc(id_ex_pc),
        .id_ex_rs1_data(id_ex_rs1_data),
        .id_ex_rs2_data(id_ex_rs2_data),
        .id_ex_imm(id_ex_imm),
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .id_ex_rd(id_ex_rd),
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_mem_write(id_ex_mem_write),
        .id_ex_alu_op(id_ex_alu_op),
        .id_ex_branch(id_ex_branch),
        .id_ex_branch_type(id_ex_branch_type),
        .id_ex_jump(id_ex_jump),
        .id_ex_mem_to_reg(id_ex_mem_to_reg),
        .id_ex_valid(id_ex_valid)
    );
    
    // -------------------------------------------------------------------------
    // STAGE 3: EXECUTE (EX)
    // -------------------------------------------------------------------------
    ex_stage_top u_ex_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(id_ex_stall),
        .flush(if_id_flush),
        
        // Inputs from ID/EX
        .pc(id_ex_pc),
        .rs1_data(id_ex_rs1_data),
        .rs2_data(id_ex_rs2_data),
        .imm(id_ex_imm),
        .rd(id_ex_rd),
        .reg_write(id_ex_reg_write),
        .mem_read(id_ex_mem_read),
        .mem_write(id_ex_mem_write),
        .alu_op(id_ex_alu_op),
        .branch(id_ex_branch),
        .branch_type(id_ex_branch_type),
        .jump(id_ex_jump),
        .ex_valid(id_ex_valid),
        
        // Outputs to MEM stage
        .ex_mem_alu_result(ex_mem_alu_result),
        .ex_mem_rs2_data(ex_mem_rs2_data),
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_mem_read(ex_mem_mem_read),
        .ex_mem_mem_write(ex_mem_mem_write),
        .ex_mem_branch_taken(ex_mem_branch_taken),
        .ex_mem_valid(ex_mem_valid)
    );
    
    // -------------------------------------------------------------------------
    // STAGE 4: MEMORY (MEM)
    // -------------------------------------------------------------------------
    mem_stage_top u_mem_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(id_ex_stall),
        .flush(if_id_flush),
        
        // Inputs from EX/MEM
        .alu_result(ex_mem_alu_result),
        .rs2_data(ex_mem_rs2_data),
        .rd(ex_mem_rd),
        .reg_write(ex_mem_reg_write),
        .mem_read(ex_mem_mem_read),
        .mem_write(ex_mem_mem_write),
        .mem_valid(ex_mem_valid),
        
        // Outputs to WB stage
        .mem_wb_data_mem(mem_wb_data_mem),
        .mem_wb_rd(mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_valid(mem_wb_valid),
        
        // External memory interface
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata)
    );
    
    // -------------------------------------------------------------------------
    // STAGE 5: WRITEBACK (WB)
    // -------------------------------------------------------------------------
    wb_stage u_wb_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(id_ex_stall),
        .flush(if_id_flush),
        
        // Inputs from MEM/WB
        .mem_wb_data_mem(mem_wb_data_mem),
        .mem_wb_data_alu(ex_mem_alu_result),  // ALU result passed through
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_dest_reg(mem_wb_rd),
        .mem_wb_mem_to_reg(1'b0),             // Simplified: always use ALU result
        
        // Outputs to Register File (internal feedback)
        .reg_write(),
        .reg_dest(),
        .reg_data()
    );
    
    // -------------------------------------------------------------------------
    // HAZARD DETECTION UNIT
    // -------------------------------------------------------------------------
    hazard_detection_unit u_hazard_detector (
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_rd(id_ex_rd),
        
        .ex_mem_mem_read(ex_mem_mem_read),
        .ex_mem_rd(ex_mem_rd),
        
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_rd(mem_wb_rd),
        
        .pc_src(pc_src),
        .if_id_flush(if_id_flush),
        .id_ex_stall(id_ex_stall)
    );
    
    // =========================================================================
    // Debug Output (Optional)
    // =========================================================================
    // Uncomment for simulation debugging
    /*
    always @(posedge clk) begin
        if (!rst_n) begin
            $display("=== SROTAS PROCESSOR RESET ===");
        end else begin
            $display("[%0t] PC=0x%08h Instr=0x%08h", 
                     $time, if_id_pc, if_id_instruction);
        end
    end
    */

endmodule
