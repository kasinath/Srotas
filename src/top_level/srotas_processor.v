// ============================================================================
// Module: srotas_processor
// File: srotas_processor.v
// Project: Srotas - 5-Stage RISC-V Processor (RV32I)
//
// Top-level module wiring together IF -> ID -> EX -> MEM -> WB, the
// hazard/forwarding unit, and the register-file writeback feedback path.
//
// Ports are intentionally minimal (clk/rst_n plus a few debug/commit
// outputs): instruction and data memory live inside the IF and MEM stages
// as Harvard-architecture BRAM/LUTRAM, sized and preloaded via the
// IMEM_INIT_FILE / DMEM_INIT_FILE parameters. Point IMEM_INIT_FILE at a
// $readmemh-format .mem file with your compiled program and simulate.
//
// The wb_commit_* outputs let a testbench watch every register write
// without needing hierarchical paths into internal state, which is what
// the self-checking testbenches in src/testbenches use.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module srotas_processor #(
    parameter integer IMEM_WORDS     = 4096,
    parameter         IMEM_INIT_FILE = "program.mem",
    parameter integer DMEM_BYTES     = 16384,
    parameter         DMEM_INIT_FILE = ""
) (
    input  wire clk,
    input  wire rst_n,

    // Debug / commit-monitor outputs (WB stage of the pipeline)
    output wire        wb_commit_valid,
    output wire [4:0]  wb_commit_rd,
    output wire [31:0] wb_commit_data,
    output wire [31:0] if_pc_debug
);

    // -------------------------------------------------------------------
    // IF stage
    // -------------------------------------------------------------------
    wire [31:0] if_id_pc, if_id_pc_plus4, if_id_instr;

    wire pc_write_en, if_id_write_en, if_id_flush;
    wire ex_redirect;
    wire [31:0] ex_redirect_target;

    if_stage_top #(
        .IMEM_WORDS     (IMEM_WORDS),
        .IMEM_INIT_FILE (IMEM_INIT_FILE)
    ) u_if_stage (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc_write_en     (pc_write_en),
        .if_id_write_en  (if_id_write_en),
        .if_id_flush     (if_id_flush),
        .branch_redirect (ex_redirect),
        .branch_target   (ex_redirect_target),
        .if_id_pc        (if_id_pc),
        .if_id_pc_plus4  (if_id_pc_plus4),
        .if_id_instr     (if_id_instr)
    );

    assign if_pc_debug = if_id_pc;

    // -------------------------------------------------------------------
    // ID stage
    // -------------------------------------------------------------------
    wire id_ex_flush;

    wire [4:0] id_rs1_addr, id_rs2_addr;

    wire [31:0] ex_pc, ex_pc_plus4, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [2:0]  ex_funct3;
    wire        ex_reg_write, ex_alu_src_b, ex_mem_read, ex_mem_write;
    wire        ex_branch, ex_jump, ex_is_jalr;
    wire [1:0]  ex_alu_src_a, ex_result_src;
    wire [3:0]  ex_alu_op;

    wire        final_wb_reg_write;
    wire [4:0]  final_wb_rd_addr;
    wire [31:0] final_wb_rd_data;

    id_stage_top u_id_stage (
        .clk          (clk),
        .rst_n        (rst_n),
        .id_ex_flush  (id_ex_flush),

        .instruction  (if_id_instr),
        .pc           (if_id_pc),
        .pc_plus4     (if_id_pc_plus4),

        .wb_reg_write (final_wb_reg_write),
        .wb_rd_addr   (final_wb_rd_addr),
        .wb_rd_data   (final_wb_rd_data),

        .rs1_addr_id  (id_rs1_addr),
        .rs2_addr_id  (id_rs2_addr),

        .ex_pc        (ex_pc),
        .ex_pc_plus4  (ex_pc_plus4),
        .ex_rs1_addr  (ex_rs1_addr),
        .ex_rs2_addr  (ex_rs2_addr),
        .ex_rd_addr   (ex_rd_addr),
        .ex_rs1_data  (ex_rs1_data),
        .ex_rs2_data  (ex_rs2_data),
        .ex_imm       (ex_imm),
        .ex_funct3    (ex_funct3),

        .ex_reg_write  (ex_reg_write),
        .ex_alu_src_a  (ex_alu_src_a),
        .ex_alu_src_b  (ex_alu_src_b),
        .ex_alu_op     (ex_alu_op),
        .ex_mem_read   (ex_mem_read),
        .ex_mem_write  (ex_mem_write),
        .ex_result_src (ex_result_src),
        .ex_branch     (ex_branch),
        .ex_jump       (ex_jump),
        .ex_is_jalr    (ex_is_jalr)
    );

    // -------------------------------------------------------------------
    // EX stage
    // -------------------------------------------------------------------
    wire [1:0] forward_a, forward_b;
    wire [31:0] fwd_exmem_data, fwd_memwb_data;

    wire [31:0] mem_pc_plus4, mem_alu_result, mem_write_data;
    wire [4:0]  mem_rd_addr;
    wire [2:0]  mem_funct3;
    wire        mem_reg_write, mem_mem_read, mem_mem_write;
    wire [1:0]  mem_result_src;

    ex_stage_top u_ex_stage (
        .clk       (clk),
        .rst_n     (rst_n),

        .pc        (ex_pc),
        .pc_plus4  (ex_pc_plus4),
        .rs1_data  (ex_rs1_data),
        .rs2_data  (ex_rs2_data),
        .imm       (ex_imm),
        .rd_addr   (ex_rd_addr),
        .funct3    (ex_funct3),

        .alu_src_a  (ex_alu_src_a),
        .alu_src_b  (ex_alu_src_b),
        .alu_op     (ex_alu_op),
        .mem_read   (ex_mem_read),
        .mem_write  (ex_mem_write),
        .reg_write  (ex_reg_write),
        .result_src (ex_result_src),
        .branch     (ex_branch),
        .jump       (ex_jump),
        .is_jalr    (ex_is_jalr),

        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .fwd_exmem_data (fwd_exmem_data),
        .fwd_memwb_data (fwd_memwb_data),

        .redirect        (ex_redirect),
        .redirect_target (ex_redirect_target),

        .mem_pc_plus4    (mem_pc_plus4),
        .mem_alu_result  (mem_alu_result),
        .mem_write_data  (mem_write_data),
        .mem_rd_addr     (mem_rd_addr),
        .mem_funct3      (mem_funct3),
        .mem_reg_write   (mem_reg_write),
        .mem_mem_read    (mem_mem_read),
        .mem_mem_write   (mem_mem_write),
        .mem_result_src  (mem_result_src)
    );

    // Best-available forwarded value from the instruction currently one
    // stage ahead (in MEM): its ALU result, or its link value if it was a
    // JAL/JALR (load results are never forwarded from here - the load-use
    // stall guarantees a producing load is never the EX/MEM forward source).
    assign fwd_exmem_data = (mem_result_src == `RESULT_LINK) ? mem_pc_plus4 : mem_alu_result;
    assign fwd_memwb_data = final_wb_rd_data;

    // -------------------------------------------------------------------
    // MEM stage
    // -------------------------------------------------------------------
    wire [31:0] memwb_pc_plus4, memwb_alu_result, memwb_mem_read_data;
    wire [4:0]  memwb_rd_addr;
    wire        memwb_reg_write;
    wire [1:0]  memwb_result_src;

    mem_stage_top #(
        .DMEM_BYTES     (DMEM_BYTES),
        .DMEM_INIT_FILE (DMEM_INIT_FILE)
    ) u_mem_stage (
        .clk               (clk),
        .rst_n             (rst_n),

        .ex_pc_plus4       (mem_pc_plus4),
        .ex_alu_result     (mem_alu_result),
        .ex_mem_write_data (mem_write_data),
        .ex_rd_addr        (mem_rd_addr),
        .ex_funct3         (mem_funct3),
        .ex_reg_write      (mem_reg_write),
        .ex_mem_read       (mem_mem_read),
        .ex_mem_write      (mem_mem_write),
        .ex_result_src     (mem_result_src),

        .wb_pc_plus4      (memwb_pc_plus4),
        .wb_alu_result    (memwb_alu_result),
        .wb_mem_read_data (memwb_mem_read_data),
        .wb_rd_addr       (memwb_rd_addr),
        .wb_reg_write     (memwb_reg_write),
        .wb_result_src    (memwb_result_src)
    );

    // -------------------------------------------------------------------
    // WB stage
    // -------------------------------------------------------------------
    wb_stage u_wb_stage (
        .pc_plus4      (memwb_pc_plus4),
        .alu_result    (memwb_alu_result),
        .mem_read_data (memwb_mem_read_data),
        .rd_addr       (memwb_rd_addr),
        .reg_write     (memwb_reg_write),
        .result_src    (memwb_result_src),

        .wb_reg_write (final_wb_reg_write),
        .wb_rd_addr   (final_wb_rd_addr),
        .wb_rd_data   (final_wb_rd_data)
    );

    // Gated by rd != 0 so this reports actual architectural state changes
    // (a write targeting x0 is architecturally a no-op, even though the
    // control path still raises reg_write for it, e.g. "jal x0, ...").
    assign wb_commit_valid = final_wb_reg_write && (final_wb_rd_addr != 5'd0);
    assign wb_commit_rd    = final_wb_rd_addr;
    assign wb_commit_data  = final_wb_rd_data;

    // -------------------------------------------------------------------
    // Hazard detection / forwarding unit
    // -------------------------------------------------------------------
    hazard_detection_unit u_hazard_detector (
        .id_rs1_addr     (id_rs1_addr),
        .id_rs2_addr     (id_rs2_addr),

        .id_ex_rs1_addr  (ex_rs1_addr),
        .id_ex_rs2_addr  (ex_rs2_addr),
        .id_ex_rd_addr   (ex_rd_addr),
        .id_ex_mem_read  (ex_mem_read),

        .ex_mem_rd_addr    (mem_rd_addr),
        .ex_mem_reg_write  (mem_reg_write),

        .mem_wb_rd_addr    (final_wb_rd_addr),
        .mem_wb_reg_write  (final_wb_reg_write),

        .ex_redirect (ex_redirect),

        .pc_write_en    (pc_write_en),
        .if_id_write_en (if_id_write_en),
        .if_id_flush    (if_id_flush),
        .id_ex_flush    (id_ex_flush),

        .forward_a (forward_a),
        .forward_b (forward_b)
    );

endmodule
