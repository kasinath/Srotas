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
// the self-checking testbenches in src/testbenches use. trap_* mirrors
// that for trap events (which never produce a wb_commit, since a
// trapping instruction's reg_write is always suppressed - see
// ex_stage_top.v), and wb_commit_pc gives the PC of the retiring
// instruction, derived from memwb_pc_plus4 rather than threaded as a new
// pipeline field. Both exist for tools/golden_model.py's lockstep
// comparison (docs/roadmap.md, Phase 1) as well as ad hoc debugging.
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
    output wire [31:0] wb_commit_pc,
    output wire [31:0] if_pc_debug,

    // Debug / trap-monitor outputs. Resolved combinationally in EX (that
    // timing drives the real redirect/squash), but reported here two
    // cycles later - deliberately delayed to align with wb_commit_*'s
    // WB-stage timing, so an external trace sees trap and commit events
    // in true program order (see the delay register near their assign
    // statements below for why that alignment matters).
    output wire        trap_valid,
    output wire [31:0] trap_pc,
    output wire [31:0] trap_cause,
    output wire [31:0] trap_mtval
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
    wire [1:0]  ex_csr_op;
    wire        ex_csr_use_imm;
    wire [11:0] ex_csr_addr;
    wire        ex_ecall, ex_ebreak, ex_mret, ex_illegal;

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
        .ex_is_jalr    (ex_is_jalr),
        .ex_csr_op      (ex_csr_op),
        .ex_csr_use_imm (ex_csr_use_imm),
        .ex_csr_addr    (ex_csr_addr),
        .ex_ecall       (ex_ecall),
        .ex_ebreak      (ex_ebreak),
        .ex_mret        (ex_mret),
        .ex_illegal     (ex_illegal)
    );

    // -------------------------------------------------------------------
    // EX stage
    // -------------------------------------------------------------------
    wire [1:0] forward_a, forward_b;
    wire [31:0] fwd_exmem_data, fwd_memwb_data;

    wire        ex_trap_valid;
    wire [31:0] ex_trap_cause, ex_trap_value;

    wire [31:0] mem_pc_plus4, mem_alu_result, mem_write_data;
    wire [4:0]  mem_rd_addr;
    wire [2:0]  mem_funct3;
    wire        mem_reg_write, mem_mem_read, mem_mem_write;
    wire [1:0]  mem_result_src;
    wire [31:0] mem_csr_rdata;

    ex_stage_top u_ex_stage (
        .clk       (clk),
        .rst_n     (rst_n),

        .pc        (ex_pc),
        .pc_plus4  (ex_pc_plus4),
        .rs1_data  (ex_rs1_data),
        .rs2_data  (ex_rs2_data),
        .imm       (ex_imm),
        .rd_addr   (ex_rd_addr),
        .rs1_addr  (ex_rs1_addr),
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
        .csr_op      (ex_csr_op),
        .csr_use_imm (ex_csr_use_imm),
        .csr_addr    (ex_csr_addr),
        .ecall       (ex_ecall),
        .ebreak      (ex_ebreak),
        .mret        (ex_mret),
        .illegal     (ex_illegal),

        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .fwd_exmem_data (fwd_exmem_data),
        .fwd_memwb_data (fwd_memwb_data),

        .redirect        (ex_redirect),
        .redirect_target (ex_redirect_target),

        .trap_debug_valid (ex_trap_valid),
        .trap_debug_cause (ex_trap_cause),
        .trap_debug_value (ex_trap_value),

        .mem_pc_plus4    (mem_pc_plus4),
        .mem_alu_result  (mem_alu_result),
        .mem_write_data  (mem_write_data),
        .mem_rd_addr     (mem_rd_addr),
        .mem_funct3      (mem_funct3),
        .mem_reg_write   (mem_reg_write),
        .mem_mem_read    (mem_mem_read),
        .mem_mem_write   (mem_mem_write),
        .mem_result_src  (mem_result_src),
        .mem_csr_rdata   (mem_csr_rdata)
    );

    // Best-available forwarded value from the instruction currently one
    // stage ahead (in MEM): its ALU result, its link value if it was a
    // JAL/JALR, or its CSR read value if it was a CSR instruction (the
    // ALU's own result is meaningless for both of those cases - see
    // ex_stage_top.v). Load results are never forwarded from here - the
    // load-use stall guarantees a producing load is never the EX/MEM
    // forward source.
    assign fwd_exmem_data = (mem_result_src == `RESULT_LINK) ? mem_pc_plus4 :
                             (mem_result_src == `RESULT_CSR)  ? mem_csr_rdata :
                                                                 mem_alu_result;
    assign fwd_memwb_data = final_wb_rd_data;

    // Debug-only alignment: trap_debug_* resolves in EX, two stages
    // earlier than wb_commit_* (WB). Left undelayed, an instruction's
    // trap could appear in an external trace *before* an earlier
    // instruction's commit, purely because EX is observed two cycles
    // sooner than WB - not a real reordering, just two debug taps at
    // different pipeline depths. This shift register delays the trap
    // debug outputs by the same two stages so both ports report events
    // in true program order, matching how tools/golden_model.py's
    // lockstep trace has no pipeline depth of its own to get out of sync
    // with. It has no effect on the real redirect/squash path (Section 5
    // of docs/processor_guide.md), which still fires the same cycle
    // trap_debug_valid does - only these external-observation copies are
    // delayed.
    reg        trap_valid_d1, trap_valid_d2;
    reg [31:0] trap_pc_d1, trap_pc_d2, trap_cause_d1, trap_cause_d2, trap_value_d1, trap_value_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trap_valid_d1 <= 1'b0; trap_valid_d2 <= 1'b0;
            trap_pc_d1    <= 32'b0; trap_pc_d2    <= 32'b0;
            trap_cause_d1 <= 32'b0; trap_cause_d2 <= 32'b0;
            trap_value_d1 <= 32'b0; trap_value_d2 <= 32'b0;
        end else begin
            trap_valid_d1 <= ex_trap_valid;
            trap_pc_d1    <= ex_pc;
            trap_cause_d1 <= ex_trap_cause;
            trap_value_d1 <= ex_trap_value;

            trap_valid_d2 <= trap_valid_d1;
            trap_pc_d2    <= trap_pc_d1;
            trap_cause_d2 <= trap_cause_d1;
            trap_value_d2 <= trap_value_d1;
        end
    end

    assign trap_valid = trap_valid_d2;
    assign trap_pc    = trap_pc_d2;
    assign trap_cause = trap_cause_d2;
    assign trap_mtval = trap_value_d2;

    // -------------------------------------------------------------------
    // MEM stage
    // -------------------------------------------------------------------
    wire [31:0] memwb_pc_plus4, memwb_alu_result, memwb_mem_read_data;
    wire [4:0]  memwb_rd_addr;
    wire        memwb_reg_write;
    wire [1:0]  memwb_result_src;
    wire [31:0] memwb_csr_rdata;

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
        .ex_csr_rdata      (mem_csr_rdata),
        .ex_reg_write      (mem_reg_write),
        .ex_mem_read       (mem_mem_read),
        .ex_mem_write      (mem_mem_write),
        .ex_result_src     (mem_result_src),

        .wb_pc_plus4      (memwb_pc_plus4),
        .wb_alu_result    (memwb_alu_result),
        .wb_mem_read_data (memwb_mem_read_data),
        .wb_rd_addr       (memwb_rd_addr),
        .wb_csr_rdata     (memwb_csr_rdata),
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
        .csr_rdata     (memwb_csr_rdata),
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
    // memwb_pc_plus4 is already threaded this far for JAL/JALR link
    // values; the retiring instruction's own PC is just that minus 4,
    // needing no new pipeline field.
    assign wb_commit_pc    = memwb_pc_plus4 - 32'd4;

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
