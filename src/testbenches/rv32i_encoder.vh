// ============================================================================
// File: rv32i_encoder.vh
// Purpose: Verilog functions that assemble RV32I machine code from mnemonic
//          arguments, for use inside testbenches. `include this file inside
//          the module/program that builds a test instruction array - it is
//          simulation-only tooling, never included by the DUT itself.
//
// Immediates are passed as full 32-bit (sign-extended where applicable)
// values; each encoder slices out only the bits the instruction format
// actually stores.
// ============================================================================

`ifndef RV32I_ENCODER_VH
`define RV32I_ENCODER_VH

`include "rv32i_defines.vh"

function [31:0] r_type;
    input [6:0] funct7;
    input [4:0] rs2, rs1;
    input [2:0] funct3;
    input [4:0] rd;
    input [6:0] opcode;
    r_type = {funct7, rs2, rs1, funct3, rd, opcode};
endfunction

function [31:0] i_type;
    input [31:0] imm;
    input [4:0] rs1;
    input [2:0] funct3;
    input [4:0] rd;
    input [6:0] opcode;
    i_type = {imm[11:0], rs1, funct3, rd, opcode};
endfunction

function [31:0] s_type;
    input [31:0] imm;
    input [4:0] rs2, rs1;
    input [2:0] funct3;
    input [6:0] opcode;
    s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
endfunction

function [31:0] b_type;
    input [31:0] imm;
    input [4:0] rs2, rs1;
    input [2:0] funct3;
    input [6:0] opcode;
    b_type = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
endfunction

function [31:0] u_type;
    input [31:0] imm;
    input [4:0] rd;
    input [6:0] opcode;
    u_type = {imm[31:12], rd, opcode};
endfunction

function [31:0] j_type;
    input [31:0] imm;
    input [4:0] rd;
    input [6:0] opcode;
    j_type = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
endfunction

// --- R-type mnemonics --------------------------------------------------
function [31:0] I_ADD;  input [4:0] rd, rs1, rs2; I_ADD  = r_type(7'b0000000, rs2, rs1, 3'b000, rd, `OP_REG); endfunction
function [31:0] I_SUB;  input [4:0] rd, rs1, rs2; I_SUB  = r_type(7'b0100000, rs2, rs1, 3'b000, rd, `OP_REG); endfunction
function [31:0] I_SLL;  input [4:0] rd, rs1, rs2; I_SLL  = r_type(7'b0000000, rs2, rs1, 3'b001, rd, `OP_REG); endfunction
function [31:0] I_SLT;  input [4:0] rd, rs1, rs2; I_SLT  = r_type(7'b0000000, rs2, rs1, 3'b010, rd, `OP_REG); endfunction
function [31:0] I_SLTU; input [4:0] rd, rs1, rs2; I_SLTU = r_type(7'b0000000, rs2, rs1, 3'b011, rd, `OP_REG); endfunction
function [31:0] I_XOR;  input [4:0] rd, rs1, rs2; I_XOR  = r_type(7'b0000000, rs2, rs1, 3'b100, rd, `OP_REG); endfunction
function [31:0] I_SRL;  input [4:0] rd, rs1, rs2; I_SRL  = r_type(7'b0000000, rs2, rs1, 3'b101, rd, `OP_REG); endfunction
function [31:0] I_SRA;  input [4:0] rd, rs1, rs2; I_SRA  = r_type(7'b0100000, rs2, rs1, 3'b101, rd, `OP_REG); endfunction
function [31:0] I_OR;   input [4:0] rd, rs1, rs2; I_OR   = r_type(7'b0000000, rs2, rs1, 3'b110, rd, `OP_REG); endfunction
function [31:0] I_AND;  input [4:0] rd, rs1, rs2; I_AND  = r_type(7'b0000000, rs2, rs1, 3'b111, rd, `OP_REG); endfunction

// --- I-type ALU mnemonics ----------------------------------------------
function [31:0] I_ADDI;  input [4:0] rd, rs1; input [31:0] imm; I_ADDI  = i_type(imm, rs1, 3'b000, rd, `OP_IMM); endfunction
function [31:0] I_SLTI;  input [4:0] rd, rs1; input [31:0] imm; I_SLTI  = i_type(imm, rs1, 3'b010, rd, `OP_IMM); endfunction
function [31:0] I_SLTIU; input [4:0] rd, rs1; input [31:0] imm; I_SLTIU = i_type(imm, rs1, 3'b011, rd, `OP_IMM); endfunction
function [31:0] I_XORI;  input [4:0] rd, rs1; input [31:0] imm; I_XORI  = i_type(imm, rs1, 3'b100, rd, `OP_IMM); endfunction
function [31:0] I_ORI;   input [4:0] rd, rs1; input [31:0] imm; I_ORI   = i_type(imm, rs1, 3'b110, rd, `OP_IMM); endfunction
function [31:0] I_ANDI;  input [4:0] rd, rs1; input [31:0] imm; I_ANDI  = i_type(imm, rs1, 3'b111, rd, `OP_IMM); endfunction
function [31:0] I_SLLI;  input [4:0] rd, rs1; input [4:0] shamt; I_SLLI = i_type({7'b0000000, shamt}, rs1, 3'b001, rd, `OP_IMM); endfunction
function [31:0] I_SRLI;  input [4:0] rd, rs1; input [4:0] shamt; I_SRLI = i_type({7'b0000000, shamt}, rs1, 3'b101, rd, `OP_IMM); endfunction
function [31:0] I_SRAI;  input [4:0] rd, rs1; input [4:0] shamt; I_SRAI = i_type({7'b0100000, shamt}, rs1, 3'b101, rd, `OP_IMM); endfunction

// --- U-type --------------------------------------------------------------
function [31:0] I_LUI;   input [4:0] rd; input [31:0] imm; I_LUI   = u_type(imm, rd, `OP_LUI);   endfunction
function [31:0] I_AUIPC; input [4:0] rd; input [31:0] imm; I_AUIPC = u_type(imm, rd, `OP_AUIPC); endfunction

// --- Loads / Stores --------------------------------------------------------
function [31:0] I_LB;  input [4:0] rd, rs1; input [31:0] imm; I_LB  = i_type(imm, rs1, 3'b000, rd, `OP_LOAD); endfunction
function [31:0] I_LH;  input [4:0] rd, rs1; input [31:0] imm; I_LH  = i_type(imm, rs1, 3'b001, rd, `OP_LOAD); endfunction
function [31:0] I_LW;  input [4:0] rd, rs1; input [31:0] imm; I_LW  = i_type(imm, rs1, 3'b010, rd, `OP_LOAD); endfunction
function [31:0] I_LBU; input [4:0] rd, rs1; input [31:0] imm; I_LBU = i_type(imm, rs1, 3'b100, rd, `OP_LOAD); endfunction
function [31:0] I_LHU; input [4:0] rd, rs1; input [31:0] imm; I_LHU = i_type(imm, rs1, 3'b101, rd, `OP_LOAD); endfunction

// store(value_reg, base_reg, imm) -- mem[base_reg + imm] = value_reg
function [31:0] I_SB; input [4:0] rs2, rs1; input [31:0] imm; I_SB = s_type(imm, rs2, rs1, 3'b000, `OP_STORE); endfunction
function [31:0] I_SH; input [4:0] rs2, rs1; input [31:0] imm; I_SH = s_type(imm, rs2, rs1, 3'b001, `OP_STORE); endfunction
function [31:0] I_SW; input [4:0] rs2, rs1; input [31:0] imm; I_SW = s_type(imm, rs2, rs1, 3'b010, `OP_STORE); endfunction

// --- Branches: (rs1, rs2, imm) -------------------------------------------
function [31:0] I_BEQ;  input [4:0] rs1, rs2; input [31:0] imm; I_BEQ  = b_type(imm, rs2, rs1, 3'b000, `OP_BRANCH); endfunction
function [31:0] I_BNE;  input [4:0] rs1, rs2; input [31:0] imm; I_BNE  = b_type(imm, rs2, rs1, 3'b001, `OP_BRANCH); endfunction
function [31:0] I_BLT;  input [4:0] rs1, rs2; input [31:0] imm; I_BLT  = b_type(imm, rs2, rs1, 3'b100, `OP_BRANCH); endfunction
function [31:0] I_BGE;  input [4:0] rs1, rs2; input [31:0] imm; I_BGE  = b_type(imm, rs2, rs1, 3'b101, `OP_BRANCH); endfunction
function [31:0] I_BLTU; input [4:0] rs1, rs2; input [31:0] imm; I_BLTU = b_type(imm, rs2, rs1, 3'b110, `OP_BRANCH); endfunction
function [31:0] I_BGEU; input [4:0] rs1, rs2; input [31:0] imm; I_BGEU = b_type(imm, rs2, rs1, 3'b111, `OP_BRANCH); endfunction

// --- Jumps -----------------------------------------------------------------
function [31:0] I_JAL;  input [4:0] rd; input [31:0] imm;              I_JAL  = j_type(imm, rd, `OP_JAL);           endfunction
function [31:0] I_JALR; input [4:0] rd, rs1; input [31:0] imm;         I_JALR = i_type(imm, rs1, 3'b000, rd, `OP_JALR); endfunction

`define I_NOP 32'h00000013

`endif // RV32I_ENCODER_VH
