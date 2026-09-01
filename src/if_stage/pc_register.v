// ============================================================================
// Module: pc_register
// File: pc_register.v
// Stage: IF
//
// Program Counter register. Holds the address of the instruction currently
// being fetched. Updates every cycle unless held (pc_write_en = 0), which
// happens during a load-use stall.
// ============================================================================

`timescale 1ns/1ps

module pc_register (
    input  wire        clk,
    input  wire        rst_n,        // active-low async reset
    input  wire [31:0] pc_next,
    input  wire        pc_write_en,  // 1 = load pc_next, 0 = hold current value
    output reg  [31:0] pc_current
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_current <= 32'h00000000;
        else if (pc_write_en)
            pc_current <= pc_next;
    end

endmodule
