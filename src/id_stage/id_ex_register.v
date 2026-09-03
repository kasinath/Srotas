// ============================================================================
// Module: id_ex_register
// File: id_ex_register.v
// Pipeline register: ID -> EX
//
// flush inserts a bubble by zeroing every control signal (reg_write,
// mem_read, mem_write, branch, jump, csr_op) while leaving data fields
// alone - a zeroed-control instruction is architecturally a NOP regardless
// of what data bits happen to still be sitting in the register.
// flush is used both for a load-use stall bubble and for squashing the
// ID-stage instruction on a branch/jump misprediction.
//
// csr_op is zeroed on flush alongside mem_read/mem_write/branch/jump: like
// them, it can cause an external side effect (a CSR write) once EX-stage
// execution consumes it, so a squashed instruction must not carry a live
// csr_op forward regardless of how that future consumer ends up gating the
// actual write. csr_use_imm and csr_addr are left unflushed, passing
// through every cycle like alu_src_a/alu_src_b/rd_addr - they only select
// which operand and which register csr_op would act on, and are inert
// whenever csr_op is 2'b00.
//
// ecall/ebreak/mret/illegal are zeroed on flush for the same reason as
// csr_op: each one drives a real trap or return in EX once consumed, and a
// squashed instruction (wrong-path after a branch, or a load-use bubble)
// must never be allowed to fire one.
//
// write_en is a full hold, not a flush: when low (the multi-cycle M-extension
// unit in EX is busy), every field - data AND control - keeps its current
// value, so the in-flight multiply/divide's operands and opcode stay put
// while it iterates. This is deliberately the opposite of flush, which lets
// data fields advance while zeroing control - a held instruction is still
// live, not a bubble. is_muldiv is zeroed on flush alongside reg_write/
// mem_read/mem_write/csr_op: it triggers a real EX-stage side effect (a
// multi-cycle unit starting), so a squashed instruction must never carry a
// live is_muldiv forward, exactly like csr_op above. flush and write_en=0
// never coexist by construction: the only way id_ex_flush ever fires is a
// load-use hazard or a redirect, both of which require the EX-stage
// instruction (the one write_en would be holding) to NOT be a muldiv
// (mem_read=0, no branch/trap paths reachable from is_muldiv) - see
// hazard_detection.v.
//
// is_amo (Phase 2, A extension) is zeroed on flush for the same reason as
// is_muldiv: it triggers a real MEM-stage side effect (a memory write
// and/or a reservation-state change in amo_unit.v) once consumed, so a
// squashed instruction must never carry it forward. amo_funct5 is left
// unflushed, passing through like funct3/csr_addr - it only selects which
// AMO operation is_amo would perform, and is inert whenever is_amo is 0.
// ============================================================================

`timescale 1ns/1ps

module id_ex_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire        write_en,

    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire [2:0]  funct3,
    input  wire [11:0] csr_addr,
    input  wire [4:0]  amo_funct5,

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
    input  wire [1:0]  csr_op,
    input  wire        csr_use_imm,
    input  wire        ecall,
    input  wire        ebreak,
    input  wire        mret,
    input  wire        illegal,
    input  wire        is_muldiv,
    input  wire        is_amo,

    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg  [2:0]  funct3_out,
    output reg  [11:0] csr_addr_out,
    output reg  [4:0]  amo_funct5_out,

    output reg         reg_write_out,
    output reg  [1:0]  alu_src_a_out,
    output reg         alu_src_b_out,
    output reg  [3:0]  alu_op_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg  [1:0]  result_src_out,
    output reg         branch_out,
    output reg         jump_out,
    output reg         is_jalr_out,
    output reg  [1:0]  csr_op_out,
    output reg         csr_use_imm_out,
    output reg         ecall_out,
    output reg         ebreak_out,
    output reg         mret_out,
    output reg         illegal_out,
    output reg         is_muldiv_out,
    output reg         is_amo_out
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
            csr_addr_out   <= 12'b0;
            amo_funct5_out <= 5'b0;
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
            csr_op_out     <= 2'b00;
            csr_use_imm_out <= 1'b0;
            ecall_out      <= 1'b0;
            ebreak_out     <= 1'b0;
            mret_out       <= 1'b0;
            illegal_out    <= 1'b0;
            is_muldiv_out  <= 1'b0;
            is_amo_out     <= 1'b0;
        end else if (!write_en) begin
            // EX is busy (multi-cycle muldiv in progress): hold everything,
            // data and control alike. See header comment.
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
            csr_addr_out   <= csr_addr;
            amo_funct5_out <= amo_funct5;
            alu_src_a_out  <= alu_src_a;
            alu_src_b_out  <= alu_src_b;
            alu_op_out     <= alu_op;
            csr_use_imm_out <= csr_use_imm;

            if (flush) begin
                reg_write_out  <= 1'b0;
                mem_read_out   <= 1'b0;
                mem_write_out  <= 1'b0;
                result_src_out <= 2'b0;
                branch_out     <= 1'b0;
                jump_out       <= 1'b0;
                is_jalr_out    <= 1'b0;
                csr_op_out     <= 2'b00;
                ecall_out      <= 1'b0;
                ebreak_out     <= 1'b0;
                mret_out       <= 1'b0;
                illegal_out    <= 1'b0;
                is_muldiv_out  <= 1'b0;
                is_amo_out     <= 1'b0;
            end else begin
                reg_write_out  <= reg_write;
                mem_read_out   <= mem_read;
                mem_write_out  <= mem_write;
                result_src_out <= result_src;
                branch_out     <= branch;
                jump_out       <= jump;
                is_jalr_out    <= is_jalr;
                csr_op_out     <= csr_op;
                ecall_out      <= ecall;
                ebreak_out     <= ebreak;
                mret_out       <= mret;
                illegal_out    <= illegal;
                is_muldiv_out  <= is_muldiv;
                is_amo_out     <= is_amo;
            end
        end
    end

endmodule
