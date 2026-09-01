// ============================================================================
// Module: mem_wb_register.v
// Stage:  MEM/WB Pipeline Register
// Project: Srotas - 5-Stage RISC-V Processor
// Day:    4
//
// Description:
//   Pipeline register between MEM and WB stages.
//   Holds all data needed by the Writeback stage.
//
// Features:
//   - Synchronous with clock
//   - Active-low asynchronous reset
//   - Stall enable (hold current value)
//   - Flush capability (clear to zero)
//   - Passes through: result data, destination register, control signals
//
// Interface:
//   - clk: Clock signal
//   - rst_n: Active-low reset
//   - stall: Stall signal (hold current state)
//   - flush: Flush signal (clear to zero)
//   - Inputs from MEM stage
//   - Outputs to WB stage
// ============================================================================

module mem_wb_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    
    // Inputs from MEM stage
    input  wire [31:0] mem_result,       // ALU result or memory data
    input  wire [31:0] mem_read_data,    // Data read from memory
    input  wire [4:0]  mem_rd,           // Destination register index
    input  wire        mem_reg_write,    // Register write enable
    input  wire        mem_mem_to_reg,   // Select memory data vs ALU result
    
    // Outputs to WB stage
    output reg  [31:0] wb_result,
    output reg  [31:0] wb_read_data,
    output reg  [4:0]  wb_rd,
    output reg         wb_reg_write,
    output reg         wb_mem_to_reg
);

    // =========================================================================
    // Pipeline Register Logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: Clear all registers
            wb_result     <= 32'd0;
            wb_read_data  <= 32'd0;
            wb_rd         <= 5'd0;
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= 1'b0;
        end
        else if (flush) begin
            // Flush: Clear all registers (bubble in pipeline)
            wb_result     <= 32'd0;
            wb_read_data  <= 32'd0;
            wb_rd         <= 5'd0;
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= 1'b0;
        end
        else if (!stall) begin
            // Normal operation: Capture inputs
            wb_result     <= mem_result;
            wb_read_data  <= mem_read_data;
            wb_rd         <= mem_rd;
            wb_reg_write  <= mem_reg_write;
            wb_mem_to_reg <= mem_mem_to_reg;
        end
        // else: stall is high, hold current values (no assignment needed)
    end

endmodule
