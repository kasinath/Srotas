// ============================================================================
// Module: hazard_detection_unit
// File: hazard_detection.v
// Project: Srotas RISC-V Processor
//
// Combined hazard-stall and data-forwarding controller.
//
// 1) Load-use hazard: the instruction about to enter EX (held in the ID/EX
//    register) is a load, and the instruction currently in ID needs that
//    register. Load data isn't ready until MEM completes, so forwarding
//    can't fix this - the pipeline stalls for exactly one cycle by
//    freezing PC and IF/ID and inserting a bubble into ID/EX.
//
// 2) EX/MEM and MEM/WB forwarding: for every other RAW hazard distance,
//    the operand is forwarded combinationally into the EX stage instead of
//    stalling - forward_a/forward_b select between the un-forwarded ID/EX
//    value (2'b00), the result of the instruction one stage ahead, in MEM
//    (2'b01), or two stages ahead, in WB (2'b10). EX/MEM (the closer
//    producer) wins if both would otherwise match.
//
// 3) Branch/jump/trap/mret redirect: resolved combinationally in EX (a
//    trap - illegal instruction, ecall/ebreak, or a misaligned address -
//    and mret drive the same ex_redirect signal a branch does; see
//    ex_stage_top.v). Squashes the two wrong-path instructions already
//    fetched (currently in IF and ID) by flushing IF/ID and ID/EX the same
//    cycle the redirect fires.
//
//    pc_write_en must never be held low by a load-use stall while
//    ex_redirect is asserted: a load can now be the very instruction
//    causing the redirect (a misaligned load traps), so without this,
//    a load-use hazard against whatever's in ID could block the PC from
//    ever reaching the trap target. Before traps existed this could never
//    happen - only a mem_read=0 instruction (a branch/jump) could redirect,
//    and mem_read=1 is required for a load-use hazard, so the two
//    conditions were mutually exclusive by construction. That's no longer
//    true once a load itself can trap.
//
// 4) EX-stage multi-cycle hold (Phase 2, the M extension): ex_busy is
//    asserted for as long as the multi-cycle muldiv unit in EX is running.
//    Unlike the load-use stall above - which bubbles ID/EX forward while
//    letting the load itself continue into MEM - a busy muldiv must stay
//    IN EX; ID/EX has to be held in place, not flushed, or its operands
//    would be overwritten mid-computation by the next ID-stage instruction.
//    So ex_busy freezes PC, IF/ID, AND ID/EX (via the new id_ex_write_en),
//    while ex_stage_top.v suppresses the held instruction's effects into
//    EX/MEM every cycle it's busy, the same way it already suppresses a
//    trapping instruction's effects - see docs/processor_guide.md Section 6
//    for the two stall shapes side by side.
//
//    ex_busy and id_ex_flush (load_use_hazard || ex_redirect) never overlap
//    by construction: while busy, the instruction held in ID/EX is a
//    muldiv, so id_ex_mem_read is 0 (no load-use hazard can be detected
//    against it) and none of ex_stage_top.v's redirect conditions (branch/
//    jump/trap) can be true for it either - a muldiv is none of those. So
//    id_ex_write_en=0 and id_ex_flush=1 are never both asserted for the
//    same instruction; if they ever were, id_ex_register.v's write_en check
//    takes priority (a full hold), matching if_id_register.v's precedent
//    of flush/hold ordering being resolved the same way in that register.
// ============================================================================

`timescale 1ns/1ps

module hazard_detection_unit (
    // Instruction currently in ID (about to be latched into ID/EX)
    input  wire [4:0] id_rs1_addr,
    input  wire [4:0] id_rs2_addr,

    // Instruction currently in EX (ID/EX register outputs)
    input  wire [4:0] id_ex_rs1_addr,
    input  wire [4:0] id_ex_rs2_addr,
    input  wire [4:0] id_ex_rd_addr,
    input  wire       id_ex_mem_read,

    // Instruction currently in MEM (EX/MEM register outputs)
    input  wire [4:0] ex_mem_rd_addr,
    input  wire       ex_mem_reg_write,

    // Instruction currently in WB (MEM/WB register outputs)
    input  wire [4:0] mem_wb_rd_addr,
    input  wire       mem_wb_reg_write,

    // Branch/jump resolution, combinational from EX this cycle
    input  wire       ex_redirect,

    // EX-stage multi-cycle muldiv unit (Phase 2), combinational from EX
    input  wire       ex_busy,

    // Pipeline control
    output wire        pc_write_en,
    output wire        if_id_write_en,
    output wire        if_id_flush,
    output wire        id_ex_flush,
    output wire        id_ex_write_en,

    // Forwarding selects for the EX stage
    output wire [1:0]  forward_a,
    output wire [1:0]  forward_b
);

    wire load_use_hazard =
        id_ex_mem_read && (id_ex_rd_addr != 5'd0) &&
        ((id_ex_rd_addr == id_rs1_addr) || (id_ex_rd_addr == id_rs2_addr));

    assign pc_write_en    = (!load_use_hazard && !ex_busy) || ex_redirect;
    assign if_id_write_en = !load_use_hazard && !ex_busy;
    assign if_id_flush    = ex_redirect;
    assign id_ex_flush    = load_use_hazard || ex_redirect;
    assign id_ex_write_en = !ex_busy;

    assign forward_a =
        (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs1_addr)) ? 2'b01 :
        (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs1_addr)) ? 2'b10 :
        2'b00;

    assign forward_b =
        (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs2_addr)) ? 2'b01 :
        (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs2_addr)) ? 2'b10 :
        2'b00;

endmodule
