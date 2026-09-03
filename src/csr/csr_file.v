// ============================================================================
// Module: csr_file
// File: csr_file.v
// Project: Srotas - 5-Stage RISC-V Processor
//
// Machine-mode control and status registers (Zicsr). Implements the minimum
// CSR set needed for M-mode trap handling: mstatus, misa, mie, mtvec,
// mscratch, mepc, mcause, mtval, mip, plus the read-only ID registers
// (mvendorid/marchid/mimpid/mhartid, all zero - single, unidentified hart).
//
// Three write sources, in priority order:
//   1. Hardware trap entry (trap_en)   - highest priority
//   2. Hardware mret retirement (mret_en)
//   3. A csrrw/csrrs/csrrc-family instruction executing (write_en)
// Priority only matters as a safety net: a correctly-sequenced in-order
// pipeline should never assert more than one of these in the same cycle,
// since a trapping instruction never also completes as a normal CSR write.
//
// No privilege modes exist yet (a later roadmap phase adds S/U), so mstatus
// is currently hardwired to a single trust domain: MPP always reads 2'b11
// (M-mode) and is not writable. mie exposes only the standard M-mode
// interrupt-enable bits (MSIE/MTIE/MEIE); mip is read-only zero for now,
// since no interrupt source (CLINT/PLIC, added in a later phase) exists yet
// to set its bits.
//
// mtvec only supports Direct mode: the mode field (bits[1:0]) is masked to
// 0 on every write, since vectored-mode dispatch isn't implemented.
//
// Pipeline integration - decoding CSR instructions, computing the
// read-modify-write value from rs1/uimm, and driving trap_en/mret_en from
// a trap controller - is a separate, later step. This module only provides
// the storage and the two access interfaces described above.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module csr_file (
    input  wire        clk,
    input  wire        rst_n,

    // Generic instruction-driven access (csrrw/csrrs/csrrc and immediate
    // forms compute the new value externally and present it here).
    input  wire [11:0] addr,
    input  wire [31:0] wdata,
    input  wire        write_en,
    output reg  [31:0] rdata,

    // Hardware trap entry - highest write priority.
    input  wire        trap_en,
    input  wire [31:0] trap_pc,
    input  wire [31:0] trap_cause,
    input  wire [31:0] trap_value,

    // Hardware mret retirement.
    input  wire        mret_en,

    // Direct, always-valid outputs for hardware consumers (PC-redirect
    // logic, future interrupt logic) that need these every cycle without
    // going through the generic address mux.
    output wire [31:0] mtvec_q,
    output wire [31:0] mepc_q,
    output wire        mstatus_mie_q
);

    // -----------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------
    reg        mstatus_mie, mstatus_mpie;
    reg [2:0]  mie_bits;      // bit0=MSIE, bit1=MTIE, bit2=MEIE
    reg [31:0] mtvec_reg;
    reg [31:0] mscratch_reg;
    reg [31:0] mepc_reg;
    reg [31:0] mcause_reg;
    reg [31:0] mtval_reg;

    localparam [31:0] MISA_VAL = 32'h4000_1100; // RV32 (MXL=1), extensions 'I' + 'M' (Phase 2)

    // mstatus: only MIE(3)/MPIE(7) are stored; MPP(12:11) is hardwired to
    // M-mode (2'b11); every other field reads zero until privilege modes,
    // FPU, etc. exist.
    wire [31:0] mstatus_composed =
        {19'b0, 2'b11 /*MPP*/, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};

    // mie: only MEIE(11)/MTIE(7)/MSIE(3) are implemented.
    wire [31:0] mie_composed =
        {20'b0, mie_bits[2], 3'b0, mie_bits[1], 3'b0, mie_bits[0], 3'b0};

    wire [31:0] mip_composed = 32'b0; // no interrupt source wired yet

    assign mtvec_q       = mtvec_reg;
    assign mepc_q         = mepc_reg;
    assign mstatus_mie_q = mstatus_mie;

    // -----------------------------------------------------------------
    // Read (combinational)
    // -----------------------------------------------------------------
    always @(*) begin
        case (addr)
            `CSR_MSTATUS:   rdata = mstatus_composed;
            `CSR_MISA:      rdata = MISA_VAL;
            `CSR_MIE:       rdata = mie_composed;
            `CSR_MTVEC:     rdata = mtvec_reg;
            `CSR_MSCRATCH:  rdata = mscratch_reg;
            `CSR_MEPC:      rdata = mepc_reg;
            `CSR_MCAUSE:    rdata = mcause_reg;
            `CSR_MTVAL:     rdata = mtval_reg;
            `CSR_MIP:       rdata = mip_composed;
            `CSR_MVENDORID: rdata = 32'b0;
            `CSR_MARCHID:   rdata = 32'b0;
            `CSR_MIMPID:    rdata = 32'b0;
            `CSR_MHARTID:   rdata = 32'b0;
            default:        rdata = 32'b0;
        endcase
    end

    // -----------------------------------------------------------------
    // Write (synchronous) - trap entry > mret > software write
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mie_bits     <= 3'b0;
            mtvec_reg    <= 32'b0;
            mscratch_reg <= 32'b0;
            mepc_reg     <= 32'b0;
            mcause_reg   <= 32'b0;
            mtval_reg    <= 32'b0;
        end else if (trap_en) begin
            // mepc[1:0] is always 0 (IALIGN=32: no compressed-instruction
            // support, so instructions are always 4-byte aligned).
            mepc_reg     <= {trap_pc[31:2], 2'b00};
            mcause_reg   <= trap_cause;
            mtval_reg    <= trap_value;
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (mret_en) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (write_en) begin
            case (addr)
                `CSR_MSTATUS: begin
                    mstatus_mie  <= wdata[3];
                    mstatus_mpie <= wdata[7];
                end
                `CSR_MIE: begin
                    mie_bits[0] <= wdata[3];  // MSIE
                    mie_bits[1] <= wdata[7];  // MTIE
                    mie_bits[2] <= wdata[11]; // MEIE
                end
                `CSR_MTVEC:    mtvec_reg    <= {wdata[31:2], 2'b00}; // Direct mode only
                `CSR_MSCRATCH: mscratch_reg <= wdata;
                `CSR_MEPC:     mepc_reg     <= {wdata[31:2], 2'b00};
                `CSR_MCAUSE:   mcause_reg   <= wdata;
                `CSR_MTVAL:    mtval_reg    <= wdata;
                // misa, mip, and the mvendorid/marchid/mimpid/mhartid group
                // are fixed-configuration and read-only here: writes are
                // silently dropped.
                default: ;
            endcase
        end
    end

endmodule
