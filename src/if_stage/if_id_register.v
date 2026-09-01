// ============================================================================
// Module: if_id_register
// File: if_id_register.v
// Pipeline register: IF -> ID
//
// write_en = 0 freezes the register (load-use stall: keep presenting the
// same fetched instruction next cycle).
// flush inserts a NOP bubble (branch/jump misprediction squash). flush wins
// over write_en if both happen to be asserted the same cycle.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module if_id_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        write_en,
    input  wire        flush,
    input  wire [31:0] pc_if,
    input  wire [31:0] pc_plus4_if,
    input  wire [31:0] instr_if,

    output reg  [31:0] pc_id,
    output reg  [31:0] pc_plus4_id,
    output reg  [31:0] instr_id
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_id       <= 32'h0;
            pc_plus4_id <= 32'h0;
            instr_id    <= `NOP_INSTR;
        end else if (flush) begin
            pc_id       <= 32'h0;
            pc_plus4_id <= 32'h0;
            instr_id    <= `NOP_INSTR;
        end else if (write_en) begin
            pc_id       <= pc_if;
            pc_plus4_id <= pc_plus4_if;
            instr_id    <= instr_if;
        end
        // else: hold current values (stall)
    end

endmodule
