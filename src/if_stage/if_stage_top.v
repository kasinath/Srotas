// ============================================================================
// Module: if_stage_top
// File: if_stage_top.v
// Stage: IF (Instruction Fetch)
//
// Integrates the PC register, instruction memory, and the IF/ID pipeline
// register. Next-PC selection priority: branch/jump redirect from EX beats
// sequential PC+4. A load-use stall freezes both the PC and the IF/ID
// register so the same instruction is re-presented to ID next cycle.
// ============================================================================

`timescale 1ns/1ps

module if_stage_top #(
    parameter integer IMEM_WORDS = 4096,
    parameter         IMEM_INIT_FILE = "program.mem"
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire         pc_write_en,   // 0 during load-use stall
    input  wire         if_id_write_en,// 0 during load-use stall
    input  wire         if_id_flush,   // 1 on branch/jump misprediction

    input  wire         branch_redirect,   // taken branch/jump resolved in EX
    input  wire [31:0]  branch_target,     // redirect target from EX

    output wire [31:0] if_id_pc,
    output wire [31:0] if_id_pc_plus4,
    output wire [31:0] if_id_instr
);

    wire [31:0] pc_current;
    wire [31:0] pc_plus4      = pc_current + 32'd4;
    wire [31:0] pc_next       = branch_redirect ? branch_target : pc_plus4;
    wire [31:0] instr_fetched;

    pc_register u_pc_register (
        .clk         (clk),
        .rst_n       (rst_n),
        .pc_next     (pc_next),
        .pc_write_en (pc_write_en),
        .pc_current  (pc_current)
    );

    instruction_memory #(
        .MEM_WORDS (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT_FILE)
    ) u_instruction_memory (
        .addr  (pc_current),
        .instr (instr_fetched)
    );

    if_id_register u_if_id_register (
        .clk         (clk),
        .rst_n       (rst_n),
        .write_en    (if_id_write_en),
        .flush       (if_id_flush),
        .pc_if       (pc_current),
        .pc_plus4_if (pc_plus4),
        .instr_if    (instr_fetched),
        .pc_id       (if_id_pc),
        .pc_plus4_id (if_id_pc_plus4),
        .instr_id    (if_id_instr)
    );

endmodule
