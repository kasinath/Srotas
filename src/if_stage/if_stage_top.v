/**
 * Instruction Fetch (IF) Stage Top Module
 * 
 * Description:
 * - Fetches instructions from memory
 * - Manages PC updates (sequential, branch, jump)
 * - Interfaces with IF/ID pipeline register
 * 
 * This is the first stage of our 5-stage RISC-V pipeline:
 *   IF → ID → EX → MEM → WB
 * 
 * Operations handled:
 *   - Sequential fetch: PC = PC + 4
 *   - Branch target: PC = PC + offset (for branches)
 *   - Jump target: PC = PC + offset or register (for jumps)
 */

module if_stage (
    // Clock and reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control signals from later stages
    input  wire        stall,      // Hold PC (data hazard)
    input  wire        flush,      // Clear pipeline (control hazard)
    input  wire [31:0] branch_target,  // Target address from EX stage
    input  wire        branch_valid,    // Branch taken signal
    
    // Output to ID stage
    output wire [31:0] pc_id,
    output wire [31:0] instr_id
);

    // Internal signals
    wire [31:0] pc_current;
    wire [31:0] pc_next_sequential;
    wire [31:0] pc_next;
    wire [31:0] instr_fetched;
    wire        pc_update;
    
    // Calculate next sequential PC (PC + 4)
    assign pc_next_sequential = pc_current + 32'h00000004;
    
    // Select next PC: branch target or sequential
    // Priority: branch > sequential
    assign pc_next = branch_valid ? branch_target : pc_next_sequential;
    
    // PC updates unless stalled
    assign pc_update = !(stall);
    
    // Instantiate PC Register
    pc_register u_pc_register (
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_update(pc_update),
        .pc_current(pc_current)
    );
    
    // Instantiate Instruction Memory
    instruction_memory u_instruction_memory (
        .addr(pc_current),
        .instr(instr_fetched)
    );
    
    // Instantiate IF/ID Pipeline Register
    if_id_register u_if_id_register (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .pc_if(pc_current),
        .instr_if(instr_fetched),
        .pc_id(pc_id),
        .instr_id(instr_id)
    );

endmodule
