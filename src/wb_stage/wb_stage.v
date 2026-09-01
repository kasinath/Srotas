// ============================================================================
// Module: Writeback Stage (WB)
// File: wb_stage.v
// Project: Srotas RISC-V Processor - Day 5
// 
// Description:
//   The Writeback stage is the final stage of our 5-stage pipeline.
//   It selects between ALU results and memory data, then writes
//   the result back to the register file.
//
// Inputs:
//   - wb_data_mem: Data from memory stage (for load instructions)
//   - wb_data_alu: Data from ALU (for arithmetic/logic instructions)
//   - wb_reg_write: Control signal to enable register write
//   - wb_dest_reg: Destination register address (rd)
//   - wb_mem_to_reg: Mux select (0=ALU result, 1=memory data)
//
// Outputs:
//   - reg_write: Signal to register file
//   - reg_dest: Destination register number
//   - reg_data: Data to write to register
// ============================================================================

module wb_stage (
    input wire clk,
    input wire rst_n,
    
    // Pipeline stall/flush control
    input wire stall,
    input wire flush,
    
    // Inputs from MEM/WB pipeline register
    input wire [31:0] mem_wb_data_mem,      // Data from memory (load results)
    input wire [31:0] mem_wb_data_alu,      // Data from ALU
    input wire mem_wb_reg_write,            // Register write enable
    input wire [4:0] mem_wb_dest_reg,       // Destination register (rd)
    input wire mem_wb_mem_to_reg,           // Mux select: 0=ALU, 1=Memory
    
    // Outputs to Register File (in ID stage)
    output wire reg_write,
    output wire [4:0] reg_dest,
    output wire [31:0] reg_data
);

    // Internal signals
    wire [31:0] selected_data;
    wire effective_reg_write;
    
    // =========================================================================
    // Writeback Data Multiplexer
    // Select between ALU result and Memory data
    // =========================================================================
    assign selected_data = mem_wb_mem_to_reg ? mem_wb_data_mem : mem_wb_data_alu;
    
    // =========================================================================
    // Register Write Control
    // Only write if not stalled, not flushed, and reg_write is enabled
    // =========================================================================
    assign effective_reg_write = mem_wb_reg_write && !stall && !flush;
    
    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign reg_write = effective_reg_write;
    assign reg_dest = flush ? 5'b0 : mem_wb_dest_reg;  // Prevent writing on flush
    assign reg_data = selected_data;
    
    // =========================================================================
    // Debug Output (optional, for simulation)
    // =========================================================================
    // Uncomment for debugging
    // always @(posedge clk) begin
    //     if (effective_reg_write && !flush) begin
    //         $display("[WB] Writing x%0d = 0x%08h", reg_dest, reg_data);
    //     end
    // end

endmodule
