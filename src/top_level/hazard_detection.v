// ============================================================================
// Module: Hazard Detection Unit
// File: hazard_detection.v
// Project: Srotas RISC-V Processor - Day 5
// 
// Description:
//   Detects data hazards and generates stall/flush signals.
//   This is a simplified hazard detection unit for learning purposes.
//
// Types of Hazards Handled:
//   1. Load-Use Hazard: Stall when instruction in EX needs data from load in MEM
//   2. Branch Hazard: Flush when branch is taken (simple approach)
//
// Note: A production processor would use forwarding paths to avoid stalls.
//       We're implementing basic stalling for educational clarity.
// ============================================================================

module hazard_detection_unit (
    // From ID/EX pipeline register
    input wire [4:0] id_ex_rs1,           // Source register 1
    input wire [4:0] id_ex_rs2,           // Source register 2
    input wire id_ex_reg_write,           // Will this instruction write?
    input wire [4:0] id_ex_rd,            // Destination register
    
    // From EX/MEM pipeline register
    input wire ex_mem_mem_read,           // Is this a load instruction?
    input wire [4:0] ex_mem_rd,           // Destination of load
    
    // From MEM/WB pipeline register
    input wire mem_wb_reg_write,          // Will WB stage write?
    input wire [4:0] mem_wb_rd,           // Destination register in WB
    
    // Control outputs
    output wire pc_src,                   // Stall PC (hold current value)
    output wire if_id_flush,              // Flush IF/ID register
    output wire id_ex_stall               // Stall ID/EX register
);

    // =========================================================================
    // Load-Use Hazard Detection
    // If instruction in EX is a LOAD, and next instruction (in ID) needs that
    // data, we need to STALL for one cycle.
    // =========================================================================
    wire load_use_hazard;
    
    assign load_use_hazard = 
        ex_mem_mem_read && (
            (id_ex_rs1 == ex_mem_rd && id_ex_rs1 != 5'b0) ||  // rs1 matches load rd
            (id_ex_rs2 == ex_mem_rd && id_ex_rs2 != 5'b0)     // rs2 matches load rd
        );
    
    // =========================================================================
    // Simple Branch Flush (can be enhanced with branch prediction later)
    // For now, we'll handle this in the control unit
    // =========================================================================
    
    // =========================================================================
    // Control Signal Generation
    // =========================================================================
    
    // Stall signal: Assert when load-use hazard detected
    assign id_ex_stall = load_use_hazard;
    
    // PC source: Hold PC when stalled
    assign pc_src = load_use_hazard;
    
    // Flush IF/ID when stalled (don't fetch new instruction)
    assign if_id_flush = load_use_hazard;

endmodule
