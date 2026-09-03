#!/usr/bin/env python3
"""
golden_model.py - an instruction-level RV32I + Zicsr + M-mode-trap
reference model for Srotas, used as the "golden" side of the lockstep
verification harness (see docs/roadmap.md, Phase 1).

This is deliberately NOT a general-purpose RISC-V simulator: it exists to
reproduce this specific RTL's architectural behavior instruction-by-
instruction, bit for bit, including this design's own simplifications
(mstatus/mtvec/mepc masking, mip/misa/id-register read-only behavior,
illegal-instruction and misaligned-address detection matching
ex_stage_top.v's exact conditions) - not the full RISC-V privileged
spec. Where this model and the RTL disagree, that disagreement is only
meaningful once both are checked against the spec/intent separately;
the comparison in lockstep_compare.py is about catching an RTL bug (or a
model bug) relative to *this* design's intended behavior, not spec
conformance in general.

Usage:
    python3 golden_model.py <program.mem> [--max-steps N] [--out trace.log]

Reads a $readmemh-format .mem file (one 32-bit hex instruction word per
line, matching srotas_processor's IMEM_INIT_FILE format), executes it,
and writes a trace in the same format tb_isa_directed.v's trace dump
uses:
    C <pc_hex8> <rd_dec> <data_hex8>   - a register write
    T <pc_hex8> <cause_dec> <mtval_hex8> - a trap

Execution stops when a JAL/JALR/branch redirects the PC to its own
address (the "spin on self forever" halt idiom every test program in
this repo ends with), or after --max-steps instructions (default
100000), whichever comes first.
"""

import argparse
import sys

MASK32 = 0xFFFFFFFF


def s32(x):
    """Reinterpret a 32-bit unsigned value as signed."""
    x &= MASK32
    return x - (1 << 32) if x & 0x80000000 else x


def u32(x):
    return x & MASK32


def sext(value, bits):
    """Sign-extend a `bits`-wide field to 32 bits."""
    value &= (1 << bits) - 1
    if value & (1 << (bits - 1)):
        value -= 1 << bits
    return u32(value)


# ---------------------------------------------------------------------------
# Opcodes (must match src/common/rv32i_defines.vh)
# ---------------------------------------------------------------------------
OP_LUI, OP_AUIPC, OP_JAL, OP_JALR = 0b0110111, 0b0010111, 0b1101111, 0b1100111
OP_BRANCH, OP_LOAD, OP_STORE = 0b1100011, 0b0000011, 0b0100011
OP_IMM, OP_REG, OP_SYSTEM, OP_MISC_MEM = 0b0010011, 0b0110011, 0b1110011, 0b0001111
OP_AMO = 0b0101111  # A extension: lr.w/sc.w and the nine AMO ops

FUNCT7_MULDIV = 0b0000001  # M extension: shares OP_REG's opcode

# A extension funct5 (instruction[31:27])
AMO_F5_LR, AMO_F5_SC = 0b00010, 0b00011
AMO_F5_SWAP, AMO_F5_ADD = 0b00001, 0b00000
AMO_F5_XOR, AMO_F5_AND, AMO_F5_OR = 0b00100, 0b01100, 0b01000
AMO_F5_MIN, AMO_F5_MAX, AMO_F5_MINU, AMO_F5_MAXU = 0b10000, 0b10100, 0b11000, 0b11100

CAUSE_INSTR_MISALIGNED = 0
CAUSE_ILLEGAL_INSTR = 2
CAUSE_BREAKPOINT = 3
CAUSE_LOAD_MISALIGNED = 4
CAUSE_STORE_MISALIGNED = 6
CAUSE_ECALL_M = 11

CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC = 0x300, 0x301, 0x304, 0x305
CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP = 0x340, 0x341, 0x342, 0x343, 0x344
CSR_ID_REGS = {0xF11, 0xF12, 0xF13, 0xF14}  # mvendorid/marchid/mimpid/mhartid

MISA_VAL = 0x40001101  # base ('I', bit 8) + M (bit 12) + A (bit 0), Phase 2

SYS_IMM_ECALL, SYS_IMM_EBREAK, SYS_IMM_MRET, SYS_IMM_WFI = 0x000, 0x001, 0x302, 0x105


class Trap(Exception):
    def __init__(self, cause, value):
        self.cause = cause
        self.value = value


class GoldenModel:
    def __init__(self, words, mem_bytes=1 << 16):
        self.imem = words
        self.mem = bytearray(mem_bytes)
        self.x = [0] * 32
        self.pc = 0
        self.trace = []

        # CSR state, mirroring csr_file.v's storage exactly (not the
        # full spec-defined register set).
        self.mstatus_mie = 0
        self.mstatus_mpie = 0
        self.mie_bits = 0  # bit0=MSIE, bit1=MTIE, bit2=MEIE
        self.mtvec = 0
        self.mscratch = 0
        self.mepc = 0
        self.mcause = 0
        self.mtval = 0

        # A-extension reservation, mirroring amo_unit.v's storage exactly:
        # one address plus one valid bit.
        self.reservation_valid = False
        self.reservation_addr = 0

    # -- register file (x0 hardwired to 0, like register_file.v) --------
    def rd_reg(self, i):
        return 0 if i == 0 else self.x[i]

    def wr_reg(self, i, v):
        if i != 0:
            self.x[i] = u32(v)

    # -- CSR read/write, mirroring csr_file.v's masking exactly ---------
    def csr_read(self, addr):
        if addr == CSR_MSTATUS:
            return (0b11 << 11) | (self.mstatus_mpie << 7) | (self.mstatus_mie << 3)
        if addr == CSR_MISA:
            return MISA_VAL
        if addr == CSR_MIE:
            meie = (self.mie_bits >> 2) & 1
            mtie = (self.mie_bits >> 1) & 1
            msie = self.mie_bits & 1
            return (meie << 11) | (mtie << 7) | (msie << 3)
        if addr == CSR_MTVEC:
            return self.mtvec
        if addr == CSR_MSCRATCH:
            return self.mscratch
        if addr == CSR_MEPC:
            return self.mepc
        if addr == CSR_MCAUSE:
            return self.mcause
        if addr == CSR_MTVAL:
            return self.mtval
        if addr == CSR_MIP:
            return 0
        if addr in CSR_ID_REGS:
            return 0
        return 0  # unimplemented address: reads 0, like csr_file.v's default

    def csr_write(self, addr, value):
        value = u32(value)
        if addr == CSR_MSTATUS:
            self.mstatus_mie = (value >> 3) & 1
            self.mstatus_mpie = (value >> 7) & 1
        elif addr == CSR_MIE:
            msie = (value >> 3) & 1
            mtie = (value >> 7) & 1
            meie = (value >> 11) & 1
            self.mie_bits = msie | (mtie << 1) | (meie << 2)
        elif addr == CSR_MTVEC:
            self.mtvec = value & ~0x3 & MASK32  # Direct mode only
        elif addr == CSR_MSCRATCH:
            self.mscratch = value
        elif addr == CSR_MEPC:
            self.mepc = value & ~0x3 & MASK32
        elif addr == CSR_MCAUSE:
            self.mcause = value
        elif addr == CSR_MTVAL:
            self.mtval = value
        # misa / mip / the ID registers / any unimplemented address:
        # read-only here, writes silently dropped.

    def trap_entry(self, pc, cause, value):
        self.mepc = pc & ~0x3 & MASK32
        self.mcause = u32(cause)
        self.mtval = u32(value)
        self.mstatus_mpie = self.mstatus_mie
        self.mstatus_mie = 0

    def mret(self):
        self.mstatus_mie = self.mstatus_mpie
        self.mstatus_mpie = 1

    # -- memory, little-endian, matching data_memory.v -------------------
    def load_mem(self, addr, funct3):
        a = addr & (len(self.mem) - 1)
        if funct3 == 0b000:  # LB
            return sext(self.mem[a], 8)
        if funct3 == 0b001:  # LH
            v = self.mem[a] | (self.mem[(a + 1) & (len(self.mem) - 1)] << 8)
            return sext(v, 16)
        if funct3 == 0b010:  # LW
            m = self.mem
            n = len(m) - 1
            return u32(m[a] | (m[(a + 1) & n] << 8) | (m[(a + 2) & n] << 16) | (m[(a + 3) & n] << 24))
        if funct3 == 0b100:  # LBU
            return self.mem[a]
        if funct3 == 0b101:  # LHU
            return self.mem[a] | (self.mem[(a + 1) & (len(self.mem) - 1)] << 8)
        return 0

    def store_mem(self, addr, funct3, value):
        n = len(self.mem) - 1
        a = addr & n
        value = u32(value)
        if funct3 == 0b000:  # SB
            self.mem[a] = value & 0xFF
        elif funct3 == 0b001:  # SH
            self.mem[a] = value & 0xFF
            self.mem[(a + 1) & n] = (value >> 8) & 0xFF
        elif funct3 == 0b010:  # SW
            self.mem[a] = value & 0xFF
            self.mem[(a + 1) & n] = (value >> 8) & 0xFF
            self.mem[(a + 2) & n] = (value >> 16) & 0xFF
            self.mem[(a + 3) & n] = (value >> 24) & 0xFF

    @staticmethod
    def mem_misaligned(addr, funct3):
        if funct3 == 0b010:  # word
            return (addr & 0x3) != 0
        if funct3 in (0b001, 0b101):  # half, half-unsigned
            return (addr & 0x1) != 0
        return False  # byte accesses are never misaligned

    # -- fetch + decode + execute one instruction ------------------------
    def step(self):
        pc = self.pc
        idx = pc >> 2
        if idx >= len(self.imem):
            raise IndexError(f"PC 0x{pc:08x} (word {idx}) is past the end of "
                              f"the loaded program ({len(self.imem)} words) - "
                              f"likely a bad redirect target, not a real halt")
        instr = self.imem[idx]

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F
        imm_i = sext(instr >> 20, 12)
        imm_s = sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = sext(
            (((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11)
            | (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1),
            13,
        )
        imm_u = instr & 0xFFFFF000
        imm_j = sext(
            (((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12)
            | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1),
            21,
        )
        csr_addr = (instr >> 20) & 0xFFF

        rs1v, rs2v = self.rd_reg(rs1), self.rd_reg(rs2)

        result = None       # value to write to rd, if reg_write
        reg_write = False
        next_pc = u32(pc + 4)

        try:
            if opcode == OP_LUI:
                result, reg_write = imm_u, True
            elif opcode == OP_AUIPC:
                result, reg_write = u32(pc + imm_u), True
            elif opcode == OP_JAL:
                target = u32(pc + imm_j)
                if target & 0x2:
                    raise Trap(CAUSE_INSTR_MISALIGNED, target)
                result, reg_write = u32(pc + 4), True
                next_pc = target
            elif opcode == OP_JALR:
                target = u32((rs1v + imm_i) & ~1)
                if target & 0x2:
                    raise Trap(CAUSE_INSTR_MISALIGNED, target)
                result, reg_write = u32(pc + 4), True
                next_pc = target
            elif opcode == OP_BRANCH:
                a, b = s32(rs1v), s32(rs2v)
                taken = {
                    0b000: rs1v == rs2v,
                    0b001: rs1v != rs2v,
                    0b100: a < b,
                    0b101: a >= b,
                    0b110: rs1v < rs2v,
                    0b111: rs1v >= rs2v,
                }.get(funct3, False)
                if taken:
                    target = u32(pc + imm_b)
                    if target & 0x2:
                        raise Trap(CAUSE_INSTR_MISALIGNED, target)
                    next_pc = target
            elif opcode == OP_LOAD:
                addr = u32(rs1v + imm_i)
                if self.mem_misaligned(addr, funct3):
                    raise Trap(CAUSE_LOAD_MISALIGNED, addr)
                result, reg_write = self.load_mem(addr, funct3), True
            elif opcode == OP_STORE:
                addr = u32(rs1v + imm_s)
                if self.mem_misaligned(addr, funct3):
                    raise Trap(CAUSE_STORE_MISALIGNED, addr)
                self.store_mem(addr, funct3, rs2v)
                if self.reservation_valid and addr == self.reservation_addr:
                    self.reservation_valid = False  # any other write to it invalidates it
            elif opcode == OP_AMO:
                funct5 = (funct7 >> 2) & 0x1F
                addr = rs1v  # no immediate in this encoding - address is rs1 alone
                # lr.w never sets mem_write (matches control_unit.v), so its
                # misalignment reports LOAD_MISALIGNED; sc.w and the nine
                # regular AMOs all set mem_write, reporting STORE_MISALIGNED -
                # mirroring ex_stage_top.v's mem_write ? STORE : LOAD choice.
                if self.mem_misaligned(addr, 0b010):
                    cause = CAUSE_LOAD_MISALIGNED if funct5 == AMO_F5_LR else CAUSE_STORE_MISALIGNED
                    raise Trap(cause, addr)
                old = self.load_mem(addr, 0b010)
                if funct5 == AMO_F5_LR:
                    self.reservation_valid = True
                    self.reservation_addr = addr
                    result, reg_write = old, True
                elif funct5 == AMO_F5_SC:
                    success = self.reservation_valid and self.reservation_addr == addr
                    self.reservation_valid = False  # sc.w always clears it, success or fail
                    if success:
                        self.store_mem(addr, 0b010, rs2v)
                    result, reg_write = (0 if success else 1), True
                else:
                    new = self._amo_alu(funct5, old, rs2v)
                    self.store_mem(addr, 0b010, new)
                    if self.reservation_valid and self.reservation_addr == addr:
                        self.reservation_valid = False
                    result, reg_write = old, True
            elif opcode == OP_IMM:
                result, reg_write = self._alu_imm(funct3, funct7, rs1v, imm_i), True
            elif opcode == OP_REG:
                if funct7 == FUNCT7_MULDIV:
                    result, reg_write = self._muldiv(funct3, rs1v, rs2v), True
                else:
                    result, reg_write = self._alu_reg(funct3, funct7, rs1v, rs2v), True
            elif opcode == OP_SYSTEM:
                if funct3 != 0:
                    result, reg_write = self._csr_instr(funct3, csr_addr, rs1, rs1v), True
                elif csr_addr == SYS_IMM_ECALL:
                    raise Trap(CAUSE_ECALL_M, 0)
                elif csr_addr == SYS_IMM_EBREAK:
                    raise Trap(CAUSE_BREAKPOINT, 0)
                elif csr_addr == SYS_IMM_MRET:
                    self.mret()
                    next_pc = self.mepc
                elif csr_addr == SYS_IMM_WFI:
                    pass  # legal NOP
                else:
                    raise Trap(CAUSE_ILLEGAL_INSTR, 0)
            elif opcode == OP_MISC_MEM:
                pass  # FENCE / FENCE.I: no-op (no caches, single hart)
            else:
                raise Trap(CAUSE_ILLEGAL_INSTR, 0)

        except Trap as t:
            self.trap_entry(pc, t.cause, t.value)
            self.trace.append(f"T {pc:08x} {t.cause} {t.value & MASK32:08x}")
            self.pc = self.mtvec
            return True

        if reg_write and rd != 0:
            self.wr_reg(rd, result)
            self.trace.append(f"C {pc:08x} {rd} {u32(result):08x}")

        halted = next_pc == pc
        self.pc = next_pc
        return not halted

    def _alu_imm(self, funct3, funct7, a, imm):
        # funct7 is instruction[31:25] regardless of format, so it carries
        # the SRLI/SRAI selector for I-type shifts the same way it carries
        # SUB/ADD and SRL/SRA for R-type - same bit position, same meaning.
        shamt = imm & 0x1F
        is_sra = (funct7 >> 5) & 1
        return {
            0b000: u32(a + imm),
            0b010: 1 if s32(a) < s32(imm) else 0,
            0b011: 1 if u32(a) < u32(imm) else 0,
            0b100: u32(a ^ imm),
            0b110: u32(a | imm),
            0b111: u32(a & imm),
            0b001: u32(a << shamt),
            0b101: u32(s32(a) >> shamt) if is_sra else u32(a >> shamt),
        }[funct3]

    def _alu_reg(self, funct3, funct7, a, b):
        sub_or_sra = (funct7 >> 5) & 1
        shamt = b & 0x1F
        return {
            0b000: u32(a - b) if sub_or_sra else u32(a + b),
            0b001: u32(a << shamt),
            0b010: 1 if s32(a) < s32(b) else 0,
            0b011: 1 if u32(a) < u32(b) else 0,
            0b100: u32(a ^ b),
            0b101: u32(s32(a) >> shamt) if sub_or_sra else u32(a >> shamt),
            0b110: u32(a | b),
            0b111: u32(a & b),
        }[funct3]

    def _muldiv(self, funct3, a, b):
        # RV32M. Deliberately an if/elif chain, not the dict-literal style
        # _alu_reg/_alu_imm use above - a dict literal evaluates every
        # branch eagerly, which would raise ZeroDivisionError on DIV x,0
        # before the intended (spec-mandated, non-trapping) result could
        # ever be selected. Python's // and % floor toward negative
        # infinity; RISC-V truncates toward zero, so the divide/remainder
        # cases compute on magnitudes and fix the sign explicitly rather
        # than relying on Python's operators directly.
        if funct3 == 0b000:  # MUL: low 32 bits, sign-independent
            return u32(s32(a) * s32(b))
        if funct3 == 0b001:  # MULH: high 32 bits, signed x signed
            return u32((s32(a) * s32(b)) >> 32)
        if funct3 == 0b010:  # MULHSU: high 32 bits, signed x unsigned
            return u32((s32(a) * u32(b)) >> 32)
        if funct3 == 0b011:  # MULHU: high 32 bits, unsigned x unsigned
            return u32((u32(a) * u32(b)) >> 32)
        if funct3 == 0b100:  # DIV
            sa, sb = s32(a), s32(b)
            if sb == 0:
                return MASK32
            if sa == -(1 << 31) and sb == -1:
                return u32(-(1 << 31))
            q = abs(sa) // abs(sb)
            return u32(-q if (sa < 0) != (sb < 0) else q)
        if funct3 == 0b101:  # DIVU
            if b == 0:
                return MASK32
            return u32(a // b)
        if funct3 == 0b110:  # REM: sign follows the dividend
            sa, sb = s32(a), s32(b)
            if sb == 0:
                return u32(sa)
            if sa == -(1 << 31) and sb == -1:
                return 0
            r = abs(sa) % abs(sb)
            return u32(-r if sa < 0 else r)
        # 0b111: REMU
        if b == 0:
            return u32(a)
        return u32(a % b)

    def _amo_alu(self, funct5, old, operand):
        # RV32A's nine regular ops (excludes lr.w/sc.w, handled by the
        # caller directly since they aren't a simple old-OP-operand
        # reduction).
        if funct5 == AMO_F5_SWAP:
            return u32(operand)
        if funct5 == AMO_F5_ADD:
            return u32(old + operand)
        if funct5 == AMO_F5_XOR:
            return u32(old ^ operand)
        if funct5 == AMO_F5_AND:
            return u32(old & operand)
        if funct5 == AMO_F5_OR:
            return u32(old | operand)
        if funct5 == AMO_F5_MIN:
            return old if s32(old) < s32(operand) else operand
        if funct5 == AMO_F5_MAX:
            return old if s32(old) > s32(operand) else operand
        if funct5 == AMO_F5_MINU:
            return old if old < operand else operand
        # AMO_F5_MAXU
        return old if old > operand else operand

    def _csr_instr(self, funct3, addr, rs1_field, rs1v):
        use_imm = bool(funct3 & 0b100)
        op = funct3 & 0b011
        operand = rs1_field if use_imm else rs1v
        old = self.csr_read(addr)
        if op == 0b01:
            new = operand
        elif op == 0b10:
            new = old | operand
        elif op == 0b11:
            new = old & ~operand & MASK32
        else:
            new = old
        self.csr_write(addr, new)
        return old

    def run(self, max_steps=100000):
        for _ in range(max_steps):
            if not self.step():
                break
        return self.trace


def load_mem_file(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mem_file")
    ap.add_argument("--max-steps", type=int, default=100000)
    ap.add_argument("--out", default=None, help="write trace here instead of stdout")
    args = ap.parse_args()

    model = GoldenModel(load_mem_file(args.mem_file))
    trace = model.run(args.max_steps)

    out = open(args.out, "w") if args.out else sys.stdout
    for line in trace:
        print(line, file=out)
    if args.out:
        out.close()


if __name__ == "__main__":
    main()
