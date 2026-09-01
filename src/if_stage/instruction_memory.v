// ============================================================================
// Module: instruction_memory
// File: instruction_memory.v
// Stage: IF
//
// Combinational (asynchronous-read) instruction ROM. Word-addressed
// internally; RV32I byte addresses are converted by dropping the two LSBs.
//
// INIT_FILE, when non-empty, is loaded with $readmemh at time zero (and at
// synthesis for FPGA BRAM initial contents). This is how a student drops in
// their own compiled program: point INIT_FILE at their .mem file.
// ============================================================================

`timescale 1ns/1ps

module instruction_memory #(
    parameter integer MEM_WORDS = 4096,          // 16KB of instruction memory
    parameter         INIT_FILE = "program.mem"  // set to "" to skip preload
) (
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    localparam ADDR_BITS = $clog2(MEM_WORDS);

    reg [31:0] mem [0:MEM_WORDS-1];

    wire [ADDR_BITS-1:0] word_addr = addr[ADDR_BITS+1:2];

    assign instr = mem[word_addr];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

endmodule
