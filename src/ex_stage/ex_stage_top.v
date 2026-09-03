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
//
// CSR execution: csr_file.v lives here, alongside the ALU and branch unit,
// since - like them - it's a pure function of this stage's own inputs plus
// one cycle's worth of state. Its read address is driven unconditionally
// from csr_addr every cycle; that's harmless because none of the currently
// implemented CSRs have read side effects, and csr_op being 2'b00 (the
// safe default, including on a squashed/bubbled instruction - see
// id_ex_register.v) already prevents any write. The write operand is
// rs1_fwd (the same forwarded value the ALU would use) when csr_use_imm is
// 0, or the zero-extended 5-bit immediate packed into the instruction's
// rs1 field when it's 1 - deliberately NOT rs1_fwd in that case, since
// forwarding must not substitute in some unrelated register's value that
// happens to coincide with those 5 bits.
//
// Trap controller: also lives here, since every condition it needs to
// check is already local to this stage.
//   - ecall/ebreak/illegal (decoded in ID) simply pass through combinationally.
//   - Instruction-address-misaligned: whenever branch_unit resolves a real
//     redirect (a taken branch or any jump) with bit[1] of its target set.
//     Bit[0] is never checked - branch_unit already forces it to 0 for
//     JALR, and B-type/J-type immediates always have it 0 by construction
//     (Section 2 of docs/processor_guide.md) - so bit[1] is the only bit
//     that can make a target something other than 4-byte aligned, which is
//     all IALIGN=32 (no C extension) requires.
//   - Load/store-address-misaligned: from alu_result (the memory address)
//     and funct3, gated on mem_read/mem_write - byte accesses are never
//     misaligned, half-word needs bit[0]=0, word needs bits[1:0]=00.
// These conditions are mutually exclusive per instruction by construction
// (a CSR instruction can't also be a branch; ecall/ebreak/illegal never
// set mem_read/mem_write/branch/jump; only one of a branch/jump vs. a
// load/store can be true for any single instruction), so there is no real
// priority conflict to resolve between them.
//
// A trapping instruction must not complete any of its normal effects: its
// reg_write/mem_read/mem_write are forced off before reaching
// ex_mem_register, so it becomes architecturally inert exactly like a
// squashed or bubbled instruction - see the local eff_reg_write etc.
// below. (csr_op needs no equivalent guard: a CSR instruction can never
// simultaneously be illegal, ecall/ebreak, or an address computation, so
// csr_write_en and trap_taken are already mutually exclusive by
// construction, not just by coincidence.)
//
// The resulting trap redirect reuses the exact same `redirect`/
// `redirect_target` outputs a plain branch already drives - trap entry
// (target mtvec_q) and mret (target mepc_q) both take priority over an
// ordinary branch/jump redirect, since a trapping branch/jump must not
// also be allowed to redirect to its own (possibly bad) target.
//
// M-extension unit (Phase 2): muldiv_unit.v lives here too, fed the SAME
// forwarded operands (rs1_fwd/rs2_fwd) the ALU uses - it latches them
// internally on the cycle it starts, since EX/MEM and MEM/WB keep draining
// while ID/EX is held busy, so the live forwarded values could otherwise
// drift mid-operation. Its result replaces alu_result (not a new
// result_src encoding - that 2-bit space is already fully used) on the way
// into ex_mem_register, via ex_result below; every other consumer of the
// raw alu_result wire (branch_unit, the misalignment checks) is unaffected
// because a muldiv instruction is never a branch, jump, load, or store.
// ex_busy holds off eff_reg_write/eff_mem_read/eff_mem_write every cycle
// the unit is busy, the same way trap_taken already does - see
// hazard_detection.v for how ex_busy freezes PC/IF/ID/ID/EX upstream.
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
    input  wire [4:0]  rs1_addr,   // raw ID/EX-latched field; only used to reconstruct zimm for csrr__i
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
    input  wire [1:0]  csr_op,
    input  wire        csr_use_imm,
    input  wire [11:0] csr_addr,
    input  wire        ecall,
    input  wire        ebreak,
    input  wire        mret,
    input  wire        illegal,
    input  wire        is_muldiv,

    // Forwarding
    input  wire [1:0]  forward_a,
    input  wire [1:0]  forward_b,
    input  wire [31:0] fwd_exmem_data,
    input  wire [31:0] fwd_memwb_data,

    // Branch/jump resolution, back to IF stage
    output wire         redirect,
    output wire [31:0]  redirect_target,

    // Multi-cycle muldiv unit busy, back to hazard_detection_unit
    output wire         ex_busy,

    // Trap debug/observation port (not part of the datapath - lets an
    // external monitor, e.g. the lockstep harness in tools/, see a trap
    // the same cycle it's resolved, without needing hierarchical access
    // into this module's internals).
    output wire         trap_debug_valid,
    output wire [31:0]  trap_debug_cause,
    output wire [31:0]  trap_debug_value,

    // To MEM stage (via EX/MEM register)
    output wire [31:0] mem_pc_plus4,
    output wire [31:0] mem_alu_result,
    output wire [31:0] mem_write_data,
    output wire [4:0]  mem_rd_addr,
    output wire [2:0]  mem_funct3,
    output wire        mem_reg_write,
    output wire        mem_mem_read,
    output wire        mem_mem_write,
    output wire [1:0]  mem_result_src,
    output wire [31:0] mem_csr_rdata
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

    // ---------------------------------------------------------------
    // M-extension: multi-cycle multiply/divide unit
    // ---------------------------------------------------------------
    wire [31:0] muldiv_result;

    muldiv_unit u_muldiv_unit (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (is_muldiv),
        .op        (funct3),
        .operand_a (rs1_fwd),
        .operand_b (rs2_fwd),
        .busy      (ex_busy),
        .done      (),
        .result    (muldiv_result)
    );

    // Replaces alu_result on the way into EX/MEM for a muldiv instruction;
    // every other consumer below (branch_unit, misalignment checks) keeps
    // reading the raw ALU output, which is fine - a muldiv is never a
    // branch, jump, load, or store.
    wire [31:0] ex_result = is_muldiv ? muldiv_result : alu_result;

    wire        branch_redirect;
    wire [31:0] branch_redirect_target;

    branch_unit u_branch_unit (
        .pc              (pc),
        .imm             (imm),
        .alu_result      (alu_result),
        .alu_zero        (alu_zero),
        .funct3          (funct3),
        .branch          (branch),
        .jump            (jump),
        .is_jalr         (is_jalr),
        .redirect        (branch_redirect),
        .redirect_target (branch_redirect_target)
    );

    // Instruction-address-misaligned: only meaningful when branch_unit is
    // actually redirecting (a not-taken branch never checks its target).
    wire instr_misaligned = branch_redirect && branch_redirect_target[1];

    // ---------------------------------------------------------------
    // Trap controller (declared ahead of csr_file below, which reads
    // trap_taken/trap_cause/trap_value combinationally the same cycle)
    // ---------------------------------------------------------------
    // Load/store-address-misaligned: byte accesses (FUNCT3_LB/LBU, and SB)
    // are never misaligned; half-word needs bit[0]=0; word needs
    // bits[1:0]=00. funct3 uses the same width encoding for loads and
    // stores (000=byte, 001=half, 010=word), so one check covers both.
    wire mem_misaligned =
        (mem_read || mem_write) &&
        ((funct3 == `FUNCT3_LW)                         ? (alu_result[1:0] != 2'b00) :
         (funct3 == `FUNCT3_LH || funct3 == `FUNCT3_LHU) ? alu_result[0] :
                                                            1'b0);

    wire trap_taken = illegal || ecall || ebreak || instr_misaligned || mem_misaligned;

    reg [31:0] trap_cause, trap_value;
    always @(*) begin
        if (illegal) begin
            trap_cause = `CAUSE_ILLEGAL_INSTR;
            trap_value = 32'b0; // spec permits 0 here; the instruction word isn't threaded to EX
        end else if (ecall) begin
            trap_cause = `CAUSE_ECALL_M;
            trap_value = 32'b0;
        end else if (ebreak) begin
            trap_cause = `CAUSE_BREAKPOINT;
            trap_value = 32'b0;
        end else if (instr_misaligned) begin
            trap_cause = `CAUSE_INSTR_MISALIGNED;
            trap_value = branch_redirect_target;
        end else if (mem_misaligned) begin
            trap_cause = mem_write ? `CAUSE_STORE_MISALIGNED : `CAUSE_LOAD_MISALIGNED;
            trap_value = alu_result;
        end else begin
            trap_cause = 32'b0;
            trap_value = 32'b0;
        end
    end

    // Data to store to memory is always the (forwarded) rs2 value, never
    // whatever the ALU's B operand happened to be selecting.
    wire [31:0] store_data = rs2_fwd;

    // ---------------------------------------------------------------
    // CSR execution
    // ---------------------------------------------------------------
    wire [31:0] csr_rdata;

    // csrrw/csrrs/csrrc use the forwarded rs1 value; the _i forms use the
    // zero-extended 5-bit immediate sitting in the instruction's rs1 field
    // instead - never rs1_fwd, since that field isn't a register reference
    // for those encodings and forwarding could otherwise substitute in an
    // unrelated value that happens to numerically match it.
    wire [31:0] csr_operand = csr_use_imm ? {27'b0, rs1_addr} : rs1_fwd;
    wire        csr_write_en = (csr_op != 2'b00);

    reg [31:0] csr_wdata;
    always @(*) begin
        case (csr_op)
            `CSR_OP_RW: csr_wdata = csr_operand;
            `CSR_OP_RS: csr_wdata = csr_rdata | csr_operand;
            `CSR_OP_RC: csr_wdata = csr_rdata & ~csr_operand;
            default:    csr_wdata = csr_rdata; // no CSR instruction this cycle
        endcase
    end

    wire [31:0] mtvec_q, mepc_q;

    csr_file u_csr_file (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (csr_addr),
        .wdata    (csr_wdata),
        .write_en (csr_write_en),
        .rdata    (csr_rdata),

        .trap_en    (trap_taken),
        .trap_pc    (pc),
        .trap_cause (trap_cause),
        .trap_value (trap_value),
        .mret_en    (mret),

        .mtvec_q       (mtvec_q),
        .mepc_q        (mepc_q),
        .mstatus_mie_q ()
    );

    assign trap_debug_valid = trap_taken;
    assign trap_debug_cause = trap_cause;
    assign trap_debug_value = trap_value;

    // Trap entry and mret both override an ordinary branch/jump redirect -
    // a trapping branch/jump must never also redirect to its own target.
    assign redirect        = trap_taken || mret || branch_redirect;
    assign redirect_target = trap_taken ? mtvec_q :
                              mret       ? mepc_q  :
                                           branch_redirect_target;

    // A trapping instruction completes none of its normal effects, and
    // neither does a muldiv instruction on any cycle it's still busy - both
    // feed ex_mem_register in place of the raw control signals below. (A
    // muldiv is never itself trap_taken - illegal/ecall/ebreak/instr_
    // misaligned/mem_misaligned are all false for it by construction, since
    // it sets none of branch/jump/mem_read/mem_write/ecall/ebreak/illegal -
    // so these two suppression sources never overlap for the same
    // instruction, they just both apply cleanly across different ones.)
    wire eff_reg_write = reg_write && !trap_taken && !ex_busy;
    wire eff_mem_read  = mem_read  && !trap_taken && !ex_busy;
    wire eff_mem_write = mem_write && !trap_taken && !ex_busy;

    ex_mem_register u_ex_mem_register (
        .clk             (clk),
        .rst_n           (rst_n),

        .pc_plus4        (pc_plus4),
        .alu_result      (ex_result),
        .mem_write_data  (store_data),
        .rd_addr         (rd_addr),
        .funct3          (funct3),
        .csr_rdata       (csr_rdata),

        .reg_write       (eff_reg_write),
        .mem_read        (eff_mem_read),
        .mem_write       (eff_mem_write),
        .result_src      (result_src),

        .pc_plus4_out       (mem_pc_plus4),
        .alu_result_out     (mem_alu_result),
        .mem_write_data_out (mem_write_data),
        .rd_addr_out        (mem_rd_addr),
        .funct3_out         (mem_funct3),
        .csr_rdata_out      (mem_csr_rdata),
        .reg_write_out      (mem_reg_write),
        .mem_read_out       (mem_mem_read),
        .mem_write_out      (mem_mem_write),
        .result_src_out     (mem_result_src)
    );

endmodule
