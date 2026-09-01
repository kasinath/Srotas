// ============================================================================
// Module: Srotas Processor Testbench
// File: processor_tb.v
// Project: Srotas RISC-V Processor - Day 5
// 
// Description:
//   Complete testbench for the 5-stage RISC-V processor.
//   Tests basic arithmetic, logic, memory operations, and branches.
//
// Test Program (RISC-V Assembly):
//   This is a simple program that tests various instructions:
//   
//   addi x1, x0, 10      # x1 = 10
//   addi x2, x0, 20      # x2 = 20
//   add  x3, x1, x2      # x3 = x1 + x2 = 30
//   sub  x4, x2, x1      # x4 = x2 - x1 = 10
//   and  x5, x1, x2      # x5 = x1 & x2
//   or   x6, x1, x2      # x6 = x1 | x2
//   xor  x7, x1, x2      # x7 = x1 ^ x2
//   sll  x8, x1, 2       # x8 = x1 << 2 = 40
//   srl  x9, x8, 1       # x9 = x8 >> 1 = 20
//   lw   x10, 0(x3)      # Load from memory (will need initialization)
//   sw   x4, 4(x3)       # Store to memory
//   beq  x1, x2, end     # Branch if equal (won't take)
//   addi x11, x0, 100    # x11 = 100 (execute this)
// end:
//   addi x12, x0, 200    # x12 = 200
// ============================================================================

`timescale 1ns/1ps

module processor_tb;

    // =========================================================================
    // Testbench Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Memory interface signals
    wire [31:0] mem_addr;
    wire mem_read;
    wire mem_write;
    wire [31:0] mem_wdata;
    reg [31:0] mem_rdata;
    
    // Internal register file monitoring (for verification)
    wire [31:0] reg_data_out;
    
    // =========================================================================
    // Clock Generation (10ns period = 100MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // =========================================================================
    // Simple Memory Model (Combined Instruction & Data Memory)
    // For simplicity, we're using a unified memory here
    // =========================================================================
    reg [31:0] memory [0:1023];  // 4KB memory (1024 words)
    
    initial begin
        // Initialize memory with test program
        // Memory addresses are in bytes, but we access in words (4 bytes)
        
        // Address 0x00000000: Program starts here
        memory[0] = 32'h00a00093;  // addi x1, x0, 10
        memory[1] = 32'h01400113;  // addi x2, x0, 20
        memory[2] = 32'h002081b3;  // add  x3, x1, x2
        memory[3] = 32'h00210233;  // sub  x4, x2, x1
        memory[4] = 32'h0020f2b3;  // and  x5, x1, x2
        memory[5] = 32'h0020e333;  // or   x6, x1, x2
        memory[6] = 32'h0020c3b3;  // xor  x7, x1, x2
        memory[7] = 32'h00209433;  // sll  x8, x1, 2
        memory[8] = 32'h00145493;  // srl  x9, x8, 1
        memory[9] = 32'h00018503;  // lw   x10, 0(x3)  - Will load from addr in x3
        memory[10] = 32'h0041a023; // sw   x4, 4(x3)   - Store x4 to addr in x3+4
        memory[11] = 32'h00208ce3; // beq  x1, x2, end (offset = 4 instructions ahead)
        memory[12] = 32'h06400593; // addi x11, x0, 100
        memory[13] = 32'h0c800613; // addi x12, x0, 200
        memory[14] = 32'h00000013; // nop (end of program)
        
        // Initialize data memory location
        // When x3 = 30, address 30 will be accessed
        memory[8] = 32'hdeadbeef;  // Some initial value at address 32
        
        $display("=== Memory Initialized ===");
        $display("Program loaded at address 0x00000000");
    end
    
    // Memory read process
    always @(posedge clk) begin
        if (mem_read && mem_addr < 4096) begin
            mem_rdata <= memory[mem_addr[31:2]];  // Word-aligned access
        end
    end
    
    // Memory write process
    always @(posedge clk) begin
        if (mem_write && mem_addr < 4096) begin
            memory[mem_addr[31:2]] <= mem_wdata;
            $display("[%0t] MEMORY WRITE: Addr=0x%08h Data=0x%08h", 
                     $time, mem_addr, mem_wdata);
        end
    end
    
    // =========================================================================
    // Instantiate the Processor
    // =========================================================================
    srotas_processor uut (
        .clk(clk),
        .rst_n(rst_n),
        
        // Memory interface
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata)
    );
    
    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        // Initialize signals
        rst_n = 0;
        
        $display("========================================");
        $display("  SROTAS RISC-V PROCESSOR TESTBENCH");
        $display("========================================");
        $display("");
        
        // Apply reset for 2 clock cycles
        $display("[%0t] Asserting RESET...", $time);
        #12 rst_n = 1;
        $display("[%0t] Releasing RESET - Processor starting!", $time);
        $display("");
        
        // Run simulation for enough cycles to execute program
        // With 5-stage pipeline and ~15 instructions, we need ~100 cycles
        #1000;
        
        $display("");
        $display("========================================");
        $display("  TEST COMPLETE");
        $display("========================================");
        $display("");
        
        // Display final results
        $display("Expected Results:");
        $display("  x1  = 10 (0x0000000a)");
        $display("  x2  = 20 (0x00000014)");
        $display("  x3  = 30 (0x0000001e)  [x1 + x2]");
        $display("  x4  = 10 (0x0000000a)  [x2 - x1]");
        $display("  x11 = 100 (0x00000064) [if branch not taken]");
        $display("  x12 = 200 (0x000000c8)");
        $display("");
        
        $finish;
    end
    
    // =========================================================================
    // Monitoring (Optional - uncomment for detailed tracing)
    // =========================================================================
    /*
    always @(posedge clk) begin
        if (rst_n) begin
            $display("[%0t] PC=%0h", $time, uut.u_if_stage.pc_reg.q);
        end
    end
    */
    
    // Waveform generation for simulation
    initial begin
        $dumpfile("srotas_processor.vcd");
        $dumpvars(0, processor_tb);
    end

endmodule
