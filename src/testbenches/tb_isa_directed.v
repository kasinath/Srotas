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
// not-taken case), a JAL/JALR subroutine call-and-return, all six Zicsr
// CSR instructions (including a CSR-produced value forwarded via EX/MEM
// to the very next instruction), all five M-mode trap causes with a
// clean MRET return, FENCE/FENCE.I (Zifencei), the M extension's
// pipeline interactions - operand forwarding into and out of a held
// multi-cycle muldiv, back-to-back muldiv instructions, a load-use hazard
// immediately adjacent to one, and a branch/trap immediately after one
// ends - and the A extension's pipeline interactions - a back-to-back
// lr.w/sc.w lock-acquire, sc.w failing after an intervening store
// invalidates its reservation, an AMO's operand forwarded in and its
// result consumed via a load-use stall, and misaligned lr.w/AMO traps
// that leave no reservation armed.
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
    wire [31:0] wb_commit_pc;
    wire [31:0] if_pc_debug;
    wire        trap_valid;
    wire [31:0] trap_pc;
    wire [31:0] trap_cause;
    wire [31:0] trap_mtval;

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
        .wb_commit_pc    (wb_commit_pc),
        .if_pc_debug     (if_pc_debug),
        .trap_valid      (trap_valid),
        .trap_pc         (trap_pc),
        .trap_cause      (trap_cause),
        .trap_mtval      (trap_mtval)
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
        // Section K: CSR instructions (Zicsr), against mscratch (a plain
        // read/write CSR with no masking, so results are simple to hand-
        // verify). Covers all six encodings, a back-to-back same-address
        // CSR access (proving no special forwarding is needed between two
        // CSR instructions - csr_file.v's write commits one cycle before a
        // following instruction reads it, exactly the natural EX-stage
        // spacing), a GPR value forwarded INTO a CSR write operand, and -
        // the case that would silently break without the EX/MEM forward
        // mux's RESULT_CSR arm in srotas_processor.v - a CSR-produced
        // value forwarded OUT to the very next instruction.
        // ============================================================
        emit(I_CSRRWI(25, 5'd5,  `CSR_MSCRATCH));  chk(25, 32'd0);   // old=0, mscratch<=5
        emit(I_CSRRS (26, 0,     `CSR_MSCRATCH));  chk(26, 32'd5);   // pure read (rs1=x0): old=5, unchanged
        emit(I_ADDI  (27, 0, 32'h55));              chk(27, 32'h55);
        emit(I_CSRRW (28, 27,    `CSR_MSCRATCH));  chk(28, 32'd5);   // rs1 forwarded from prior ADDI; old=5, mscratch<=0x55
        emit(I_ADD   (29, 28, 0));                  chk(29, 32'd5);   // x28 (a CSR result) forwarded EX/MEM -> EX
        emit(I_CSRRC (30, 27,    `CSR_MSCRATCH));  chk(30, 32'h55);  // old=0x55, mscratch <= 0x55 & ~0x55 = 0
        emit(I_CSRRSI(31, 5'd31, `CSR_MSCRATCH));  chk(31, 32'd0);   // old=0, mscratch <= 0x1F
        emit(I_CSRRCI(24, 5'd31, `CSR_MSCRATCH));  chk(24, 32'd31);  // old=0x1F, mscratch <= 0

        // ============================================================
        // Section L: traps. One handler (placed inline, skipped over
        // during normal flow by an unconditional JAL) is reused for five
        // separate exception triggers - ECALL, EBREAK, an illegal
        // instruction, a misaligned load, and a misaligned store - each
        // proving the trap controller captures the right mepc/mcause/
        // mtval, and each returning via MRET to mepc+4 (the standard
        // "skip past the faulting instruction" epilogue) to prove the
        // pipeline resumes cleanly afterward. The final LW checks that
        // the misaligned store's write was actually suppressed, not just
        // that its GPR write was (stores have no register result to
        // catch a suppression bug the way a load's would).
        // ============================================================
        begin : trap_section
            // RV32I register fields are 5 bits (x0-x31 only); every
            // register used below is chosen to avoid colliding with any
            // register still live at this point - x2 is the sole
            // exception, and Section L never writes it, only reads it
            // (Section J left it at 0) in the final corruption check.
            integer skip_slot, handler_idx;
            integer ecall_idx, ebreak_idx, illegal_idx, lh_idx, sw_idx;
            integer ecall_pc, ebreak_pc, illegal_pc, lh_pc, sw_pc;
            integer handler_byte_addr;

            skip_slot = idx; emit(32'h0);           // JAL x0, SKIP_HANDLER (patched below)

            handler_idx = idx;
            emit(I_CSRRS (1, 0, `CSR_MEPC));        // read mepc
            emit(I_CSRRS (3, 0, `CSR_MCAUSE));      // read mcause
            emit(I_CSRRS (4, 0, `CSR_MTVAL));       // read mtval
            emit(I_ADDI  (1, 1, 32'd4));             // mepc + 4 (skip past the faulting instruction)
            emit(I_CSRRW (0, 1, `CSR_MEPC));        // mepc <= mepc + 4
            emit(`I_MRET);

            prog[skip_slot] = I_JAL(0, (idx - skip_slot) * 4);  // SKIP_HANDLER starts here
            handler_byte_addr = handler_idx * 4;

            emit(I_ADDI (6, 0, handler_byte_addr));   // handler address (fits in 12 bits: small program)
            emit(I_CSRRW(7, 6, `CSR_MTVEC));         // set mtvec; capture old value (0)

            // Prime mem[4] with a known, all-bytes-nonzero sentinel so the
            // later misaligned-store check (below) compares against a
            // real prior value instead of assuming untouched memory reads
            // as zero - it doesn't in every simulator (Vivado's xsim
            // leaves genuinely virgin memory as X, not 0).
            emit(I_LUI (9, 32'hCAFEF000));
            emit(I_ADDI(9, 9, 32'd13));                // x9 = 0xCAFEF00D
            emit(I_SW  (9, 2, 32'd4));                 // mem[4] <- 0xCAFEF00D

            ecall_idx = idx;   emit(`I_ECALL);
            ebreak_idx = idx;  emit(`I_EBREAK);
            illegal_idx = idx; emit(32'hFFFFFFFF);   // opcode=1111111: unrecognized by any OP_* case

            emit(I_ADDI(14, 0, 32'd1));               // odd address: word- and half-misaligned
            lh_idx = idx; emit(I_LH(15, 14, 32'd0));

            emit(I_ADDI(16, 0, 32'd2));               // half-aligned but word-misaligned address
            // Every byte of this value is nonzero, so if the misaligned
            // store's suppression ever failed, the corrupted bytes at
            // address 4 (checked below) would be visibly nonzero too -
            // a value like 0x00001234 would hide that exact bug, since
            // its upper two bytes are already zero.
            emit(I_LUI (17, 32'hDEADC000));
            emit(I_ADDI(17, 17, -32'sd273));           // x17 = 0xDEADBEEF (0xDEADC000 + (-0x111))
            sw_idx = idx; emit(I_SW(17, 16, 32'd0));

            emit(I_ADDI(19, 0, 32'd777));             // proves execution resumed correctly
            emit(I_LW  (20, 2, 32'd4));                // x2==0 (Section J); mem[4] must still hold the sentinel

            ecall_pc   = ecall_idx * 4;
            ebreak_pc  = ebreak_idx * 4;
            illegal_pc = illegal_idx * 4;
            lh_pc      = lh_idx * 4;
            sw_pc      = sw_idx * 4;

            chk(6, handler_byte_addr);
            chk(7, 32'd0);                           // mtvec was 0 before this write
            chk(9, 32'hCAFEF000);
            chk(9, 32'hCAFEF00D);

            chk(1, ecall_pc);        chk(3, `CAUSE_ECALL_M);          chk(4, 32'd0); chk(1, ecall_pc + 4);
            chk(1, ebreak_pc);       chk(3, `CAUSE_BREAKPOINT);       chk(4, 32'd0); chk(1, ebreak_pc + 4);
            chk(1, illegal_pc);      chk(3, `CAUSE_ILLEGAL_INSTR);    chk(4, 32'd0); chk(1, illegal_pc + 4);

            chk(14, 32'd1);
            chk(1, lh_pc);           chk(3, `CAUSE_LOAD_MISALIGNED);  chk(4, 32'd1); chk(1, lh_pc + 4);

            chk(16, 32'd2);
            chk(17, 32'hDEADC000);
            chk(17, 32'hDEADBEEF);
            chk(1, sw_pc);           chk(3, `CAUSE_STORE_MISALIGNED); chk(4, 32'd2); chk(1, sw_pc + 4);

            chk(19, 32'd777);
            chk(20, 32'hCAFEF00D);                   // the misaligned store never actually wrote memory
        end

        // ============================================================
        // Section M: FENCE / FENCE.I (Zifencei). Both are true no-ops in
        // this design (single in-order hart, no caches) - this just
        // proves they neither trap nor disturb the instructions around
        // them, including a forwarded dependency across the fence.
        // ============================================================
        emit(I_ADDI(21, 0, 32'd42));           chk(21, 32'd42);
        emit(`I_FENCE);
        emit(`I_FENCE_I);
        emit(I_ADDI(22, 21, 32'd1));            chk(22, 32'd43);

        // ============================================================
        // Section N: M extension (multiply/divide). Phase 2. Per-op
        // correctness (every op, every sign combination, the /0 and
        // overflow special cases) is tb_muldiv_unit.v's job; this section
        // is the pipeline-interaction cases that only a full run exercises
        // - the same split Phase 1 used between csr_file's unit test and
        // this file's own Section K/L.
        // ============================================================
        begin : muldiv_section
            integer n_branch_slot, n_branch_target;
            integer n_trap_idx, n_trap_pc;

            // N1: a producer overwriting a register immediately before a
            // muldiv reads it - the muldiv's operand must be the freshly
            // forwarded value (99) at the exact cycle it starts, not the
            // stale pre-forwarding value (5) that a live (non-latching)
            // re-read would fall back to partway through the 32-cycle
            // hold, once EX/MEM and MEM/WB have drained past the producer
            // (see muldiv_unit.v's header for why the operands are latched
            // once, at start, and never re-sampled).
            emit(I_ADDI(5, 0, 32'd5));   chk(5, 32'd5);
            emit(I_ADDI(5, 0, 32'd99));  chk(5, 32'd99);
            emit(I_MUL (6, 5, 5));       chk(6, 32'd9801); // 99*99

            // N2: a MUL result forwarded via EX/MEM to the very next
            // instruction - the muldiv analogue of Section K's CSR-
            // forwarding check, proving ex_result (not the raw ALU
            // output) is what reaches fwd_exmem_data on the completion
            // cycle.
            emit(I_ADDI(7, 0, 32'd6));   chk(7, 32'd6);
            emit(I_ADDI(8, 0, 32'd7));   chk(8, 32'd7);
            emit(I_MUL (9, 7, 8));       chk(9, 32'd42);
            emit(I_ADDI(10, 9, 32'd0));  chk(10, 32'd42);

            // N3: back-to-back muldiv, no idle cycle between them - a DIV
            // immediately follows a MUL in program order, and the DIV's
            // dividend is the MUL's own result, forwarded.
            emit(I_MUL(11, 7, 8));       chk(11, 32'd42);  // 6*7
            emit(I_DIV(12, 11, 7));      chk(12, 32'd7);   // 42/6

            // N4: a load-use hazard immediately followed by a muldiv -
            // two genuinely different stall shapes back to back
            // (hazard_detection.v: the load-use bubble pushes forward
            // while the load continues into MEM; the muldiv hold freezes
            // ID/EX in place instead), proving neither corrupts the other.
            emit(I_SW (12, 0, 32'd132));                   // mem[132] = 7
            emit(I_LW (13, 0, 32'd132)); chk(13, 32'd7);
            emit(I_MUL(2,  13, 13));     chk(2,  32'd49);

            // N5: a taken branch immediately after a muldiv hold ends -
            // proves ex_busy dropping doesn't leave pc_write_en/
            // if_id_flush/id_ex_flush in a stale state that would block
            // or mistime the very next cycle's redirect.
            emit(I_ADDI(14, 0, 32'd10)); chk(14, 32'd10);
            emit(I_ADDI(15, 0, 32'd2));  chk(15, 32'd2);
            emit(I_DIV (16, 14, 15));    chk(16, 32'd5);   // 10/2, ends the hold
            n_branch_slot = idx; emit(32'h0); // BEQ x0,x0,TARGET - patched below
            emit(I_ADDI(17, 0, 32'd999));                  // POISON - must be squashed
            emit(I_ADDI(17, 0, 32'd999));                  // POISON - must be squashed
            n_branch_target = idx;
            emit(I_ADDI(18, 0, 32'd111)); chk(18, 32'd111);
            prog[n_branch_slot] = I_BEQ(0, 0, (n_branch_target - n_branch_slot) * 4);

            // N6: a trap immediately after a muldiv hold ends - the case
            // srotas_processor.v's fixed 2-cycle trap-debug delay (see its
            // header comment) needs to still line up correctly even
            // though a stall happened immediately beforehand. Reuses
            // Section L's already-installed handler (mtvec was set there
            // and is still active).
            emit(I_ADDI(19, 0, 32'd8));  chk(19, 32'd8);
            emit(I_ADDI(20, 0, 32'd3));  chk(20, 32'd3);
            emit(I_DIV (21, 19, 20));    chk(21, 32'd2);   // 8/3, ends the hold
            emit(I_ADDI(22, 0, 32'd129));chk(22, 32'd129); // odd address: half-misaligned
            n_trap_idx = idx; emit(I_LH(24, 22, 32'd0));
            n_trap_pc = n_trap_idx * 4;
            chk(1, n_trap_pc); chk(3, `CAUSE_LOAD_MISALIGNED); chk(4, 32'd129); chk(1, n_trap_pc + 4);
            emit(I_ADDI(25, 0, 32'd55)); chk(25, 32'd55);   // resumed cleanly
        end

        // ============================================================
        // Section O: A extension (atomics). Phase 2. Per-op correctness
        // and the reservation model's edge cases are tb_amo_unit.v's job;
        // this section is the pipeline-interaction cases that only a full
        // run exercises - the same split the M extension used between
        // tb_muldiv_unit.v and Section N. Registers are reused freely
        // across the sub-tests below (O1's x5/x6 etc. are long since
        // irrelevant by the time O6 reuses them), the same convention
        // Section L and Section N already established.
        // ============================================================
        begin : amo_section
            integer o_trap_idx2, o_trap_pc2, o_trap_idx3, o_trap_pc3;

            // O1: lr.w immediately followed by sc.w, zero idle cycle -
            // the actual lock-acquire idiom. The value sc.w will store is
            // computed BEFORE the lr.w so nothing sits between them.
            emit(I_ADDI(5, 0, 32'd256)); chk(5, 32'd256);   // address
            emit(I_ADDI(6, 0, 32'd99));  chk(6, 32'd99);
            emit(I_SW  (6, 5, 32'd0));                       // prime mem[256]=99 (no chk - store)
            emit(I_ADDI(7, 0, 32'd42));  chk(7, 32'd42);    // sc.w's value, ready ahead of time
            emit(I_LR_W(8, 5));          chk(8, 32'd99);    // arms the reservation
            emit(I_SC_W(9, 5, 7));       chk(9, 32'd0);     // immediately after lr.w - succeeds
            emit(I_LW  (10, 5, 32'd0));  chk(10, 32'd42);   // confirm the write actually landed

            // O2: sc.w fails after an intervening ordinary store to the
            // SAME address invalidates the reservation lr.w armed.
            emit(I_ADDI(11, 0, 32'd260)); chk(11, 32'd260);
            emit(I_ADDI(12, 0, 32'd11));  chk(12, 32'd11);
            emit(I_SW  (12, 11, 32'd0));                     // prime mem[260]=11
            emit(I_LR_W(13, 11));         chk(13, 32'd11);  // arms the reservation
            emit(I_ADDI(14, 0, 32'd77));  chk(14, 32'd77);
            emit(I_SW  (14, 11, 32'd0));                     // plain store to the reserved address - invalidates it
            emit(I_ADDI(15, 0, 32'd999)); chk(15, 32'd999);
            emit(I_SC_W(16, 11, 15));     chk(16, 32'd1);   // fails
            emit(I_LW  (17, 11, 32'd0));  chk(17, 32'd77);  // memory still holds the intervening store's value

            // O3: a regular AMO (amoadd.w) whose operand (rs2) comes from
            // an immediately-preceding producer - needs EX/MEM forwarding
            // into the AMO, the same shape as Section D's store-data case.
            emit(I_ADDI(18, 0, 32'd264));  chk(18, 32'd264);
            emit(I_ADDI(19, 0, 32'd5));    chk(19, 32'd5);
            emit(I_SW  (19, 18, 32'd0));                     // prime mem[264]=5
            emit(I_ADDI(20, 0, 32'd3));    chk(20, 32'd3);  // operand producer, right before the AMO
            emit(I_AMOADD_W(21, 18, 20));  chk(21, 32'd5);  // returns OLD value 5; writes 5+3=8
            emit(I_LW  (22, 18, 32'd0));   chk(22, 32'd8);  // confirm the write

            // O4: the AMO's old-value result consumed by the very next
            // instruction - a LOAD-USE STALL (mem_read=1 for every AMO
            // variant), not EX/MEM forwarding - the key architectural
            // difference from how the M extension's result reached its
            // consumer (Section N used EX/MEM forwarding there instead).
            emit(I_ADDI(23, 0, 32'd268)); chk(23, 32'd268);
            emit(I_ADDI(24, 0, 32'd10));  chk(24, 32'd10);
            emit(I_SW  (24, 23, 32'd0));                     // prime mem[268]=10
            emit(I_ADDI(25, 0, 32'd1));   chk(25, 32'd1);
            emit(I_AMOADD_W(26, 23, 25)); chk(26, 32'd10);  // returns old value 10
            emit(I_ADDI(27, 26, 32'd0));  chk(27, 32'd10);  // load-use hazard against x26

            // O5: a misaligned lr.w traps (LOAD_MISALIGNED - lr.w never
            // sets mem_write), and critically, leaves NO reservation
            // armed: a subsequent sc.w to an unrelated address still
            // fails, proving mem_read_in gated the reservation-set branch
            // in amo_unit.v rather than the raw (trap-unaware) is_amo.
            emit(I_ADDI(28, 0, 32'd271)); chk(28, 32'd271); // misaligned: 271 mod 4 = 3
            o_trap_idx2 = idx; emit(I_LR_W(29, 28));
            o_trap_pc2 = o_trap_idx2 * 4;
            chk(1, o_trap_pc2); chk(3, `CAUSE_LOAD_MISALIGNED); chk(4, 32'd271); chk(1, o_trap_pc2 + 4);

            emit(I_ADDI(30, 0, 32'd272)); chk(30, 32'd272); // a different, aligned address
            emit(I_ADDI(31, 0, 32'd999)); chk(31, 32'd999);
            emit(I_SC_W(29, 30, 31));     chk(29, 32'd1);   // fails - no reservation was ever armed

            // O6: a misaligned regular AMO traps as STORE_MISALIGNED
            // (mem_write=1 for every AMO variant except lr.w).
            emit(I_ADDI(5, 0, 32'd273)); chk(5, 32'd273);   // misaligned: 273 mod 4 = 1
            emit(I_ADDI(6, 0, 32'd5));   chk(6, 32'd5);
            o_trap_idx3 = idx; emit(I_AMOADD_W(7, 5, 6));
            o_trap_pc3 = o_trap_idx3 * 4;
            chk(1, o_trap_pc3); chk(3, `CAUSE_STORE_MISALIGNED); chk(4, 32'd273); chk(1, o_trap_pc3 + 4);

            emit(I_ADDI(8, 0, 32'd111)); chk(8, 32'd111);   // resumed cleanly
        end

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

        // Also dump this program as a .mem file: tools/golden_model.py
        // runs the exact same instruction sequence and its trace is
        // diffed against dut_trace.log (below) by tools/lockstep_compare.py
        // - the widest single cross-check in the repo, since this program
        // already carries the hand-written chk() queue above.
        begin : dump_mem
            integer fd, i;
            fd = $fopen("mem/lockstep_test.mem", "w");
            for (i = 0; i < idx; i = i + 1)
                $fdisplay(fd, "%08h", prog[i]);
            $fclose(fd);
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
    // Lockstep trace dump: an independent record of the same event
    // stream the scoreboard above checks, in the plain text format
    // tools/golden_model.py and tools/lockstep_compare.py expect -
    // "C <pc> <rd> <data>" per register write, "T <pc> <cause> <mtval>"
    // per trap. See tools/lockstep_compare.py's module header for the
    // full format and how to run the comparison.
    // -----------------------------------------------------------------
    integer trace_fd;

    initial begin
        trace_fd = $fopen("dut_trace.log", "w");
    end

    always @(posedge clk) begin
        if (rst_n && wb_commit_valid)
            $fdisplay(trace_fd, "C %08h %0d %08h", wb_commit_pc, wb_commit_rd, wb_commit_data);
        if (rst_n && trap_valid)
            $fdisplay(trace_fd, "T %08h %0d %08h", trap_pc, trap_cause, trap_mtval);
    end

    // -----------------------------------------------------------------
    // Reset and run
    // -----------------------------------------------------------------
    initial begin
        rst_n = 0;
        #12 rst_n = 1;

        // Enough cycles for ~160 instructions plus stalls/bubbles, including
        // Section N's several 32-cycle muldiv holds (each one alone costs
        // as much simulated time as roughly 30 ordinary instructions).
        #20000;

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
        $fclose(trace_fd);
        $finish;
    end

endmodule
