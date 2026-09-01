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

`define NOP_INSTR 32'h00000013  // addi x0, x0, 0

`endif // RV32I_DEFINES_VH
