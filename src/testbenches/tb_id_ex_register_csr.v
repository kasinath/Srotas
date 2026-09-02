// ============================================================================
// Testbench: tb_id_ex_register_csr
// File: tb_id_ex_register_csr.v
//
// Directed unit test for the csr_op/csr_use_imm/csr_addr and
// ecall/ebreak/mret/illegal fields added to id_ex_register.v (see
// docs/roadmap.md, Phase 1): normal passthrough on a clean cycle,
// csr_op/ecall/ebreak/mret/illegal all being zeroed on flush (grouped
// with reg_write/mem_read/mem_write/branch/jump - all the "can cause an
// external side effect" signals), and csr_use_imm/csr_addr passing
// through unflushed (grouped with alu_src_a/alu_src_b/rd_addr - bystander
// fields, inert whenever csr_op is 2'b00). Other fields are driven with
// representative values only to exercise the register; tb_isa_directed.v's
// regression already covers this module's pre-existing flush/stall
// behavior end to end.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_id_ex_register_csr;

    reg clk = 0;
    reg rst_n;
    reg flush;

    reg [1:0]  csr_op;
    reg        csr_use_imm;
    reg [11:0] csr_addr;
    reg        reg_write, mem_read, mem_write, branch, jump, is_jalr;
    reg        ecall, ebreak, mret, illegal;

    wire [1:0]  csr_op_out;
    wire        csr_use_imm_out;
    wire [11:0] csr_addr_out;
    wire        reg_write_out, mem_read_out, mem_write_out, branch_out, jump_out, is_jalr_out;
    wire        ecall_out, ebreak_out, mret_out, illegal_out;

    integer errors;
    integer checks;

    id_ex_register dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),

        .pc        (32'b0),
        .pc_plus4  (32'b0),
        .rs1_addr  (5'b0),
        .rs2_addr  (5'b0),
        .rd_addr   (5'b0),
        .rs1_data  (32'b0),
        .rs2_data  (32'b0),
        .imm       (32'b0),
        .funct3    (3'b0),
        .csr_addr  (csr_addr),

        .reg_write  (reg_write),
        .alu_src_a  (2'b0),
        .alu_src_b  (1'b0),
        .alu_op     (4'b0),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .result_src (2'b0),
        .branch     (branch),
        .jump       (jump),
        .is_jalr    (is_jalr),
        .csr_op      (csr_op),
        .csr_use_imm (csr_use_imm),
        .ecall       (ecall),
        .ebreak      (ebreak),
        .mret        (mret),
        .illegal     (illegal),

        .pc_out         (),
        .pc_plus4_out   (),
        .rs1_addr_out   (),
        .rs2_addr_out   (),
        .rd_addr_out    (),
        .rs1_data_out   (),
        .rs2_data_out   (),
        .imm_out        (),
        .funct3_out     (),
        .csr_addr_out   (csr_addr_out),

        .reg_write_out  (reg_write_out),
        .alu_src_a_out  (),
        .alu_src_b_out  (),
        .alu_op_out     (),
        .mem_read_out   (mem_read_out),
        .mem_write_out  (mem_write_out),
        .result_src_out (),
        .branch_out     (branch_out),
        .jump_out       (jump_out),
        .is_jalr_out    (is_jalr_out),
        .csr_op_out      (csr_op_out),
        .csr_use_imm_out (csr_use_imm_out),
        .ecall_out       (ecall_out),
        .ebreak_out      (ebreak_out),
        .mret_out        (mret_out),
        .illegal_out     (illegal_out)
    );

    always #5 clk = ~clk;

    task check2;
        input [1:0] actual;
        input [1:0] expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[%0t] FAIL: expected %02b, got %02b", $time, expected, actual);
                errors = errors + 1;
            end else begin
                $display("[%0t] pass: %02b", $time, actual);
            end
        end
    endtask

    task check1;
        input actual;
        input expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[%0t] FAIL: expected %0b, got %0b", $time, expected, actual);
                errors = errors + 1;
            end else begin
                $display("[%0t] pass: %0b", $time, actual);
            end
        end
    endtask

    task check12;
        input [11:0] actual;
        input [11:0] expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[%0t] FAIL: expected 0x%03h, got 0x%03h", $time, expected, actual);
                errors = errors + 1;
            end else begin
                $display("[%0t] pass: 0x%03h", $time, actual);
            end
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        rst_n = 0; flush = 0;
        csr_op = 2'b00; csr_use_imm = 1'b0; csr_addr = 12'b0;
        reg_write = 1'b0; mem_read = 1'b0; mem_write = 1'b0; branch = 1'b0; jump = 1'b0; is_jalr = 1'b0;
        ecall = 1'b0; ebreak = 1'b0; mret = 1'b0; illegal = 1'b0;
        @(negedge clk);
        rst_n = 1'b1;

        // ---------------- Reset state ----------------
        check2(csr_op_out, 2'b00);
        check1(csr_use_imm_out, 1'b0);
        check12(csr_addr_out, 12'b0);
        check1(ecall_out, 1'b0);
        check1(ebreak_out, 1'b0);
        check1(mret_out, 1'b0);
        check1(illegal_out, 1'b0);

        // ---------------- Normal passthrough (no flush) ----------------
        csr_op = `CSR_OP_RS; csr_use_imm = 1'b1; csr_addr = `CSR_MSTATUS;
        reg_write = 1'b1;
        @(negedge clk);
        check2(csr_op_out, `CSR_OP_RS);
        check1(csr_use_imm_out, 1'b1);
        check12(csr_addr_out, `CSR_MSTATUS);
        check1(reg_write_out, 1'b1);

        // A different op/imm/address combination, still no flush.
        csr_op = `CSR_OP_RC; csr_use_imm = 1'b0; csr_addr = `CSR_MEPC;
        @(negedge clk);
        check2(csr_op_out, `CSR_OP_RC);
        check1(csr_use_imm_out, 1'b0);
        check12(csr_addr_out, `CSR_MEPC);

        // ecall/ebreak/mret/illegal passthrough, no flush (one at a time,
        // matching how control_unit.v only ever asserts one of these per
        // instruction).
        csr_op = 2'b00;
        ecall = 1'b1;
        @(negedge clk);
        check1(ecall_out, 1'b1);
        ecall = 1'b0; illegal = 1'b1;
        @(negedge clk);
        check1(ecall_out, 1'b0);
        check1(illegal_out, 1'b1);
        illegal = 1'b0;

        // ---------------- Flush: csr_op/ecall/ebreak/mret/illegal zeroed, csr_use_imm/csr_addr pass through ----------------
        csr_op = `CSR_OP_RW; csr_use_imm = 1'b1; csr_addr = `CSR_MCAUSE;
        reg_write = 1'b1; mem_read = 1'b1; mem_write = 1'b1; branch = 1'b1; jump = 1'b1; is_jalr = 1'b1;
        ecall = 1'b1; ebreak = 1'b1; mret = 1'b1; illegal = 1'b1;
        flush = 1'b1;
        @(negedge clk);
        flush = 1'b0;
        ecall = 1'b0; ebreak = 1'b0; mret = 1'b0; illegal = 1'b0;
        check2(csr_op_out, 2'b00);          // zeroed like the other side-effect signals
        check1(csr_use_imm_out, 1'b1);      // NOT zeroed - passes through like alu_src_a/alu_src_b
        check12(csr_addr_out, `CSR_MCAUSE); // NOT zeroed - passes through like rd_addr
        check1(reg_write_out, 1'b0);
        check1(mem_read_out, 1'b0);
        check1(mem_write_out, 1'b0);
        check1(branch_out, 1'b0);
        check1(jump_out, 1'b0);
        check1(is_jalr_out, 1'b0);
        check1(ecall_out, 1'b0);
        check1(ebreak_out, 1'b0);
        check1(mret_out, 1'b0);
        check1(illegal_out, 1'b0);

        // ---------------- Post-flush cycle: normal passthrough resumes ----------------
        csr_op = `CSR_OP_RW; reg_write = 1'b1;
        @(negedge clk);
        check2(csr_op_out, `CSR_OP_RW);
        check1(reg_write_out, 1'b1);

        $display("");
        $display("========================================");
        if (errors == 0) begin
            $display("RESULT: ALL %0d CHECKS PASSED", checks);
        end else begin
            $display("RESULT: %0d ERROR(S) - SEE LOG ABOVE", errors);
        end
        $display("========================================");
        $finish;
    end

endmodule
