// ============================================================================
// Testbench: tb_control_unit_csr
// File: tb_control_unit_csr.v
//
// Directed unit test for the CSR-instruction and trap-classification
// decode paths in control_unit.v (see docs/roadmap.md, Phase 1): the six
// csrrw/csrrs/csrrc/csrrwi/csrrsi/csrrci encodings, ECALL/EBREAK/MRET
// (funct3==000, distinguished by csr_addr), WFI decoding as a NOP,
// anything else in that space (or any unrecognized opcode) setting
// illegal, and a couple of pre-existing opcodes to confirm none of this
// disturbed anything else. control_unit is purely combinational, so it's
// exercised directly rather than through a full pipeline run -
// tb_isa_directed.v's Section L is the full-pipeline trap regression.
//
// Also covers the Phase 2 M-extension decode: all eight OP_REG/
// FUNCT7_MULDIV encodings setting is_muldiv (and nothing else OP_REG
// wouldn't already set), plus the regression this closes - a muldiv
// encoding no longer silently decoding as ADD/SUB/etc. through the base
// R-type funct3 case (funct7[5], which the base ops key off of, happens to
// be 0 for FUNCT7_MULDIV too).
//
// And the Phase 2 A-extension decode: all 11 OP_AMO/funct5 encodings
// setting is_amo, mem_write correctly clear only for lr.w (the one variant
// that never writes), a non-word funct3 and an unrecognized funct5 both
// setting illegal - OP_AMO is its own opcode, not shared with any base
// R-type op, so unlike M there's no "silently decodes as something else"
// regression to guard against here, only "decodes as illegal" for the two
// malformed cases.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_control_unit_csr;

    reg  [6:0]  opcode;
    reg  [2:0]  funct3;
    reg  [6:0]  funct7;
    reg  [11:0] csr_addr;

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
    wire        is_muldiv;
    wire        is_amo;

    integer errors;
    integer checks;

    control_unit dut (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),
        .csr_addr    (csr_addr),
        .reg_write   (reg_write),
        .alu_src_a   (alu_src_a),
        .alu_src_b   (alu_src_b),
        .alu_op      (alu_op),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .result_src  (result_src),
        .branch      (branch),
        .jump        (jump),
        .is_jalr     (is_jalr),
        .imm_format  (imm_format),
        .csr_op      (csr_op),
        .csr_use_imm (csr_use_imm),
        .ecall       (ecall),
        .ebreak      (ebreak),
        .mret        (mret),
        .illegal     (illegal),
        .is_muldiv   (is_muldiv),
        .is_amo      (is_amo)
    );

    task check1;
        input actual;
        input expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[FAIL] opcode=%b funct3=%b: expected %0b, got %0b", opcode, funct3, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check2;
        input [1:0] actual;
        input [1:0] expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[FAIL] opcode=%b funct3=%b: expected %02b, got %02b", opcode, funct3, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check4;
        input [3:0] actual;
        input [3:0] expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("[FAIL] opcode=%b funct3=%b: expected %04b, got %04b", opcode, funct3, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    // Applies one CSR-instruction funct3 and checks the full expected
    // control-signal bundle in one place.
    task check_csr;
        input [2:0] f3;
        begin
            opcode = `OP_SYSTEM; funct3 = f3; funct7 = 7'b0; csr_addr = `CSR_MSCRATCH;
            #1;
            check1(reg_write, 1'b1);
            check2(result_src, `RESULT_CSR);
            check2(csr_op, f3[1:0]);
            check1(csr_use_imm, f3[2]);
            // A CSR instruction must never assert any of these.
            check1(mem_read, 1'b0);
            check1(mem_write, 1'b0);
            check1(branch, 1'b0);
            check1(jump, 1'b0);
            check1(ecall, 1'b0);
            check1(ebreak, 1'b0);
            check1(mret, 1'b0);
            check1(illegal, 1'b0);
        end
    endtask

    // Applies one funct3==000 OP_SYSTEM csr_addr value and checks which
    // single one of ecall/ebreak/mret/illegal (if any) it sets, plus that
    // reg_write never fires for any of them.
    task check_sys;
        input [11:0] addr;
        input        exp_ecall;
        input        exp_ebreak;
        input        exp_mret;
        input        exp_illegal;
        begin
            opcode = `OP_SYSTEM; funct3 = 3'b000; funct7 = 7'b0; csr_addr = addr;
            #1;
            check1(ecall,   exp_ecall);
            check1(ebreak,  exp_ebreak);
            check1(mret,    exp_mret);
            check1(illegal, exp_illegal);
            check1(reg_write, 1'b0);
        end
    endtask

    // Applies one OP_REG/FUNCT7_MULDIV funct3 and checks is_muldiv fires
    // with nothing else OP_REG wouldn't already set.
    task check_muldiv;
        input [2:0] f3;
        begin
            opcode = `OP_REG; funct3 = f3; funct7 = `FUNCT7_MULDIV;
            #1;
            check1(reg_write, 1'b1);
            check1(is_muldiv, 1'b1);
            check2(result_src, `RESULT_ALU);
            check1(mem_read, 1'b0);
            check1(mem_write, 1'b0);
            check1(branch, 1'b0);
            check1(jump, 1'b0);
            check1(illegal, 1'b0);
        end
    endtask

    // Applies one OP_AMO funct5 and checks the full expected bundle,
    // including mem_write's one variant-dependent bit (0 only for lr.w).
    task check_amo;
        input [4:0] f5;
        input       exp_mem_write;
        begin
            opcode = `OP_AMO; funct3 = 3'b010; funct7 = {f5, 2'b00}; // aq=rl=0
            #1;
            check1(reg_write, 1'b1);
            check1(is_amo, 1'b1);
            check2(result_src, `RESULT_MEM);
            check1(mem_read, 1'b1);
            check1(mem_write, exp_mem_write);
            check1(branch, 1'b0);
            check1(jump, 1'b0);
            check1(illegal, 1'b0);
            check1(is_muldiv, 1'b0);
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;

        // ---------------- The six CSR instruction encodings ----------------
        check_csr(3'b001); // CSRRW
        check_csr(3'b010); // CSRRS
        check_csr(3'b011); // CSRRC
        check_csr(3'b101); // CSRRWI
        check_csr(3'b110); // CSRRSI
        check_csr(3'b111); // CSRRCI

        // ---------------- funct3 == 000: ECALL/EBREAK/MRET/WFI/illegal ----------------
        check_sys(`SYS_IMM_ECALL,  1'b1, 1'b0, 1'b0, 1'b0);
        check_sys(`SYS_IMM_EBREAK, 1'b0, 1'b1, 1'b0, 1'b0);
        check_sys(`SYS_IMM_MRET,   1'b0, 1'b0, 1'b1, 1'b0);
        check_sys(`SYS_IMM_WFI,    1'b0, 1'b0, 1'b0, 1'b0); // legal NOP, not illegal
        check_sys(12'h123,         1'b0, 1'b0, 1'b0, 1'b1); // unrecognized (e.g. sfence.vma-shaped)

        // ---------------- Regression: unrecognized opcode is illegal ----------------
        opcode = 7'b0000000; funct3 = 3'b000; funct7 = 7'b0;
        #1;
        check1(illegal, 1'b1);
        check1(reg_write, 1'b0);

        // ---------------- M extension: all eight OP_REG/FUNCT7_MULDIV encodings ----------------
        check_muldiv(`FUNCT3_MUL);
        check_muldiv(`FUNCT3_MULH);
        check_muldiv(`FUNCT3_MULHSU);
        check_muldiv(`FUNCT3_MULHU);
        check_muldiv(`FUNCT3_DIV);
        check_muldiv(`FUNCT3_DIVU);
        check_muldiv(`FUNCT3_REM);
        check_muldiv(`FUNCT3_REMU);

        // ---------------- Regression: pre-existing opcodes unaffected ----------------
        opcode = `OP_REG; funct3 = 3'b000; funct7 = 7'b0; // ADD
        #1;
        check1(reg_write, 1'b1);
        check4(alu_op, `ALU_ADD);
        check2(result_src, `RESULT_ALU);
        check2(csr_op, 2'b00);
        check1(illegal, 1'b0);
        check1(is_muldiv, 1'b0);

        opcode = `OP_REG; funct3 = 3'b000; funct7 = 7'b0100000; // SUB
        #1;
        check4(alu_op, `ALU_SUB);
        check1(is_muldiv, 1'b0);

        opcode = `OP_REG; funct3 = 3'b101; funct7 = 7'b0100000; // SRA
        #1;
        check4(alu_op, `ALU_SRA);
        check1(is_muldiv, 1'b0);

        opcode = `OP_LOAD; funct3 = `FUNCT3_LW; funct7 = 7'b0; // LW
        #1;
        check1(reg_write, 1'b1);
        check1(mem_read, 1'b1);
        check2(result_src, `RESULT_MEM);

        opcode = `OP_BRANCH; funct3 = `FUNCT3_BEQ; funct7 = 7'b0; // BEQ
        #1;
        check1(branch, 1'b1);
        check1(reg_write, 1'b0);
        check4(alu_op, `ALU_SUB);

        // ---------------- A extension: all 11 OP_AMO/funct5 encodings ----------------
        check_amo(`AMO_F5_LR,    1'b0);  // the one variant that never writes
        check_amo(`AMO_F5_SC,    1'b1);
        check_amo(`AMO_F5_SWAP,  1'b1);
        check_amo(`AMO_F5_ADD,   1'b1);
        check_amo(`AMO_F5_XOR,   1'b1);
        check_amo(`AMO_F5_AND,   1'b1);
        check_amo(`AMO_F5_OR,    1'b1);
        check_amo(`AMO_F5_MIN,   1'b1);
        check_amo(`AMO_F5_MAX,   1'b1);
        check_amo(`AMO_F5_MINU,  1'b1);
        check_amo(`AMO_F5_MAXU,  1'b1);

        // ---------------- A extension: malformed encodings trap illegal ----------------
        opcode = `OP_AMO; funct3 = 3'b011; funct7 = {`AMO_F5_ADD, 2'b00}; // doubleword: RV64A-only
        #1;
        check1(illegal, 1'b1);
        check1(is_amo, 1'b0);
        check1(reg_write, 1'b0);

        opcode = `OP_AMO; funct3 = 3'b010; funct7 = {5'b11111, 2'b00}; // unrecognized funct5
        #1;
        check1(illegal, 1'b1);
        check1(is_amo, 1'b0);

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
