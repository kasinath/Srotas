// ============================================================================
// Module: mem_wb_register
// File: mem_wb_register.v
// Pipeline register: MEM -> WB
//
// Plain always-advancing pipeline latch (see ex_mem_register.v for why no
// stall/flush input is needed in this design).
// ============================================================================

`timescale 1ns/1ps

module mem_wb_register (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] pc_plus4,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    input  wire [4:0]  rd_addr,
    input  wire        reg_write,
    input  wire [1:0]  result_src,

    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_read_data_out,
    output reg  [4:0]  rd_addr_out,
    output reg         reg_write_out,
    output reg  [1:0]  result_src_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus4_out      <= 32'b0;
            alu_result_out    <= 32'b0;
            mem_read_data_out <= 32'b0;
            rd_addr_out       <= 5'b0;
            reg_write_out     <= 1'b0;
            result_src_out    <= 2'b0;
        end else begin
            pc_plus4_out      <= pc_plus4;
            alu_result_out    <= alu_result;
            mem_read_data_out <= mem_read_data;
            rd_addr_out       <= rd_addr;
            reg_write_out     <= reg_write;
            result_src_out    <= result_src;
        end
    end

endmodule
