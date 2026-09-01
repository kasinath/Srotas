// ============================================================================
// Module: ex_stage_top
// File: ex_stage_top.v
// Stage: EX (Execute)
//
// Integrates the operand-forwarding muxes, ALU, branch/jump resolution,
// and the EX/MEM pipeline register.
//
// Forwarding: forward_a/forward_b (driven by the top-level hazard/forward
// unit) select between the ID/EX-latched register value, the result of the
// instruction one stage ahead (in MEM, "EX/MEM forwarding"), or the result
// of the instruction two stages ahead (in WB, "MEM/WB forwarding"). This
// resolves back-to-back RAW dependencies without stalling. The one case
// forwarding cannot fix - a load immediately followed by a dependent
// instruction - is handled upstream by a 1-cycle stall (bubble) instead,
// since load data simply is not ready yet at that point.
//
// Store data always uses the forwarded rs2 value, independent of whichever
// operand the ALU's B input is using (which is the immediate for address
// calculation on a store) - these are two different uses of rs2 and must
// not be conflated.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module ex_stage_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire [4:0]  rd_addr,
    input  wire [2:0]  funct3,

    input  wire [1:0]  alu_src_a,
    input  wire        alu_src_b,
    input  wire [3:0]  alu_op,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        reg_write,
    input  wire [1:0]  result_src,
    input  wire        branch,
    input  wire        jump,
    input  wire        is_jalr,

    // Forwarding
    input  wire [1:0]  forward_a,
    input  wire [1:0]  forward_b,
    input  wire [31:0] fwd_exmem_data,
    input  wire [31:0] fwd_memwb_data,

    // Branch/jump resolution, back to IF stage
    output wire         redirect,
    output wire [31:0]  redirect_target,

    // To MEM stage (via EX/MEM register)
    output wire [31:0] mem_pc_plus4,
    output wire [31:0] mem_alu_result,
    output wire [31:0] mem_write_data,
    output wire [4:0]  mem_rd_addr,
    output wire [2:0]  mem_funct3,
    output wire        mem_reg_write,
    output wire        mem_mem_read,
    output wire        mem_mem_write,
    output wire [1:0]  mem_result_src
);

    // ---------------------------------------------------------------
    // Forwarding muxes
    // ---------------------------------------------------------------
    reg [31:0] rs1_fwd, rs2_fwd;
    always @(*) begin
        case (forward_a)
            2'b01:   rs1_fwd = fwd_exmem_data;
            2'b10:   rs1_fwd = fwd_memwb_data;
            default: rs1_fwd = rs1_data;
        endcase
        case (forward_b)
            2'b01:   rs2_fwd = fwd_exmem_data;
            2'b10:   rs2_fwd = fwd_memwb_data;
            default: rs2_fwd = rs2_data;
        endcase
    end

    // ---------------------------------------------------------------
    // ALU operand selection
    // ---------------------------------------------------------------
    reg [31:0] operand_a;
    always @(*) begin
        case (alu_src_a)
            `ASEL_PC:   operand_a = pc;
            `ASEL_ZERO: operand_a = 32'b0;
            default:    operand_a = rs1_fwd; // ASEL_RS1
        endcase
    end

    wire [31:0] operand_b = alu_src_b ? imm : rs2_fwd;

    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .operand_a (operand_a),
        .operand_b (operand_b),
        .alu_op    (alu_op),
        .result    (alu_result),
        .zero      (alu_zero)
    );

    branch_unit u_branch_unit (
        .pc              (pc),
        .imm             (imm),
        .alu_result      (alu_result),
        .alu_zero        (alu_zero),
        .funct3          (funct3),
        .branch          (branch),
        .jump            (jump),
        .is_jalr         (is_jalr),
        .redirect        (redirect),
        .redirect_target (redirect_target)
    );

    // Data to store to memory is always the (forwarded) rs2 value, never
    // whatever the ALU's B operand happened to be selecting.
    wire [31:0] store_data = rs2_fwd;

    ex_mem_register u_ex_mem_register (
        .clk             (clk),
        .rst_n           (rst_n),

        .pc_plus4        (pc_plus4),
        .alu_result      (alu_result),
        .mem_write_data  (store_data),
        .rd_addr         (rd_addr),
        .funct3          (funct3),

        .reg_write       (reg_write),
        .mem_read        (mem_read),
        .mem_write       (mem_write),
        .result_src      (result_src),

        .pc_plus4_out       (mem_pc_plus4),
        .alu_result_out     (mem_alu_result),
        .mem_write_data_out (mem_write_data),
        .rd_addr_out        (mem_rd_addr),
        .funct3_out         (mem_funct3),
        .reg_write_out      (mem_reg_write),
        .mem_read_out       (mem_mem_read),
        .mem_write_out      (mem_mem_write),
        .result_src_out     (mem_result_src)
    );

endmodule
