// ============================================================================
// Module: id_stage_top
// File: id_stage_top.v
// Stage: ID (Instruction Decode)
//
// Decodes the instruction from IF/ID, reads the register file, generates
// control signals, sign-extends the immediate, and latches everything into
// the ID/EX pipeline register.
//
// The register file's write port is driven by the WB stage of a *different*
// (later) instruction; those signals are fed back in from the top level
// (wb_reg_write / wb_rd_addr / wb_rd_data) - the standard "regfile spans ID
// and WB" structure of every textbook pipeline diagram.
// ============================================================================

`timescale 1ns/1ps

module id_stage_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        id_ex_flush,     // bubble: load-use stall or branch squash

    input  wire [31:0] instruction,
    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,

    // Writeback feedback (from WB stage, via top level)
    input  wire         wb_reg_write,
    input  wire [4:0]   wb_rd_addr,
    input  wire [31:0]  wb_rd_data,

    // Decoded register addresses, exposed combinationally for hazard
    // detection (these describe the instruction currently in ID, i.e. the
    // one about to be latched into ID/EX next edge).
    output wire [4:0]  rs1_addr_id,
    output wire [4:0]  rs2_addr_id,

    // Outputs to EX stage (registered, one cycle later)
    output wire [31:0] ex_pc,
    output wire [31:0] ex_pc_plus4,
    output wire [4:0]  ex_rs1_addr,
    output wire [4:0]  ex_rs2_addr,
    output wire [4:0]  ex_rd_addr,
    output wire [31:0] ex_rs1_data,
    output wire [31:0] ex_rs2_data,
    output wire [31:0] ex_imm,
    output wire [2:0]  ex_funct3,
    output wire [11:0] ex_csr_addr,

    output wire        ex_reg_write,
    output wire [1:0]  ex_alu_src_a,
    output wire        ex_alu_src_b,
    output wire [3:0]  ex_alu_op,
    output wire        ex_mem_read,
    output wire        ex_mem_write,
    output wire [1:0]  ex_result_src,
    output wire        ex_branch,
    output wire        ex_jump,
    output wire        ex_is_jalr,
    output wire [1:0]  ex_csr_op,
    output wire        ex_csr_use_imm,
    output wire        ex_ecall,
    output wire        ex_ebreak,
    output wire        ex_mret,
    output wire        ex_illegal
);

    wire [6:0] opcode  = instruction[6:0];
    wire [4:0] rs1_addr = instruction[19:15];
    wire [4:0] rs2_addr = instruction[24:20];
    wire [4:0] rd_addr  = instruction[11:7];
    wire [2:0] funct3   = instruction[14:12];
    wire [6:0] funct7   = instruction[31:25];
    // Same bit range as the I-type immediate, but a CSR address is an
    // unsigned 12-bit index, not a value to sign-extend - so it's taken
    // directly from the instruction rather than routed through
    // sign_extend.v's IMM_I path.
    wire [11:0] csr_addr = instruction[31:20];

    assign rs1_addr_id = rs1_addr;
    assign rs2_addr_id = rs2_addr;

    wire [31:0] rs1_data, rs2_data;
    wire [31:0] extended_imm;

    wire        reg_write;
    wire [1:0]  alu_src_a;
    wire        alu_src_b;
    wire [3:0]  alu_op;
    wire        mem_read;
    wire        mem_write;
    wire [1:0]  result_src;
    wire        branch;
    wire        jump;
    wire        is_jalr;
    wire [2:0]  imm_format;
    wire [1:0]  csr_op;
    wire        csr_use_imm;
    wire        ecall;
    wire        ebreak;
    wire        mret;
    wire        illegal;

    register_file u_register_file (
        .clk          (clk),
        .rst_n        (rst_n),
        .rs1_addr     (rs1_addr),
        .rs1_data     (rs1_data),
        .rs2_addr     (rs2_addr),
        .rs2_data     (rs2_data),
        .rd_addr      (wb_rd_addr),
        .rd_data      (wb_rd_data),
        .reg_write_en (wb_reg_write)
    );

    control_unit u_control_unit (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7     (funct7),
        .csr_addr   (csr_addr),
        .reg_write  (reg_write),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .result_src (result_src),
        .branch     (branch),
        .jump       (jump),
        .is_jalr    (is_jalr),
        .imm_format (imm_format),
        .csr_op      (csr_op),
        .csr_use_imm (csr_use_imm),
        .ecall       (ecall),
        .ebreak      (ebreak),
        .mret        (mret),
        .illegal     (illegal)
    );

    sign_extend u_sign_extend (
        .instruction  (instruction),
        .imm_format   (imm_format),
        .extended_imm (extended_imm)
    );

    id_ex_register u_id_ex_register (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (id_ex_flush),

        .pc        (pc),
        .pc_plus4  (pc_plus4),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rd_addr   (rd_addr),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data),
        .imm       (extended_imm),
        .funct3    (funct3),
        .csr_addr  (csr_addr),

        .reg_write  (reg_write),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .result_src (result_src),
        .branch     (branch),
        .jump       (jump),
        .is_jalr    (is_jalr),
        .csr_op      (csr_op),
        .csr_use_imm (csr_use_imm),
        .ecall       (ecall),
        .ebreak      (ebreak),
        .mret        (mret),
        .illegal     (illegal),

        .pc_out         (ex_pc),
        .pc_plus4_out   (ex_pc_plus4),
        .rs1_addr_out   (ex_rs1_addr),
        .rs2_addr_out   (ex_rs2_addr),
        .rd_addr_out    (ex_rd_addr),
        .rs1_data_out   (ex_rs1_data),
        .rs2_data_out   (ex_rs2_data),
        .imm_out        (ex_imm),
        .funct3_out     (ex_funct3),
        .csr_addr_out   (ex_csr_addr),

        .reg_write_out  (ex_reg_write),
        .alu_src_a_out  (ex_alu_src_a),
        .alu_src_b_out  (ex_alu_src_b),
        .alu_op_out     (ex_alu_op),
        .mem_read_out   (ex_mem_read),
        .mem_write_out  (ex_mem_write),
        .result_src_out (ex_result_src),
        .branch_out     (ex_branch),
        .jump_out       (ex_jump),
        .is_jalr_out    (ex_is_jalr),
        .csr_op_out      (ex_csr_op),
        .csr_use_imm_out (ex_csr_use_imm),
        .ecall_out       (ex_ecall),
        .ebreak_out      (ex_ebreak),
        .mret_out        (ex_mret),
        .illegal_out     (ex_illegal)
    );

endmodule
