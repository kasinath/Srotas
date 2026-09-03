// ============================================================================
// File: rv32i_defines.vh
// Project: Srotas - 5-Stage RISC-V Processor
//
// Central set of encodings shared by the control unit, ALU, and branch
// logic. Everything that decodes or acts on opcode/funct3/funct7/ALU
// control bits should `include this file instead of hard-coding numbers,
// so the encodings can never drift out of sync between modules.
// ============================================================================

`ifndef RV32I_DEFINES_VH
`define RV32I_DEFINES_VH

// ---------------------------------------------------------------------------
// RV32I base opcodes (instruction[6:0])
// ---------------------------------------------------------------------------
`define OP_LUI    7'b0110111
`define OP_AUIPC  7'b0010111
`define OP_JAL    7'b1101111
`define OP_JALR   7'b1100111
`define OP_BRANCH 7'b1100011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_IMM    7'b0010011
`define OP_REG    7'b0110011
`define OP_SYSTEM 7'b1110011  // CSR instructions (Zicsr) and ECALL/EBREAK/MRET
`define OP_MISC_MEM 7'b0001111  // FENCE (base RV32I) and FENCE.I (Zifencei)

// ---------------------------------------------------------------------------
// ALU control encoding (4 bits) - shared by control_unit.v and alu.v
// ---------------------------------------------------------------------------
`define ALU_ADD  4'h0
`define ALU_SUB  4'h1
`define ALU_SLL  4'h2
`define ALU_SLT  4'h3
`define ALU_SLTU 4'h4
`define ALU_XOR  4'h5
`define ALU_SRL  4'h6
`define ALU_SRA  4'h7
`define ALU_OR   4'h8
`define ALU_AND  4'h9

// ---------------------------------------------------------------------------
// Immediate format selector (for sign_extend.v)
// ---------------------------------------------------------------------------
`define IMM_I 3'b000
`define IMM_S 3'b001
`define IMM_B 3'b010
`define IMM_U 3'b011
`define IMM_J 3'b100

// ---------------------------------------------------------------------------
// ALU operand-A source select
// ---------------------------------------------------------------------------
`define ASEL_RS1  2'b00  // register rs1
`define ASEL_PC   2'b01  // program counter (AUIPC)
`define ASEL_ZERO 2'b10  // constant zero (LUI)

// ---------------------------------------------------------------------------
// Writeback data source select (result_src)
// ---------------------------------------------------------------------------
`define RESULT_ALU  2'b00  // ALU result
`define RESULT_MEM  2'b01  // data memory read result
`define RESULT_LINK 2'b10  // PC + 4 (JAL / JALR return address)
`define RESULT_CSR  2'b11  // old CSR value (csrrw/csrrs/csrrc and immediate forms)

// ---------------------------------------------------------------------------
// Load/store size encoding (funct3)
// ---------------------------------------------------------------------------
`define FUNCT3_LB  3'b000
`define FUNCT3_LH  3'b001
`define FUNCT3_LW  3'b010
`define FUNCT3_LBU 3'b100
`define FUNCT3_LHU 3'b101

// Branch funct3
`define FUNCT3_BEQ  3'b000
`define FUNCT3_BNE  3'b001
`define FUNCT3_BLT  3'b100
`define FUNCT3_BGE  3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111

// ---------------------------------------------------------------------------
// M extension (Zmmul... full M: multiply/divide). Shares OP_REG with the
// base ALU R-type ops; funct7 distinguishes the two (control_unit.v).
// funct3 gives the 8 sub-ops directly - no separate ALU-op-style encoding
// needed since muldiv_unit.v takes funct3 as its own `op` input.
// ---------------------------------------------------------------------------
`define FUNCT7_MULDIV 7'b0000001
`define FUNCT3_MUL    3'b000
`define FUNCT3_MULH   3'b001
`define FUNCT3_MULHSU 3'b010
`define FUNCT3_MULHU  3'b011
`define FUNCT3_DIV    3'b100
`define FUNCT3_DIVU   3'b101
`define FUNCT3_REM    3'b110
`define FUNCT3_REMU   3'b111

`define NOP_INSTR 32'h00000013  // addi x0, x0, 0

// ---------------------------------------------------------------------------
// Machine-mode CSR addresses (Zicsr) - the minimal M-mode-only set needed
// for trap handling. Used by csr_file.v.
// ---------------------------------------------------------------------------
`define CSR_MSTATUS   12'h300
`define CSR_MISA      12'h301
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

// ---------------------------------------------------------------------------
// CSR instruction operation encoding (used by control_unit.v's csr_op
// output). For all six csrrw/csrrs/csrrc/csrrwi/csrrsi/csrrci encodings,
// funct3[1:0] directly gives this 2-bit operation regardless of whether the
// source is a register (csrr_) or a 5-bit immediate (csrr_i) - funct3[2] is
// the separate register-vs-immediate selector, exposed as csr_use_imm.
// ---------------------------------------------------------------------------
`define CSR_OP_RW 2'b01  // csrrw(i):  CSR <= operand
`define CSR_OP_RS 2'b10  // csrrs(i):  CSR <= CSR | operand
`define CSR_OP_RC 2'b11  // csrrc(i):  CSR <= CSR & ~operand

// ---------------------------------------------------------------------------
// OP_SYSTEM, funct3 == 000: identifies ECALL/EBREAK/MRET by the imm[11:0]
// field (instruction[31:20] - the same bits as a CSR address, since these
// share an opcode/funct3 with the CSR instructions but not the encoding
// space itself: funct3 == 000 never means "CSR instruction"). WFI shares
// this space too; it's treated as a NOP (a legal implementation choice
// per the RISC-V spec) since there's no interrupt to wait for yet.
// Anything else here (SFENCE.VMA, or garbage) is undecoded and falls
// through to control_unit.v's illegal-instruction default.
// ---------------------------------------------------------------------------
`define SYS_IMM_ECALL  12'h000
`define SYS_IMM_EBREAK 12'h001
`define SYS_IMM_MRET   12'h302
`define SYS_IMM_WFI    12'h105

// ---------------------------------------------------------------------------
// Machine-mode exception cause codes (mcause, bit31=0 - these are all
// synchronous exceptions, never interrupts, since no interrupt source
// exists yet).
// ---------------------------------------------------------------------------
`define CAUSE_INSTR_MISALIGNED 32'd0
`define CAUSE_ILLEGAL_INSTR    32'd2
`define CAUSE_BREAKPOINT       32'd3
`define CAUSE_LOAD_MISALIGNED  32'd4
`define CAUSE_STORE_MISALIGNED 32'd6
`define CAUSE_ECALL_M          32'd11

`endif // RV32I_DEFINES_VH
