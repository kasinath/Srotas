// ============================================================================
// Module: muldiv_unit
// File: muldiv_unit.v
// Stage: EX
//
// Iterative multi-cycle implementation of the M-extension's eight ops
// (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU), selected by `op` (the
// instruction's funct3 field, which already encodes exactly these eight
// variants per the RV32M spec). 32-cycle shift-add multiply and 32-cycle
// restoring divide, both operating on sign-stripped magnitudes with the
// correct sign re-applied at the end - readable, teachable RTL over a DSP-
// inferring `*`/`/`, matching this project's learning focus.
//
// `req` is a LEVEL, not a pulse: it is simply "the instruction currently
// held in EX is a muldiv" (id_ex's is_muldiv_out), which stays asserted for
// the entire multi-cycle hold since hazard_detection_unit freezes ID/EX via
// id_ex_write_en while busy. The unit only reacts to req on the IDLE->RUN
// edge (see `start` below); once running, further req=1 cycles are ignored
// until the operation completes.
//
// `busy` is combinationally asserted the instant a new op is recognized
// (`state==IDLE && req`), one cycle before the internal state register
// actually reaches RUN - this is what stops hazard_detection_unit from
// letting the pipeline advance on the very edge that would otherwise load
// the operation's own operands into this module while simultaneously
// overwriting the ID/EX register that owns them.
//
// operand_a/operand_b are latched into a_q/b_q on that same start edge and
// used for every iteration and the final sign-fixup - never re-read live.
// This matters because operand_a/operand_b are the EX-stage forwarding
// muxes' outputs: EX/MEM and MEM/WB keep draining (they are plain, always-
// advancing latches that take bubbles while EX is held), so forward_a/
// forward_b - and therefore the live operand values - can change mid-hold
// even though the instruction in EX does not. Re-reading them across the
// multi-cycle operation would silently substitute in a value belonging to
// a different instruction.
//
// `busy` deasserts on the exact cycle `done` asserts (the same cycle the
// final iteration's registered result becomes readable), and the internal
// state returns to IDLE on that same clock edge - so a second muldiv
// already waiting in ID/EX (having been held there behind the first) is
// recognized as a fresh `start` on the very next cycle, with no extra idle
// cycle between back-to-back muldiv instructions.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module muldiv_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,          // level: is_muldiv of the instruction in EX
    input  wire [2:0]  op,           // funct3: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
    input  wire [31:0] operand_a,    // rs1 (forwarded)
    input  wire [31:0] operand_b,    // rs2 (forwarded)
    output wire        busy,
    output wire        done,
    output wire [31:0] result
);

    localparam ST_IDLE = 1'b0;
    localparam ST_RUN  = 1'b1;

    reg        state;
    reg [4:0]  count;         // iterations remaining after the current cycle
    reg [2:0]  op_q;
    reg [31:0] a_q, b_q;      // latched raw (two's-complement) operands

    reg [31:0] product_hi, product_lo;  // multiply datapath
    reg [31:0] multiplicand_q;
    reg [63:0] rq;                      // divide datapath: {remainder, quotient}
    reg [31:0] divisor_q;

    // -----------------------------------------------------------------
    // One shift-add multiply step / one restoring-divide step, purely
    // combinational so both the start edge (operating on live inputs)
    // and every later edge (operating on the latched/registered state)
    // can share the same logic.
    // -----------------------------------------------------------------
    function [63:0] mul_step;
        input [31:0] hi, lo, multiplicand;
        reg   [32:0] sum;
        begin
            sum = lo[0] ? ({1'b0, hi} + {1'b0, multiplicand}) : {1'b0, hi};
            mul_step = {sum[32:1], sum[0], lo[31:1]};
        end
    endfunction

    function [63:0] div_step;
        input [63:0] rq_in;
        input [31:0] divisor;
        reg   [63:0] shifted;
        reg   [31:0] cand_rem;
        begin
            shifted  = {rq_in[62:0], 1'b0};
            cand_rem = shifted[63:32];
            if (cand_rem >= divisor)
                div_step = {cand_rem - divisor, shifted[31:1], 1'b1};
            else
                div_step = shifted;
        end
    endfunction

    // is_muldiv op encoding (funct3, per RV32M):
    //   op[2]==0: multiply family - MUL(00) MULH(01) MULHSU(10) MULHU(11)
    //   op[2]==1: divide family   - DIV(00) DIVU(01)  REM(10)   REMU(11)
    // Used only while computing the start-time magnitudes below, so this
    // reads the live `op` input (valid at the start edge); everything after
    // the start edge reads op_q, the latched copy, instead.
    wire start_is_divide = op[2];

    // Multiply: which operand(s) are signed, per variant.
    wire mul_signed_a = !(op[1] && op[0]);   // all but MULHU
    wire mul_signed_b = !op[1];              // MUL, MULH only

    // Divide: op[0]==0 -> signed (DIV/REM), op[0]==1 -> unsigned (DIVU/REMU)
    wire div_signed = !op[0];

    // Magnitudes computed from the LIVE inputs, used only on the start edge.
    wire start_neg_a = start_is_divide ? (div_signed && operand_a[31])
                                        : (mul_signed_a && operand_a[31]);
    wire start_neg_b = start_is_divide ? (div_signed && operand_b[31])
                                        : (mul_signed_b && operand_b[31]);
    wire [31:0] start_mag_a = start_neg_a ? (~operand_a + 32'b1) : operand_a;
    wire [31:0] start_mag_b = start_neg_b ? (~operand_b + 32'b1) : operand_b;

    wire start = (state == ST_IDLE) && req;
    assign busy = (state == ST_RUN && count != 5'd0) || start;
    assign done = (state == ST_RUN) && (count == 5'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            count         <= 5'd0;
            op_q          <= 3'd0;
            a_q           <= 32'b0;
            b_q           <= 32'b0;
            product_hi    <= 32'b0;
            product_lo    <= 32'b0;
            multiplicand_q<= 32'b0;
            rq            <= 64'b0;
            divisor_q     <= 32'b0;
        end else if (start) begin
            state      <= ST_RUN;
            count      <= 5'd31;
            op_q       <= op;
            a_q        <= operand_a;
            b_q        <= operand_b;
            {product_hi, product_lo} <= mul_step(32'b0, start_mag_b, start_mag_a);
            multiplicand_q <= start_mag_a;
            rq         <= div_step({32'b0, start_mag_a}, start_mag_b);
            divisor_q  <= start_mag_b;
        end else if (state == ST_RUN && count != 5'd0) begin
            count <= count - 5'd1;
            {product_hi, product_lo} <= mul_step(product_hi, product_lo, multiplicand_q);
            rq                       <= div_step(rq, divisor_q);
        end else if (state == ST_RUN) begin
            // count == 0: this is the `done` cycle - result is read out
            // combinationally below; go back to IDLE for the next request.
            state <= ST_IDLE;
        end
    end

    // -----------------------------------------------------------------
    // Final sign fix-up and RV32M special cases, applied to the
    // now-complete unsigned-magnitude results. Combinational: valid
    // whenever `done` is asserted (garbage, harmlessly, at all other
    // times since ex_stage_top only lets it reach architectural state
    // on the done cycle). Deliberately re-derived from the LATCHED op_q/
    // a_q/b_q, not the live op/operand_a/operand_b ports, so this stays
    // correct even if a future change relaxes the assumption that the
    // live inputs never move during the hold.
    wire is_divide       = op_q[2];
    wire final_signed_a  = !(op_q[1] && op_q[0]);   // mul: all but MULHU
    wire final_signed_b  = !op_q[1];                // mul: MUL, MULH only
    wire final_div_signed = !op_q[0];               // div: DIV/REM

    wire        mul_result_sign = (final_signed_a && a_q[31]) ^ (final_signed_b && b_q[31]);
    wire [63:0] mul_mag_full    = {product_hi, product_lo};
    wire [63:0] mul_full        = mul_result_sign ? (~mul_mag_full + 64'b1) : mul_mag_full;
    wire [31:0] mul_result      = (op_q[1:0] == 2'b00) ? mul_full[31:0] : mul_full[63:32];

    wire        div_by_zero  = (b_q == 32'b0);
    wire        div_overflow = final_div_signed && (a_q == 32'h8000_0000) && (b_q == 32'hFFFF_FFFF);

    wire        quot_sign = final_div_signed && (a_q[31] ^ b_q[31]);
    wire        rem_sign  = final_div_signed && a_q[31];
    wire [31:0] quot_mag  = rq[31:0];
    wire [31:0] rem_mag   = rq[63:32];
    wire [31:0] quot_norm = quot_sign ? (~quot_mag + 32'b1) : quot_mag;
    wire [31:0] rem_norm  = rem_sign  ? (~rem_mag  + 32'b1) : rem_mag;

    wire [31:0] quot_final = div_by_zero  ? 32'hFFFF_FFFF :
                              div_overflow ? 32'h8000_0000 :
                                             quot_norm;
    wire [31:0] rem_final  = div_by_zero  ? a_q :
                              div_overflow ? 32'b0 :
                                             rem_norm;
    wire [31:0] div_result = op_q[1] ? rem_final : quot_final;

    assign result = is_divide ? div_result : mul_result;

endmodule
