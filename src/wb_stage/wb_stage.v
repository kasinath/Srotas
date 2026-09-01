// ============================================================================
// Module: wb_stage
// File: wb_stage.v
// Stage: WB (Writeback)
//
// Final stage: selects between ALU result, memory read data, and the
// PC+4 link value (for JAL/JALR), and presents that plus the destination
// register to the register file (fed back into the ID stage at the top
// level) and to the forwarding unit.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module wb_stage (
    input  wire [31:0] pc_plus4,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    input  wire [4:0]  rd_addr,
    input  wire        reg_write,
    input  wire [1:0]  result_src,

    output wire        wb_reg_write,
    output wire [4:0]  wb_rd_addr,
    output wire [31:0] wb_rd_data
);

    reg [31:0] selected_data;
    always @(*) begin
        case (result_src)
            `RESULT_MEM:  selected_data = mem_read_data;
            `RESULT_LINK: selected_data = pc_plus4;
            default:      selected_data = alu_result; // RESULT_ALU
        endcase
    end

    assign wb_reg_write = reg_write;
    assign wb_rd_addr   = rd_addr;
    assign wb_rd_data   = selected_data;

endmodule
