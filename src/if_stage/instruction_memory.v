/**
 * Instruction Memory Module
 * 
 * Description:
 * - Combinational read-only memory for instructions
 * - In real hardware, this connects to instruction cache or ROM
 * - For simulation/testbench, we'll load programs using $readmemh
 * 
 * Interface:
 * - addr: Instruction address from PC
 * - instr: 32-bit instruction output
 * 
 * Note: RV32I uses byte-addressing, but instructions are 4-byte aligned.
 *       The two LSBs of addr are always 00 for aligned instructions.
 */

module instruction_memory (
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    // 4KB instruction memory (adjust size as needed)
    // Address space: 0x0000 to 0x0FFF (1024 words = 4KB)
    reg [31:0] mem [0:1023];
    
    // Convert byte address to word address
    wire [9:0] word_addr = addr[31:2];
    
    // Combinational read
    assign instr = (word_addr < 1024) ? mem[word_addr] : 32'h00000000;
    
    // For testbench: allow loading from file
    // Usage in testbench: $readmemh("program.hex", instruction_memory.mem);
    
endmodule
