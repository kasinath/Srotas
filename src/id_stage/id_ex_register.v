// ============================================================================
// Module: id_ex_register
// File: id_ex_register.v
// Pipeline register: ID -> EX
//
// flush inserts a bubble by zeroing every control signal (reg_write,
// mem_read, mem_write, branch, jump) while leaving data fields alone -
// a zeroed-control instruction is architecturally a NOP regardless of what
// data bits happen to still be sitting in the register.
// flush is used both for a load-use stall bubble and for squashing the
// ID-stage instruction on a branch/jump misprediction.
// ============================================================================

`timescale 1ns/1ps

module id_ex_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire [2:0]  funct3,

    input  wire        reg_write,
    input  wire [1:0]  alu_src_a,
    input  wire        alu_src_b,
    input  wire [3:0]  alu_op,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [1:0]  result_src,
    input  wire        branch,
    input  wire        jump,
    input  wire        is_jalr,

    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg  [2:0]  funct3_out,

    output reg         reg_write_out,
    output reg  [1:0]  alu_src_a_out,
    output reg         alu_src_b_out,
    output reg  [3:0]  alu_op_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg  [1:0]  result_src_out,
    output reg         branch_out,
    output reg         jump_out,
    output reg         is_jalr_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out         <= 32'b0;
            pc_plus4_out   <= 32'b0;
            rs1_addr_out   <= 5'b0;
            rs2_addr_out   <= 5'b0;
            rd_addr_out    <= 5'b0;
            rs1_data_out   <= 32'b0;
            rs2_data_out   <= 32'b0;
            imm_out        <= 32'b0;
            funct3_out     <= 3'b0;
            reg_write_out  <= 1'b0;
            alu_src_a_out  <= 2'b0;
            alu_src_b_out  <= 1'b0;
            alu_op_out     <= 4'b0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            result_src_out <= 2'b0;
            branch_out     <= 1'b0;
            jump_out       <= 1'b0;
            is_jalr_out    <= 1'b0;
        end else begin
            pc_out         <= pc;
            pc_plus4_out   <= pc_plus4;
            rs1_addr_out   <= rs1_addr;
            rs2_addr_out   <= rs2_addr;
            rd_addr_out    <= rd_addr;
            rs1_data_out   <= rs1_data;
            rs2_data_out   <= rs2_data;
            imm_out        <= imm;
            funct3_out     <= funct3;
            alu_src_a_out  <= alu_src_a;
            alu_src_b_out  <= alu_src_b;
            alu_op_out     <= alu_op;

            if (flush) begin
                reg_write_out  <= 1'b0;
                mem_read_out   <= 1'b0;
                mem_write_out  <= 1'b0;
                result_src_out <= 2'b0;
                branch_out     <= 1'b0;
                jump_out       <= 1'b0;
                is_jalr_out    <= 1'b0;
            end else begin
                reg_write_out  <= reg_write;
                mem_read_out   <= mem_read;
                mem_write_out  <= mem_write;
                result_src_out <= result_src;
                branch_out     <= branch;
                jump_out       <= jump;
                is_jalr_out    <= is_jalr;
            end
        end
    end

endmodule
