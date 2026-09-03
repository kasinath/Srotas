// ============================================================================
// Module: mem_stage_top
// File: mem_stage_top.v
// Stage: MEM (Memory Access)
//
// Integrates data memory, the A-extension's amo_unit.v, and the MEM/WB
// pipeline register.
//
// amo_unit.v sits between data_memory's read and write ports: for a
// non-AMO instruction, dmem_write_data/dmem_write_en/final_mem_read_data
// are simple passthroughs of the raw EX/MEM values (unchanged behavior).
// For an AMO, amo_unit.v computes the new value from data_memory's own
// (combinational, pre-write) read output and the forwarded rs2 operand,
// and that becomes what data_memory actually writes this same cycle -
// data_memory.v itself needs no changes, since its combinational-read/
// synchronous-write timing was already RMW-safe. final_mem_read_data
// overrides what reaches mem_wb_register only for sc.w (a 0/1 success
// flag, not a memory value); lr.w and the nine regular AMOs already get
// the correct result via the existing RESULT_MEM path with no override at
// all - see amo_unit.v's header for the full reasoning.
// ============================================================================

`timescale 1ns/1ps

module mem_stage_top #(
    parameter integer DMEM_BYTES = 16384,
    parameter         DMEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] ex_pc_plus4,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_mem_write_data,
    input  wire [4:0]  ex_rd_addr,
    input  wire [2:0]  ex_funct3,
    input  wire [31:0] ex_csr_rdata,
    input  wire        ex_reg_write,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire [1:0]  ex_result_src,
    input  wire        ex_is_amo,
    input  wire [4:0]  ex_amo_funct5,

    output wire [31:0] wb_pc_plus4,
    output wire [31:0] wb_alu_result,
    output wire [31:0] wb_mem_read_data,
    output wire [4:0]  wb_rd_addr,
    output wire [31:0] wb_csr_rdata,
    output wire        wb_reg_write,
    output wire [1:0]  wb_result_src
);

    wire [31:0] mem_read_data;
    wire [31:0] amo_write_data;
    wire        amo_write_enable;
    wire [31:0] amo_rd_value;

    wire [31:0] dmem_write_data      = ex_is_amo ? amo_write_data   : ex_mem_write_data;
    wire        dmem_write_en        = ex_is_amo ? amo_write_enable : ex_mem_write;
    wire [31:0] final_mem_read_data  = ex_is_amo ? amo_rd_value     : mem_read_data;

    data_memory #(
        .MEM_BYTES (DMEM_BYTES),
        .INIT_FILE (DMEM_INIT_FILE)
    ) u_data_memory (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_addr       (ex_alu_result),
        .mem_write_data (dmem_write_data),
        .mem_read       (ex_mem_read),
        .mem_write      (dmem_write_en),
        .funct3         (ex_funct3),
        .mem_read_data  (mem_read_data)
    );

    amo_unit u_amo_unit (
        .clk          (clk),
        .rst_n        (rst_n),
        .is_amo       (ex_is_amo),
        .amo_funct5   (ex_amo_funct5),
        .mem_addr     (ex_alu_result),
        .old_value    (mem_read_data),
        .operand      (ex_mem_write_data),
        .mem_read_in  (ex_mem_read),
        .mem_write_in (ex_mem_write),
        .write_data   (amo_write_data),
        .write_enable (amo_write_enable),
        .rd_value     (amo_rd_value)
    );

    mem_wb_register u_mem_wb_register (
        .clk            (clk),
        .rst_n          (rst_n),

        .pc_plus4       (ex_pc_plus4),
        .alu_result     (ex_alu_result),
        .mem_read_data  (final_mem_read_data),
        .rd_addr        (ex_rd_addr),
        .csr_rdata      (ex_csr_rdata),
        .reg_write      (ex_reg_write),
        .result_src     (ex_result_src),

        .pc_plus4_out      (wb_pc_plus4),
        .alu_result_out    (wb_alu_result),
        .mem_read_data_out (wb_mem_read_data),
        .rd_addr_out       (wb_rd_addr),
        .csr_rdata_out     (wb_csr_rdata),
        .reg_write_out     (wb_reg_write),
        .result_src_out    (wb_result_src)
    );

endmodule
