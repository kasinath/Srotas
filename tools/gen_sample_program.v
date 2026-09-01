// ============================================================================
// File: gen_sample_program.v
// Purpose: Assembles the beginner sample program (mem/program.mem) using the
//          same RV32I encoder functions the testbenches use, and writes it
//          out with $writememh. Not part of the processor RTL - this is a
//          one-off host-side tool. Run it once with any Verilog simulator:
//
//              iverilog -I src/common -I src/testbenches \
//                  -o gen.out -s gen_sample_program tools/gen_sample_program.v
//              vvp gen.out
//
// Program (RV32I assembly):
//   0: addi x5, x0, 0        # sum = 0
//   1: addi x6, x0, 1        # i = 1
//   2: addi x7, x0, 11       # limit = 11
//   3: add  x5, x5, x6       # loop: sum += i
//   4: addi x6, x6, 1        # i++
//   5: bne  x6, x7, -8       # loop back to instruction 3 while i != 11
//   6: addi x2, x0, 0        # x2 = data memory base address
//   7: sw   x5, 0(x2)        # mem[0]  = sum        (55)
//   8: slli x8, x5, 1        # x8 = sum * 2
//   9: sw   x8, 4(x2)        # mem[4]  = sum * 2    (110)
//  10: jal  x0, 0            # halt: spin on self forever
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module gen_sample_program;

    `include "rv32i_encoder.vh"

    reg [31:0] prog [0:10];

    initial begin
        prog[0]  = I_ADDI(5, 0, 32'd0);
        prog[1]  = I_ADDI(6, 0, 32'd1);
        prog[2]  = I_ADDI(7, 0, 32'd11);
        prog[3]  = I_ADD (5, 5, 6);
        prog[4]  = I_ADDI(6, 6, 32'd1);
        prog[5]  = I_BNE (6, 7, -32'sd8);
        prog[6]  = I_ADDI(2, 0, 32'd0);
        prog[7]  = I_SW  (5, 2, 32'd0);
        prog[8]  = I_SLLI(8, 5, 5'd1);
        prog[9]  = I_SW  (8, 2, 32'd4);
        prog[10] = I_JAL (0, 32'd0);

        $writememh("mem/program.mem", prog);
        $display("Wrote mem/program.mem (%0d instructions)", 11);
        $finish;
    end

endmodule
