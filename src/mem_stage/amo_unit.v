// ============================================================================
// Module: amo_unit
// File: amo_unit.v
// Stage: MEM
//
// The A extension's read-modify-write: lr.w/sc.w (load-reserved/store-
// conditional) and the nine AMO ops (swap/add/xor/and/or/min/max/minu/
// maxu). Single-cycle, unlike the M extension's multi-cycle muldiv_unit.v -
// data_memory.v's combinational read and synchronous write to the same
// address are already RMW-safe with no changes to that module: the old
// value is stable and observable for the whole cycle before the write
// commits at the next clock edge, so `old_value` (data_memory's raw read
// output) and `write_data` (fed back into data_memory's write input) can
// both be wired up the same cycle without any new stall mechanism.
//
// mem_read_in/mem_write_in must be the ALREADY trap-suppressed mem_read/
// mem_write signals as they arrive at MEM (ex_stage_top.v's eff_mem_read/
// eff_mem_write, threaded through ex_mem_register unchanged) - NOT a raw
// is_amo flag. is_amo alone isn't trap-aware: a misaligned lr.w still has
// is_amo=1 all the way to MEM (nothing upstream zeroes it), but eff_mem_read
// is correctly 0 for it. Gating the reservation-set/clear branches on
// mem_read_in/mem_write_in - not is_amo - is what stops a trapped lr.w/
// sc.w from silently arming or consuming a reservation nothing should have
// touched. The *output-value* mux (rd_value) doesn't need this same care:
// reg_write is already 0 for a trapping instruction downstream, so nothing
// ever architecturally observes rd_value regardless of what it computes.
//
// Reservation model: one address register plus one valid bit - the
// textbook address-matching model, not the cheaper-but-unrepresentative
// "any write anywhere clears it." lr.w arms it; sc.w always clears it
// (success or fail, both spec-legal); any OTHER write (a plain store, or a
// regular AMO) to the reserved address also clears it, per spec - the
// third branch below covers both by if/else-if priority falling through
// past the first two.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module amo_unit (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        is_amo,
    input  wire [4:0]  amo_funct5,
    input  wire [31:0] mem_addr,     // = alu_result reaching MEM (rs1, no immediate)
    input  wire [31:0] old_value,    // = data_memory's raw combinational read output
    input  wire [31:0] operand,      // = forwarded rs2 (the AMO's value operand / sc.w's store value)
    input  wire        mem_read_in,  // = eff_mem_read reaching MEM (already trap-suppressed)
    input  wire        mem_write_in, // = eff_mem_write reaching MEM (already trap-suppressed)

    output wire [31:0] write_data,   // value to feed data_memory.mem_write_data
    output wire        write_enable, // value to feed data_memory.mem_write
    output wire [31:0] rd_value      // value to feed mem_wb_register.mem_read_data
);

    reg        reserved_valid;
    reg [31:0] reserved_addr;

    wire is_lr = is_amo && (amo_funct5 == `AMO_F5_LR);
    wire is_sc = is_amo && (amo_funct5 == `AMO_F5_SC);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reserved_valid <= 1'b0;
            reserved_addr  <= 32'b0;
        end else if (is_lr && mem_read_in) begin
            reserved_valid <= 1'b1;
            reserved_addr  <= mem_addr;
        end else if (is_sc && mem_write_in) begin
            reserved_valid <= 1'b0;
        end else if (mem_write_in && reserved_valid && (mem_addr == reserved_addr)) begin
            reserved_valid <= 1'b0;
        end
    end

    wire sc_success = is_sc && mem_write_in && reserved_valid && (mem_addr == reserved_addr);

    reg [31:0] amo_alu_result;
    always @(*) begin
        case (amo_funct5)
            `AMO_F5_SWAP: amo_alu_result = operand;
            `AMO_F5_ADD:  amo_alu_result = old_value + operand;
            `AMO_F5_XOR:  amo_alu_result = old_value ^ operand;
            `AMO_F5_AND:  amo_alu_result = old_value & operand;
            `AMO_F5_OR:   amo_alu_result = old_value | operand;
            `AMO_F5_MIN:  amo_alu_result = ($signed(old_value) < $signed(operand)) ? old_value : operand;
            `AMO_F5_MAX:  amo_alu_result = ($signed(old_value) > $signed(operand)) ? old_value : operand;
            `AMO_F5_MINU: amo_alu_result = (old_value < operand) ? old_value : operand;
            `AMO_F5_MAXU: amo_alu_result = (old_value > operand) ? old_value : operand;
            default:      amo_alu_result = operand; // unreachable for is_amo (control_unit.v traps unknown funct5)
        endcase
    end

    assign write_enable = is_lr ? 1'b0 :
                           is_sc ? sc_success :
                                   mem_write_in;
    assign write_data  = is_sc ? operand : amo_alu_result;
    assign rd_value    = is_sc ? {31'b0, !sc_success} : old_value;

endmodule
