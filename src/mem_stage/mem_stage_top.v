// ============================================================================
// Module: mem_stage_top.v
// Stage:  MEM (Memory Access) - Top Level
// Project: Srotas - 5-Stage RISC-V Processor
// Day:    4
//
// Description:
//   Top-level module for the Memory Access stage.
//   Integrates data memory and MEM/WB pipeline register.
//
// Functionality:
//   1. Receives data from EX/MEM register
//   2. Performs memory read/write if needed
//   3. Passes results to MEM/WB register for WB stage
//
// Instructions handled:
//   - LOAD: LB, LH, LW, LBU, LHU (read from memory)
//   - STORE: SB, SH, SW (write to memory)
//   - Other instructions pass through without memory access
//
// Interface:
//   - Inputs from EX/MEM pipeline register
//   - Outputs to MEM/WB pipeline register
// ============================================================================

module mem_stage_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    
    // Inputs from EX/MEM register
    input  wire [31:0] ex_mem_alu_result,   // ALU result (address for load/store)
    input  wire [31:0] ex_mem_write_data,   // Data to store in memory
    input  wire [4:0]  ex_mem_rd,           // Destination register index
    input  wire        ex_mem_reg_write,    // Register write enable
    input  wire        ex_mem_mem_read,     // Memory read enable
    input  wire        ex_mem_mem_write,    // Memory write enable
    input  wire [2:0]  ex_mem_func3,        // Function code for access size
    input  wire        ex_mem_mem_to_reg,   // Select memory data vs ALU result
    
    // Outputs to MEM/WB register
    output wire [31:0] mem_wb_result,
    output wire [31:0] mem_wb_read_data,
    output wire [4:0]  mem_wb_rd,
    output wire        mem_wb_reg_write,
    output wire        mem_wb_mem_to_reg
);

    // Internal wires
    wire [31:0] mem_read_data;
    
    // =========================================================================
    // Data Memory Instance
    // =========================================================================
    data_memory u_data_memory (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_addr       (ex_mem_alu_result),   // Address from ALU
        .mem_write_data (ex_mem_write_data),   // Data to write
        .mem_read       (ex_mem_mem_read),     // Read enable
        .mem_write      (ex_mem_mem_write),    // Write enable
        .mem_func3      (ex_mem_func3),        // Access size
        .mem_read_data  (mem_read_data)        // Data read from memory
    );
    
    // =========================================================================
    // Result Selection Logic
    // For non-memory instructions, pass ALU result
    // For load instructions, this will be overridden by mem_to_reg mux in WB
    // =========================================================================
    wire [31:0] selected_result;
    assign selected_result = ex_mem_alu_result;
    
    // =========================================================================
    // MEM/WB Pipeline Register Instance
    // =========================================================================
    mem_wb_register u_mem_wb_register (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall),
        .flush          (flush),
        
        // Inputs from MEM stage logic
        .mem_result     (selected_result),
        .mem_read_data  (mem_read_data),
        .mem_rd         (ex_mem_rd),
        .mem_reg_write  (ex_mem_reg_write),
        .mem_mem_to_reg (ex_mem_mem_to_reg),
        
        // Outputs to WB stage
        .wb_result      (mem_wb_result),
        .wb_read_data   (mem_wb_read_data),
        .wb_rd          (mem_wb_rd),
        .wb_reg_write   (mem_wb_reg_write),
        .wb_mem_to_reg  (mem_wb_mem_to_reg)
    );

endmodule
