// ============================================================================
// Module: ex_mem_register
// File: ex_mem_register.v
// Pipeline register: EX -> MEM
//
// No stall/flush inputs: with full forwarding, a load-use hazard is
// resolved by inserting a single bubble at the ID/EX boundary (see
// id_ex_register), and a branch/jump misprediction only ever needs to
// squash instructions still in IF or ID - by the time a branch resolves,
// the instruction sitting in this register is unrelated and must proceed
// normally. So this register is a plain, always-advancing pipeline latch.
// ============================================================================

`timescale 1ns/1ps

module ex_mem_register (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] pc_plus4,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_write_data,
    input  wire [4:0]  rd_addr,
    input  wire [2:0]  funct3,
    input  wire [31:0] csr_rdata,

    input  wire        reg_write,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [1:0]  result_src,

    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_write_data_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [2:0]  funct3_out,
    output reg  [31:0] csr_rdata_out,

    output reg          reg_write_out,
    output reg          mem_read_out,
    output reg          mem_write_out,
    output reg  [1:0]   result_src_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus4_out       <= 32'b0;
            alu_result_out     <= 32'b0;
            mem_write_data_out <= 32'b0;
            rd_addr_out        <= 5'b0;
            funct3_out         <= 3'b0;
            csr_rdata_out      <= 32'b0;
            reg_write_out      <= 1'b0;
            mem_read_out       <= 1'b0;
            mem_write_out      <= 1'b0;
            result_src_out     <= 2'b0;
        end else begin
            pc_plus4_out       <= pc_plus4;
            alu_result_out     <= alu_result;
            mem_write_data_out <= mem_write_data;
            rd_addr_out        <= rd_addr;
            funct3_out         <= funct3;
            csr_rdata_out      <= csr_rdata;
            reg_write_out      <= reg_write;
            mem_read_out       <= mem_read;
            mem_write_out      <= mem_write;
            result_src_out     <= result_src;
        end
    end

endmodule
