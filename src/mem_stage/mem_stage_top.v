// ============================================================================
// Module: mem_stage_top
// File: mem_stage_top.v
// Stage: MEM (Memory Access)
//
// Integrates data memory and the MEM/WB pipeline register.
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
    input  wire        ex_reg_write,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire [1:0]  ex_result_src,

    output wire [31:0] wb_pc_plus4,
    output wire [31:0] wb_alu_result,
    output wire [31:0] wb_mem_read_data,
    output wire [4:0]  wb_rd_addr,
    output wire        wb_reg_write,
    output wire [1:0]  wb_result_src
);

    wire [31:0] mem_read_data;

    data_memory #(
        .MEM_BYTES (DMEM_BYTES),
        .INIT_FILE (DMEM_INIT_FILE)
    ) u_data_memory (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_addr       (ex_alu_result),
        .mem_write_data (ex_mem_write_data),
        .mem_read       (ex_mem_read),
        .mem_write      (ex_mem_write),
        .funct3         (ex_funct3),
        .mem_read_data  (mem_read_data)
    );

    mem_wb_register u_mem_wb_register (
        .clk            (clk),
        .rst_n          (rst_n),

        .pc_plus4       (ex_pc_plus4),
        .alu_result     (ex_alu_result),
        .mem_read_data  (mem_read_data),
        .rd_addr        (ex_rd_addr),
        .reg_write      (ex_reg_write),
        .result_src     (ex_result_src),

        .pc_plus4_out      (wb_pc_plus4),
        .alu_result_out    (wb_alu_result),
        .mem_read_data_out (wb_mem_read_data),
        .rd_addr_out       (wb_rd_addr),
        .reg_write_out     (wb_reg_write),
        .result_src_out    (wb_result_src)
    );

endmodule
