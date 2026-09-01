// ============================================================================
// Module: tb_isa_directed
// File: tb_isa_directed.v
// Project: Srotas RISC-V Processor - directed, self-checking testbench
//
// Builds a hand-assembled RV32I program (via the encoder functions in
// rv32i_encoder.vh) directly in instruction memory, then checks every
// register write the processor commits, in order, against a queue of
// expected (rd, data) pairs built while authoring the program.
//
// Because retirement is strictly in-order and single-issue, "the next
// commit the DUT produces" must equal "the next expected entry in program
// order" if (and only if) the pipeline is fully correct - hazards resolved,
// forwarding correct, branches/jumps redirecting and squashing correctly,
// loads/stores correct. Any bug shows up as either a missing commit, an
// extra/unexpected commit (e.g. a squashed branch delay slot leaking
// through), or a value mismatch, and is reported with the offending
// register and cycle.
//
// Coverage: every R-type and I-type ALU op, LUI/AUIPC, all load/store
// widths (signed and unsigned), a store-data forwarding case, a load-use
// stall, a 3-instruction-apart register-file bypass case, all six branch
// comparisons (taken, with squash-of-two verification, plus one
// not-taken case), and a JAL/JALR subroutine call-and-return.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_isa_directed;

    `include "rv32i_encoder.vh"

    reg clk;
    reg rst_n;

    // -----------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    wire        wb_commit_valid;
    wire [4:0]  wb_commit_rd;
    wire [31:0] wb_commit_data;
    wire [31:0] if_pc_debug;

    srotas_processor #(
        .IMEM_WORDS     (512),
        .IMEM_INIT_FILE (""),   // program is injected directly below
        .DMEM_BYTES     (4096),
        .DMEM_INIT_FILE ("")
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .wb_commit_valid (wb_commit_valid),
        .wb_commit_rd    (wb_commit_rd),
        .wb_commit_data  (wb_commit_data),
        .if_pc_debug     (if_pc_debug)
    );

    // -----------------------------------------------------------------
    // Program assembly
    // -----------------------------------------------------------------
    integer idx;          // next free instruction slot (word address / 4)
    reg [31:0] prog [0:511];

    task emit;
        input [31:0] instr;
        begin
            prog[idx] = instr;
            idx = idx + 1;
        end
    endtask

    // Expected-commit queue, built in true execution order (which can
    // differ from program/array order across a taken jump).
    reg [4:0]  exp_rd   [0:255];
    reg [31:0] exp_data [0:255];
    integer    exp_count;

    task chk;
        input [4:0]  rd;
        input [31:0] data;
        begin
            exp_rd[exp_count]   = rd;
            exp_data[exp_count] = data;
            exp_count = exp_count + 1;
        end
    endtask

    integer beq_slot, bne_slot, blt_slot, bge_slot, bltu_slot, bgeu_slot;
    integer beq_target, blt_target, bge_target, bltu_target, bgeu_target;
    integer jal_slot, jalr_ret_slot, skip_slot;
    integer sub_idx, after_sub_idx;
    integer link_val, auipc_pc;
    integer loop_idx, bne_loop_slot;

    initial begin
        idx = 0;
        exp_count = 0;

        // ============================================================
        // Section A: R-type ALU + forwarding stress (0/1/2-apart deps)
        // ============================================================
        emit(I_ADDI(5, 0, 32'd7));           chk(5, 32'd7);
        emit(I_ADDI(6, 0, 32'd3));            chk(6, 32'd3);
        emit(I_ADD (7, 5, 6));                chk(7, 32'd10);
        emit(I_SUB (8, 7, 5));                chk(8, 32'd3);
        emit(I_AND (9, 5, 6));                chk(9, 32'd3);
        emit(I_OR  (10, 5, 6));               chk(10, 32'd7);
        emit(I_XOR (11, 5, 6));               chk(11, 32'd4);
        emit(I_SLL (12, 6, 6));               chk(12, 32'd24);
        emit(I_SRL (13, 12, 6));              chk(13, 32'd3);
        emit(I_ADDI(14, 0, -32'sd8));          chk(14, 32'hFFFFFFF8);
        emit(I_SRA (15, 14, 6));              chk(15, 32'hFFFFFFFF);
        emit(I_SLT (16, 14, 5));              chk(16, 32'd1);
        emit(I_SLTU(17, 14, 5));              chk(17, 32'd0);

        // ============================================================
        // Section B: I-type ALU
        // ============================================================
        emit(I_ADDI (18, 5, 32'd100));        chk(18, 32'd107);
        emit(I_SLTI (19, 5, 32'd10));          chk(19, 32'd1);
        emit(I_SLTIU(20, 5, 32'd10));          chk(20, 32'd1);
        emit(I_XORI (21, 5, 32'd15));          chk(21, 32'd8);
        emit(I_ORI  (22, 5, 32'd8));           chk(22, 32'd15);
        emit(I_ANDI (23, 5, 32'd3));           chk(23, 32'd3);
        emit(I_SLLI (24, 5, 5'd2));            chk(24, 32'd28);
        emit(I_SRLI (25, 24, 5'd2));           chk(25, 32'd7);
        emit(I_ADDI (26, 0, -32'sd32));        chk(26, 32'hFFFFFFE0);
        emit(I_SRAI (27, 26, 5'd2));           chk(27, 32'hFFFFFFF8);

        // ============================================================
        // Section C: LUI / AUIPC
        // ============================================================
        emit(I_LUI(28, 32'h00013000));        chk(28, 32'h00013000);
        auipc_pc = idx * 4;
        emit(I_AUIPC(29, 32'h00001000));      chk(29, auipc_pc + 32'h00001000);

        // ============================================================
        // Section D: Load/Store, all widths, signed/unsigned,
        //            store-data forwarding
        // ============================================================
        emit(I_ADDI(2, 0, 32'd0));            chk(2, 32'd0);            // x2 = data base = 0
        emit(I_ADDI(3, 0, -32'sd1));           chk(3, 32'hFFFFFFFF);      // x3 = 0xFFFFFFFF
        emit(I_SW  (3, 2, 32'd0));                                        // mem[0:3] = FF FF FF FF (store-fwd: x3 is 1-back)
        emit(I_LB  (4, 2, 32'd0));            chk(4, 32'hFFFFFFFF);      // signed byte  -> -1
        emit(I_LBU (30, 2, 32'd0));           chk(30, 32'd255);           // unsigned byte -> 255
        emit(I_LH  (31, 2, 32'd0));           chk(31, 32'hFFFFFFFF);     // signed half  -> -1
        emit(I_LHU (1, 2, 32'd0));            chk(1, 32'h0000FFFF);      // unsigned half -> 65535
        emit(I_LW  (8, 2, 32'd0));            chk(8, 32'hFFFFFFFF);      // word

        emit(I_ADDI(10, 0, 32'h55));          chk(10, 32'h55);
        emit(I_SB  (10, 2, 32'd4));                                       // store-fwd: x10 is 1-back
        emit(I_LBU (11, 2, 32'd4));           chk(11, 32'h55);
        emit(I_LB  (12, 2, 32'd4));           chk(12, 32'h55);           // MSB clear: no sign flip

        emit(I_ADDI(13, 0, -32'sd100));        chk(13, 32'hFFFFFF9C);
        emit(I_SH  (13, 2, 32'd8));                                       // store-fwd: x13 is 1-back
        emit(I_LH  (14, 2, 32'd8));           chk(14, 32'hFFFFFF9C);     // -100
        emit(I_LHU (15, 2, 32'd8));           chk(15, 32'h0000FF9C);     // 65436

        // ============================================================
        // Section E: Load-use hazard (must stall exactly one cycle)
        // ============================================================
        emit(I_LW (17, 2, 32'd0));            chk(17, 32'hFFFFFFFF);     // load
        emit(I_ADD(18, 17, 0));               chk(18, 32'hFFFFFFFF);     // uses it immediately

        // ============================================================
        // Section F: register-file same-cycle write-then-read bypass
        //            (producer exactly 3 instructions ahead of consumer)
        // ============================================================
        emit(I_ADDI(19, 0, 32'd42));          chk(19, 32'd42);
        emit(I_ADDI(20, 0, 32'd1));            chk(20, 32'd1);
        emit(I_ADDI(21, 0, 32'd2));            chk(21, 32'd2);
        emit(I_ADD (22, 19, 0));              chk(22, 32'd42);

        // ============================================================
        // Section G: Branches
        // ============================================================
        // G1: BEQ taken - verifies redirect + 2-instruction squash
        emit(I_ADDI(1, 0, 32'd5));            chk(1, 32'd5);
        emit(I_ADDI(2, 0, 32'd5));            chk(2, 32'd5);
        beq_slot = idx; emit(32'h0); // placeholder, patched below
        emit(I_ADDI(3, 0, 32'd999));           // POISON - must be squashed
        emit(I_ADDI(3, 0, 32'd999));           // POISON - must be squashed
        beq_target = idx;
        emit(I_ADDI(24, 0, 32'd111));         chk(24, 32'd111);
        prog[beq_slot] = I_BEQ(1, 2, (beq_target - beq_slot) * 4);

        // G2: BNE not-taken - fall-through instructions must execute for real
        emit(I_ADDI(5, 0, 32'd8));            chk(5, 32'd8);
        emit(I_ADDI(6, 0, 32'd8));            chk(6, 32'd8);
        bne_slot = idx; emit(32'h0);
        emit(I_ADDI(7, 0, 32'd222));          chk(7, 32'd222);
        emit(I_ADDI(8, 0, 32'd333));          chk(8, 32'd333);
        prog[bne_slot] = I_BNE(5, 6, ((idx) - bne_slot) * 4); // valid target, irrelevant (not taken)

        // G3: BLT taken (signed -5 < 3)
        emit(I_ADDI(1, 0, -32'sd5));           chk(1, 32'hFFFFFFFB);
        emit(I_ADDI(2, 0, 32'd3));            chk(2, 32'd3);
        blt_slot = idx; emit(32'h0);
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        blt_target = idx;
        emit(I_ADDI(9, 0, 32'd44));            chk(9, 32'd44);
        prog[blt_slot] = I_BLT(1, 2, (blt_target - blt_slot) * 4);

        // G4: BGE taken (3 >= -5 signed)
        bge_slot = idx; emit(32'h0);
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        bge_target = idx;
        emit(I_ADDI(10, 0, 32'd55));           chk(10, 32'd55);
        prog[bge_slot] = I_BGE(2, 1, (bge_target - bge_slot) * 4);

        // G5: BLTU taken (2 < 9 unsigned)
        emit(I_ADDI(1, 0, 32'd2));            chk(1, 32'd2);
        emit(I_ADDI(2, 0, 32'd9));            chk(2, 32'd9);
        bltu_slot = idx; emit(32'h0);
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        bltu_target = idx;
        emit(I_ADDI(13, 0, 32'd66));           chk(13, 32'd66);
        prog[bltu_slot] = I_BLTU(1, 2, (bltu_target - bltu_slot) * 4);

        // G6: BGEU taken (9 >= 2 unsigned)
        bgeu_slot = idx; emit(32'h0);
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        emit(I_ADDI(3, 0, 32'd999));           // POISON
        bgeu_target = idx;
        emit(I_ADDI(14, 0, 32'd77));           chk(14, 32'd77);
        prog[bgeu_slot] = I_BGEU(2, 1, (bgeu_target - bgeu_slot) * 4);

        // ============================================================
        // Section H: JAL / JALR subroutine call and return
        // ============================================================
        jal_slot = idx;
        link_val = idx * 4 + 4;
        emit(32'h0); // placeholder for JAL, patched once sub_idx is known
        emit(I_ADDI(16, 0, 32'd77));          // resumes here after the call returns
        skip_slot = idx;
        emit(32'h0); // placeholder for the "skip over subroutine body" JAL
        sub_idx = idx;
        emit(I_ADDI(17, 0, 32'd55));          // subroutine body marker
        emit(I_JALR(0, 15, 32'd0));            // return to x15
        after_sub_idx = idx;
        emit(I_ADDI(18, 0, 32'd199));

        prog[jal_slot]  = I_JAL(15, (sub_idx - jal_slot) * 4);
        prog[skip_slot] = I_JAL(0,  (after_sub_idx - skip_slot) * 4);

        // Execution order differs from array order here: JAL -> subroutine
        // -> JALR return -> resume instruction -> skip jump -> after label.
        chk(15, link_val);      // jal writes the return address
        chk(17, 32'd55);        // subroutine body ran
        chk(16, 32'd77);        // resumed correctly after jalr
        chk(18, 32'd199);       // fell through past the subroutine body once

        // ============================================================
        // Section I: forwarding-priority stress - a self-referential
        // accumulator where every instruction is 1-apart from itself, so
        // an EX/MEM candidate and a MEM/WB candidate both exist for the
        // same register every cycle. The closer (EX/MEM) source must win,
        // or the result silently diverges from the doubling pattern.
        // ============================================================
        emit(I_ADDI(20, 0, 32'd1));           chk(20, 32'd1);
        emit(I_ADD (20, 20, 20));             chk(20, 32'd2);
        emit(I_ADD (20, 20, 20));             chk(20, 32'd4);
        emit(I_ADD (20, 20, 20));             chk(20, 32'd8);
        emit(I_ADD (20, 20, 20));             chk(20, 32'd16);
        emit(I_ADD (20, 20, 20));             chk(20, 32'd32);

        // ============================================================
        // Section J: backward branch (a real loop) - sum 1..10.
        // Every earlier branch test redirects forward; this is the only
        // check that a *backward* redirect (the common loop case) also
        // works correctly across multiple taken iterations in a row.
        // ============================================================
        emit(I_ADDI(5, 0, 32'd0));            chk(5, 32'd0);   // sum = 0
        emit(I_ADDI(6, 0, 32'd1));            chk(6, 32'd1);   // i = 1
        emit(I_ADDI(7, 0, 32'd11));           chk(7, 32'd11);  // limit = 11
        loop_idx = idx;
        emit(I_ADD (5, 5, 6));                                 // sum += i  (checked below)
        emit(I_ADDI(6, 6, 32'd1));                              // i += 1    (checked below)
        bne_loop_slot = idx; emit(32'h0);
        prog[bne_loop_slot] = I_BNE(6, 7, (loop_idx - bne_loop_slot) * 4);

        begin : loop_expect
            integer li, sum_acc;
            sum_acc = 0;
            for (li = 1; li <= 10; li = li + 1) begin
                sum_acc = sum_acc + li;
                chk(5, sum_acc);
                chk(6, li + 1);
            end
        end

        emit(I_ADDI(2, 0, 32'd0));            chk(2, 32'd0);
        emit(I_SW  (5, 2, 32'd0));                                // store sum to mem[0]
        emit(I_LW  (9, 2, 32'd0));            chk(9, 32'd55);     // read it back

        // ============================================================
        // Halt: spin on self forever so nothing further ever commits
        // ============================================================
        emit(I_JAL(0, 32'd0));

        // Copy the assembled program into instruction memory.
        begin : load_program
            integer i;
            for (i = 0; i < idx; i = i + 1)
                dut.u_if_stage.u_instruction_memory.mem[i] = prog[i];
        end
    end

    // -----------------------------------------------------------------
    // Scoreboard: compare every commit against the expected queue
    // -----------------------------------------------------------------
    integer check_ptr;
    integer errors;
    integer commits_seen;

    initial begin
        check_ptr    = 0;
        errors       = 0;
        commits_seen = 0;
    end

    always @(posedge clk) begin
        if (rst_n && wb_commit_valid) begin
            commits_seen = commits_seen + 1;
            if (check_ptr >= exp_count) begin
                $display("[%0t] FAIL: unexpected extra commit x%0d = 0x%08h (queue exhausted)",
                          $time, wb_commit_rd, wb_commit_data);
                errors = errors + 1;
            end else begin
                if ((wb_commit_rd !== exp_rd[check_ptr]) || (wb_commit_data !== exp_data[check_ptr])) begin
                    $display("[%0t] FAIL: commit #%0d got x%0d=0x%08h, expected x%0d=0x%08h",
                              $time, check_ptr, wb_commit_rd, wb_commit_data,
                              exp_rd[check_ptr], exp_data[check_ptr]);
                    errors = errors + 1;
                end else begin
                    $display("[%0t] pass: x%0d = 0x%08h", $time, wb_commit_rd, wb_commit_data);
                end
                check_ptr = check_ptr + 1;
            end
        end
    end

    // -----------------------------------------------------------------
    // Reset and run
    // -----------------------------------------------------------------
    initial begin
        rst_n = 0;
        #12 rst_n = 1;

        // Enough cycles for ~130 instructions plus stalls/bubbles.
        #6000;

        $display("");
        $display("========================================");
        if (check_ptr < exp_count) begin
            $display("FAIL: only %0d of %0d expected commits were observed", check_ptr, exp_count);
            errors = errors + 1;
        end
        if (errors == 0) begin
            $display("RESULT: ALL %0d CHECKS PASSED", exp_count);
        end else begin
            $display("RESULT: %0d ERROR(S) - SEE LOG ABOVE", errors);
        end
        $display("========================================");
        $finish;
    end

endmodule
