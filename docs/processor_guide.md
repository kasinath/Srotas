# The Srotas Processor: A Complete Guide

This document walks through every module in the Srotas RISC-V processor,
stage by stage, explaining not just what each piece does but *why it exists*
and why it's built the way it is. It replaces the original day-by-day build
log with a single reference that's kept up to date as the processor grows —
see [`docs/roadmap.md`](roadmap.md) for where it's headed next.

If you just want a quick architectural overview and the datapath diagram,
see the "Architecture" section of the top-level `README.md` — this document
goes deeper, module by module, for anyone extending or debugging the design.

## 1. The big picture

Srotas implements the **RV32I base integer ISA** — the smallest complete
RISC-V instruction set, 47 instructions covering arithmetic, logic, shifts,
loads/stores, branches, and jumps — plus **Zicsr** (the six CSR
read/modify/write instructions) and **M-mode exception handling**
(`ecall`/`ebreak`/`mret`, illegal instructions, and misaligned addresses),
as a **classic 5-stage in-order pipeline**:

```
IF (Fetch) -> ID (Decode) -> EX (Execute) -> MEM (Memory) -> WB (Writeback)
```

### Why pipeline at all?

Without pipelining, a processor fetches an instruction, decodes it,
executes it, accesses memory, and writes back the result — one instruction
completely finished before the next one starts. Pipelining overlaps these
steps: while one instruction is being decoded, the next is already being
fetched. Five instructions can be "in flight" at once, one per stage, so in
steady state the processor retires one instruction per clock cycle instead
of one every five cycles.

The cost of this overlap is **hazards**: cases where one instruction's
result is needed before it's actually ready, or where a branch changes
which instructions should even be in the pipeline in the first place.
Sections 6 and 7 cover how Srotas detects and resolves these.

### Why a separate module per stage, plus a "_top" wrapper?

Each stage directory (`src/if_stage/`, `src/id_stage/`, etc.) contains small
single-purpose modules (a register, a decoder, an ALU) plus one
`..._stage_top.v` that wires them together and exposes a clean interface to
the rest of the pipeline. This mirrors the datapath itself: a stage's
internal wiring is that stage's private concern, and only its stage boundary
signals matter to its neighbors. It also means each piece can be tested and
reasoned about independently — the ALU doesn't know that it's part of a
pipeline; it just computes a function of two operands.

### Why a shared `rv32i_defines.vh`?

`src/common/rv32i_defines.vh` centralizes every opcode, ALU-op, immediate
format, and load/store-width encoding used anywhere in the design. The
control unit assigns `alu_op = `ALU_SUB``; the ALU checks
`` alu_op == `ALU_SUB` ``. If those two modules each hard-coded their own
`4'b0001` for "subtract," a typo in either one would silently break the
processor with no compile-time warning. A single shared header makes that
class of bug impossible — the two modules can never disagree about what a
value means.

## 2. Instruction formats

RV32I instructions are all 32 bits, but the meaning of those bits depends on
the format, determined by the 7-bit opcode:

```
R-type (register-register):
 31        25 24    20 19    15 14  12 11     7 6         0
├───────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│  funct7   │   rs2   │   rs1   │funct3 │   rd    │ opcode  │
└───────────┴─────────┴─────────┴───────┴─────────┴─────────┘

I-type (immediate arithmetic / loads / JALR):
 31            20 19    15 14  12 11     7 6         0
├────────────────┼─────────┼───────┼─────────┼─────────┤
│   imm[11:0]    │   rs1   │funct3 │   rd    │ opcode  │
└────────────────┴─────────┴───────┴─────────┴─────────┘

S-type (stores):
 31        25 24    20 19    15 14  12 11     7 6         0
├───────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│ imm[11:5] │   rs2   │   rs1   │funct3 │imm[4:0] │ opcode  │
└───────────┴─────────┴─────────┴───────┴─────────┴─────────┘

B-type (branches):
 31       25 24    20 19    15 14  12 11     8  7       6         0
├────────────┼───────┼─────────┼───────┼────────┼───────┼───────┤
│imm[12|10:5]│  rs2  │   rs1   │funct3 │imm[4:1]│imm[11]│opcode │
└────────────┴───────┴─────────┴───────┴────────┴───────┴───────┘

U-type (LUI, AUIPC):
 31                          12 11     7 6         0
├──────────────────────────────┼─────────┼─────────┤
│         imm[31:12]           │   rd    │ opcode  │
└──────────────────────────────┴─────────┴─────────┘

J-type (JAL):
 31                                     12 11     7 6         0
├───────────────────────────────────────┼──────────┼─────────┤
│  imm[20|10:1|11|19:12]                 │   rd    │ opcode  │
└───────────────────────────────────────┴──────────┴─────────┘
```

B-type and J-type immediates always have their least-significant bit forced
to `0` — branch/jump targets are always 2-byte aligned at minimum, so that
bit is reused to encode more range instead of being wasted. This is why
`sign_extend.v` (Section 4) hard-wires a `1'b0` at the bottom of those two
formats rather than reading it from the instruction.

## 3. IF — Instruction Fetch

**Job:** produce the address of the next instruction, fetch it, and hand it
to ID.

- **`pc_register.v`** — the Program Counter. A single 32-bit register,
  reset to `0x00000000`, that holds the address currently being fetched. It
  only has one piece of extra behavior: `pc_write_en`. When a load-use
  hazard is detected (Section 6), the PC must *not* advance, so the same
  instruction is presented again next cycle instead of skipping ahead while
  the pipeline is stalled.

- **`instruction_memory.v`** — a ROM: address in, 32-bit instruction word
  out, combinationally. Real hardware would back this with a cache; in
  simulation it's initialized via `$readmemh` from `IMEM_INIT_FILE`.

- **`if_id_register.v`** — the pipeline register carrying the fetched
  instruction (plus its PC and PC+4) into ID. It has two independent
  control inputs, not one, because stall and flush are different actions
  with different intents:
  - **`write_en = 0` (stall)**: freeze the register's contents. Used during
    a load-use hazard — the instruction in ID needs to stay in ID for one
    more cycle while the load ahead of it produces its result.
  - **`flush = 1`**: force the register to a NOP (`` `NOP_INSTR ``, i.e.
    `addi x0, x0, 0` — an instruction that touches no visible state). Used
    when a branch or jump resolved in EX turns out to have been taken,
    which means the instruction currently sitting in IF was fetched down
    the wrong path and must never be allowed to execute.
  - If both fire in the same cycle, flush wins — a squash always overrides
    a stall, since there's no point preserving an instruction that's about
    to be thrown away anyway.

- **`if_stage_top.v`** — computes `pc_next` (branch/jump target from EX if
  `branch_redirect` is asserted, otherwise `pc + 4`) and wires the three
  modules above together.

## 4. ID — Instruction Decode

**Job:** split the instruction into its fields, read the two source
registers, generate every control signal the rest of the pipeline needs,
and build the sign-extended immediate.

- **`register_file.v`** — 32 general-purpose registers, `x0`–`x31`. Two
  things about it are easy to get wrong and worth calling out:
  - **`x0` is hardwired to zero.** It isn't backed by storage at all (the
    `registers` array is declared `[1:31]`) — reads of `x0` are muxed to a
    constant `0`, and writes to it are simply ignored. This isn't an
    implementation detail; it's architectural. RISC-V code relies on `x0`
    always reading zero (e.g. `beq x0, x0, label` as an unconditional
    branch, or `addi x0, x0, 0` as a NOP).
  - **Same-cycle write-then-read bypass.** Reads are asynchronous
    (combinational), and writes happen on the clock edge — but if WB is
    writing register `R` in the *same* cycle that ID is reading `R`, a plain
    synchronous-write memory would hand ID the *stale* pre-write value, one
    cycle too late. `register_file.v` compares the write address against
    both read addresses combinationally and forwards the incoming write
    data directly to the read port when they match. This exact case arises
    whenever a producer instruction is exactly three instructions ahead of
    a consumer (producer in WB while consumer is in ID) — the one RAW
    hazard distance that's *too far* for the EX-stage forwarding muxes
    (Section 6) to reach, because by the time the consumer is in ID, EX-stage
    forwarding has already moved on. See test section F in
    `tb_isa_directed.v` for the case this exists to fix.

- **`sign_extend.v`** — takes the raw instruction and an `imm_format`
  selector (chosen by the control unit based on opcode) and produces the
  correct 32-bit sign-extended immediate for whichever of the five formats
  applies. Getting sign extension right matters: zero-extending a negative
  I-type immediate like `0xFFF` (-1) would produce `4095` instead of `-1`,
  silently corrupting every negative offset and negative immediate in a
  program.

- **`control_unit.v`** — the decode logic. Pure combinational function of
  `opcode`/`funct3`/`funct7`, producing every signal downstream stages need:
  `reg_write`, `alu_src_a` (register / PC / zero — see below), `alu_src_b`
  (register / immediate), `alu_op`, `mem_read`, `mem_write`, `result_src`
  (ALU / memory / link — Section 8), `branch`, `jump`, `is_jalr`, and
  `imm_format`. A few choices worth explaining:
  - **`alu_src_a` has three options, not two.** Most instructions use `rs1`
    as the ALU's first operand, but `LUI` needs a plain `0` (it just wants
    the sign-extended immediate to pass through unchanged via `0 + imm`)
    and `AUIPC` needs the current `PC` (it computes `PC + imm`, a
    PC-relative address). Rather than special-casing those two
    instructions elsewhere, the ALU's first input is just made
    three-way-selectable, so the same ALU/adder handles all three cases.
  - **`result_src` decides what gets written back**, not the ALU. Most
    instructions write the ALU result; loads write memory data; `JAL`/
    `JALR` write the *link value* (`PC+4`, the return address) instead of
    anything the ALU computed. This selection is deferred all the way to
    WB (Section 8), since that's genuinely where "what value ends up in
    the register" is decided.
  - **Unrecognized opcodes fall through to the `default` case**, which
    leaves every control signal at its safe, no-side-effect default
    (`reg_write = 0`, `mem_read/write = 0`, etc.) — an unimplemented
    instruction behaves as an inert NOP rather than corrupting state,
    which matters because RV32I doesn't include compressed or
    M-extension opcodes, and encountering one shouldn't silently
    misbehave.
  - **CSR instructions** (`csrrw`/`csrrs`/`csrrc` and their `_i` immediate
    forms, all under `OP_SYSTEM`) decode into `result_src = RESULT_CSR`
    plus two CSR-specific signals: `csr_op` (`funct3[1:0]`, directly
    giving write/set/clear regardless of register-vs-immediate form) and
    `csr_use_imm` (`funct3[2]`, 1 for the `_i` forms).
  - **`ecall`/`ebreak`/`mret`** share `OP_SYSTEM` with the CSR
    instructions but are distinguished by `funct3 == 000` together with
    the `imm[11:0]` field (the same bits as a CSR address, reused here
    for their fixed bit patterns: `0x000`/`0x001`/`0x302`). `wfi`
    (`0x105`) decodes as a deliberate NOP — a legal implementation choice
    per the RISC-V spec, since there's no interrupt yet to wait for.
    Anything else in this space (`sfence.vma`, or garbage) sets
    `illegal`, alongside the outer `default` case for any entirely
    unrecognized opcode. All four of `ecall`/`ebreak`/`mret`/`illegal` are
    only *classified* here — control_unit.v has no notion of a PC
    redirect or squash; that happens in EX (Section 5), the same way a
    branch's `taken`/`not-taken` classification here doesn't resolve the
    branch itself.
  - **`FENCE`/`FENCE.I`** (`OP_MISC_MEM`, base RV32I and Zifencei
    respectively) get their own case that leaves every signal at its
    default and does *not* set `illegal` — a single in-order hart with no
    caches has no memory reordering to fence and no instruction cache to
    invalidate, so both are true no-ops here, not merely unimplemented.
    This closed a real gap rather than adding a cosmetic one: `FENCE` is
    base-ISA, so before this opcode had its own case it fell into the
    `default` branch below and would have wrongly trapped as illegal — a
    compliant base RV32I instruction excepting is a correctness bug, not
    a scope limitation.

- **`id_ex_register.v`** — the pipeline register into EX. Its `flush`
  behavior is more selective than `if_id_register`'s: it zeros out only the
  *control* signals (`reg_write`, `mem_read`, `mem_write`, `branch`,
  `jump`, `is_jalr`, `result_src`, `csr_op`, `ecall`, `ebreak`, `mret`,
  `illegal`) and leaves data fields (registers, immediate, PC,
  `csr_use_imm`, `csr_addr`) untouched. A "bubble" only needs to look like
  a NOP to the rest of the pipeline — and an instruction is
  architecturally inert the moment none of its control signals can cause
  a write, a memory access, or a redirect, regardless of what stale data
  bits happen to still be sitting in the register. This one register
  handles two different reasons to flush: a load-use stall bubble, and
  squashing whatever was decoded down the wrong path of a branch — and,
  as of the trap controller (Section 5), a third: a squashed `ecall` must
  never be allowed to fire just because it happened to be sitting on a
  mispredicted path.

- **`id_stage_top.v`** — ties the above together and is also where the
  register file's write port gets connected. Note that the write address/
  data/enable driving the register file come from `wb_reg_write`/
  `wb_rd_addr`/`wb_rd_data` — signals fed back from the *WB* stage of a
  *different, later* instruction, routed in from the top level. This is the
  standard "the register file straddles ID and WB" structure of every
  textbook pipeline diagram: one instruction's decode-time read and a
  different, earlier instruction's writeback-time write happen to the same
  physical register file in the same cycle.

## 5. EX — Execute

**Job:** do the actual computation, resolve forwarding, and decide whether
a branch or jump changes control flow.

- **`alu.v`** — the arithmetic/logic core. One `case` on a 4-bit `alu_op`
  covers all of `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND`. It exposes a
  `zero` flag (`result == 0`) and nothing else — no separate carry/overflow
  outputs — because nothing downstream needs them: RV32I doesn't trap on
  arithmetic overflow, so `zero` is the only ALU-derived signal branch
  resolution needs (see next module).

- **`branch_unit.v`** — resolves every conditional branch and computes
  redirect targets for taken branches, `JAL`, and `JALR`. Its central
  design decision is that it does **not** contain its own comparator: the
  control unit already steers `alu_op` to `SUB` for `BEQ`/`BNE`, `SLT` for
  `BLT`/`BGE`, and `SLTU` for `BLTU`/`BGEU` when it sees a branch opcode
  (Section 4). That means by the time an instruction reaches the branch
  unit, the ALU has *already* computed exactly the comparison the branch
  needs — `zero` for equality, bit 0 of the `SLT`/`SLTU` result for
  less-than. Reusing the ALU instead of duplicating a comparator saves
  hardware and, more importantly, means there's only one piece of logic
  that can get signed-vs-unsigned comparison wrong, not two.
  - **Targets**: a taken branch or `JAL` targets `pc + imm` (PC-relative).
    `JALR` targets `(rs1 + imm) & ~1` — and since the ALU was already
    computing `rs1 + imm` for a JALR instruction (that's what "ALU op is
    ADD, operand A is rs1, operand B is the immediate" means for JALR),
    the branch unit doesn't recompute this sum itself; it just takes the
    ALU's result and clears the LSB, per the RV32I spec's requirement that
    the target always be even.

- **Forwarding muxes (in `ex_stage_top.v`)** — described fully in Section
  6, but structurally: `forward_a`/`forward_b` (driven by the hazard unit)
  select each ALU operand between the raw ID/EX-latched value, the result
  one stage ahead in MEM, or the result two stages ahead in WB, *before*
  those values reach the ALU.

- **Store data is handled as its own path**, not reused from the ALU's B
  operand. For a store instruction, the ALU's B operand is the *address
  immediate* (computing `rs1 + imm` as the store address) — but the value
  actually being stored is `rs2`. These are two unrelated uses of the same
  instruction slot, and the store-data path (`store_data = rs2_fwd`, the
  *forwarded* rs2 value) is kept deliberately separate so a store never
  accidentally writes an address offset to memory instead of the intended
  data.

- **`csr_file.v`** — the CSR register file, instantiated here in
  `ex_stage_top.v` alongside the ALU and branch unit, since — like them —
  it's a pure function of this stage's own inputs plus one cycle's worth
  of state. It implements the minimal M-mode set needed for trap handling
  (`mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`,
  `mtval`, `mip`, plus the read-only `mvendorid`/`marchid`/`mimpid`/
  `mhartid` identification group), with `mstatus`'s `MPP` field hardwired
  to M-mode and `mtvec`'s mode field masked to Direct, since no privilege
  modes or vectored dispatch exist yet. Its hardware trap-entry and
  `mret` ports are now driven for real by the trap controller below.
  - **The write operand** is the forwarded rs1 value for `csrrw`/`csrrs`/
    `csrrc`, or the zero-extended 5-bit immediate packed into the
    instruction's rs1 field for the `_i` forms — deliberately *not* the
    forwarded value in that case, since that field isn't a register
    reference for those encodings, and forwarding could otherwise
    substitute in an unrelated register's value that happens to
    numerically coincide with those 5 bits.
  - **No forwarding is needed between two CSR instructions accessing the
    same address**, even back to back: the write commits synchronously at
    the same clock edge that moves the producing instruction from EX to
    MEM, so a consumer reaching EX exactly one cycle later already sees
    the update through `csr_file.v`'s own combinational read — the same
    single-resource, single-stage structure that makes GPR-style
    forwarding unnecessary here in the first place.
  - **The old CSR value** (read the same cycle the new value is computed
    and written — correctly matching the RV32I semantics that `rd`
    receives the *pre*-modification value) is threaded onward through
    `ex_mem_register.v`, exactly like the ALU result.

- **The trap controller** — also lives in `ex_stage_top.v`, since every
  condition it needs is already local to this stage:
  - **`ecall`/`ebreak`/`illegal`** (classified in ID) pass straight
    through combinationally — nothing more to compute.
  - **Instruction-address-misaligned** fires whenever `branch_unit`
    actually redirects (a taken branch or any jump — a not-taken branch
    never checks its target) and bit `[1]` of the target is set. Bit `[0]`
    is never checked: `branch_unit.v` already forces it to 0 for `JALR`,
    and B-type/J-type immediates always have it 0 by construction
    (Section 2), so bit 1 is the only bit that can make a target
    something other than 4-byte aligned — exactly what `IALIGN=32` (no C
    extension) requires.
  - **Load/store-address-misaligned** comes from `alu_result` (the
    memory address) and `funct3`, gated on `mem_read`/`mem_write`: byte
    accesses are never misaligned, half-word needs bit `[0]=0`, word
    needs bits `[1:0]=00`. Loads and stores share the same width encoding
    in `funct3` (000/001/010 = byte/half/word), so one check covers both,
    distinguishing the two only for which cause code to report.
  - **These conditions are mutually exclusive per instruction by
    construction**, not by coincidence checked at runtime: a CSR
    instruction can never also be a branch; `ecall`/`ebreak`/`illegal`
    never set `mem_read`/`mem_write`/`branch`/`jump`; and only one of
    branch/jump vs. load/store can ever be true for a single instruction.
    So there's no real priority conflict between them to resolve — the
    `if`/`else if` chain choosing `trap_cause`/`trap_value` is just
    picking out whichever one condition is actually true.
  - **A trapping instruction completes none of its normal effects.**
    `reg_write`/`mem_read`/`mem_write` are ANDed with `!trap_taken`
    before reaching `ex_mem_register.v`, becoming architecturally inert
    the same way a squashed or load-use-bubbled instruction already is.
    This matters concretely for a misaligned `JAL`/`JALR` (which would
    otherwise still write its link value) and a misaligned store (which
    would otherwise still corrupt memory) — a misaligned *load* would be
    caught anyway, since suppressing `reg_write` means nothing ever lands
    in `rd`, but a store has no register result, so a bug in this
    suppression is only visible by reading memory back afterward (see
    Section 10's note on `tb_isa_directed.v` Section L). `csr_op` needs
    no equivalent AND-gate: a CSR instruction can never simultaneously be
    illegal, `ecall`/`ebreak`, or an address computation, so
    `csr_write_en` and `trap_taken` are already mutually exclusive by
    construction.
  - **The resulting redirect reuses the exact same `redirect`/
    `redirect_target` outputs a plain branch already drives** — this is
    the "reuse, don't rebuild, the squash path" idea from
    `docs/roadmap.md`, Phase 1, made concrete: trap entry (target
    `mtvec_q`) and `mret` (target `mepc_q`) both take priority over an
    ordinary branch/jump redirect, since a trapping branch/jump must
    never also be allowed to redirect to its own (possibly bad) target.

- **`ex_mem_register.v`** — pipeline register into MEM. Carries the ALU
  result, the store data, the old CSR value, the destination register, and
  every control signal MEM/WB will need.

- **`muldiv_unit.v`** (Phase 2) — the M extension's eight ops
  (`mul/mulh/mulhsu/mulhu/div/divu/rem/remu`), selected by `funct3` (which
  already encodes exactly these eight variants). An iterative shift-add
  multiplier and restoring divider, both 32 cycles, operating on
  sign-stripped magnitudes with the correct sign re-applied at the end —
  readable, teachable RTL over a DSP-inferring `*`/`/`, matching this
  project's learning focus. `control_unit.v` distinguishes a muldiv
  encoding from the base R-type ALU ops sharing `OP_REG`'s opcode by
  `funct7 == FUNCT7_MULDIV` (`0000001`) rather than the `funct7[5]` bit the
  base ops use — that check has to come *before* the base ops' `funct3`
  case, not after, since `FUNCT7_MULDIV` happens to have bit 5 clear too:
  without the explicit check, a `MUL` would silently decode as `ADD`
  instead of trapping illegal or, correctly, being recognized as a
  multiply — the same class of bug this project's `FENCE` fix (Section 4)
  caught in Phase 1.

  Its result replaces `alu_result` on the way into `ex_mem_register`
  (there's no spare `result_src` encoding to add a fourth writeback source,
  so it rides the existing `RESULT_ALU` path instead) — which means
  writeback and *both* forwarding paths (Section 6) need no changes at
  all. The unit **latches its operands once, on the cycle it starts, and
  never re-reads them** — this is not optional defensive coding, it's
  required for correctness: while the unit is busy, EX/MEM and MEM/WB keep
  draining (they're always-advancing latches, taking bubbles), which makes
  `forward_a`/`forward_b`'s match naturally decay from an EX/MEM hit to a
  MEM/WB hit to no-match within the first couple of cycles of a multi-cycle
  hold — and once it drops to no-match, the *live* operand would fall back
  to `rs1_data`/`rs2_data`, the raw, pre-forwarding value latched into ID/EX
  at decode time, which is stale for exactly the RAW-hazard case forwarding
  exists to fix. Latching at the start captures the one moment the
  forwarded value is guaranteed correct and holds onto it for the rest of
  the operation. See Section 6 for how the pipeline holds the instruction
  in EX in the first place.

- **A extension (Phase 2) in EX — deliberately almost nothing.** An AMO's
  address is `rs1` alone: its R-type-shaped encoding has no immediate field
  at all (`funct5`/`aq`/`rl`/`rs2` occupy those bit positions instead), so
  routing it through the usual `alu_src_b` (imm-or-`rs2`) mux would either
  read those bits as a garbage immediate or wrongly add `rs2` into the
  address. The fix is a new ALU op, **`ALU_PASS_A`** (`alu.v` gains one
  case arm, `result = operand_a`, ignoring `operand_b` entirely) —
  `control_unit.v` decodes an AMO with `alu_src_a = ASEL_RS1`, `alu_op =
  ALU_PASS_A`. Beyond that, EX does no A-extension work of its own: `is_amo`
  and `amo_funct5` are pure pass-through fields into `ex_mem_register`,
  unlike `is_muldiv`, which drove a whole unit instantiated right here. The
  actual read-modify-write happens one stage later, in MEM (Section 7) —
  see that section, and Section 6, for why A needed no new EX-stage stall
  the way M did.

- **`ex_stage_top.v`** — integrates the forwarding muxes, ALU, branch unit,
  CSR file, trap controller, muldiv unit, and EX/MEM register, and exposes
  `redirect`/`redirect_target` — the signals that travel all the way back
  to the IF stage to steer the PC mux — plus `ex_busy` (Phase 2), which
  travels to the hazard unit instead.

## 6. Hazards and forwarding

This is the part of the design that makes "5 stages running in parallel"
actually produce correct results, and it's worth understanding as a single
system even though it's split across `hazard_detection.v` and the
forwarding muxes physically living in `ex_stage_top.v`.

### The problem

Consider:
```
add x1, x2, x3
sub x5, x1, x4      # needs x1 immediately
```
By the time `sub` reaches ID and reads `x1`, `add` hasn't written `x1` to
the register file yet — it's still sitting in EX or MEM. A naive pipeline
would read the *old* value of `x1` and silently compute the wrong answer.
This is a **RAW (read-after-write) hazard**, and it's the single most
common pattern in real code — almost every instruction depends on a
recent predecessor.

### The fix for most cases: forwarding, not stalling

Stalling (pausing the pipeline until the value is safely written back)
would work, but it would cost 2 bubble cycles on *every* dependent
instruction pair — unacceptably slow for something this common. Instead,
`hazard_detection_unit` computes `forward_a`/`forward_b`, two independent
3-way selects (one per ALU operand):

| Value | Selected when |
|---|---|
| `2'b00` — un-forwarded ID/EX value | no hazard |
| `2'b01` — EX/MEM result (`fwd_exmem_data`) | the instruction one stage ahead (currently in MEM) produced this register |
| `2'b10` — MEM/WB result (`fwd_memwb_data`) | the instruction two stages ahead (currently in WB) produced this register |

If both the MEM-stage and WB-stage instructions happen to target the same
register the current instruction needs, **EX/MEM (`2'b01`) wins** — it's
the more recently produced value, so it's the architecturally correct one,
even though the WB-stage instruction is chronologically the very next
producer after that. This priority is exercised directly by test section I
in `tb_isa_directed.v` (a self-referential accumulator where the closer
source must be selected).

`fwd_memwb_data` is wired to `final_wb_rd_data` — the *actual, final*
output of the WB mux (Section 8) — not a raw field plucked out of the
MEM/WB pipeline register. This matters because for a `JAL`/`JALR`
producer, the value that should be forwarded is the *link address*, which
only exists after the WB-stage mux has selected it; forwarding a raw
MEM/WB register field would forward the wrong value for exactly that
instruction class.

`fwd_exmem_data` (in `srotas_processor.v`) needs the same kind of care one
stage earlier: it defaults to `mem_alu_result`, but must special-case both
`RESULT_LINK` (using `mem_pc_plus4`) and `RESULT_CSR` (using
`mem_csr_rdata`, the CSR value threaded out of `ex_stage_top.v`) — for
either producer, the ALU's own result for that instruction is meaningless
garbage, since neither a link value nor a CSR read ever goes through the
ALU. Getting the CSR case wrong here is exactly the kind of bug that's
easy to introduce silently: `tb_isa_directed.v`'s CSR section (K) includes
a CSR result forwarded via EX/MEM to the very next instruction
specifically to catch it, and reverting the fix reproduces the failure
immediately (the consumer receives stale ALU garbage instead of the
correct CSR value).

### The one case forwarding can't fix: load-use hazard

```
lw  x1, 0(x2)
add x3, x1, x4      # needs x1 immediately
```
When `lw` is in EX, its result isn't a computed value yet — it's a memory
*address*. The actual loaded data doesn't exist until `lw` reaches MEM, one
cycle later than the point where `add` (in EX at that time) would need it
forwarded. There's no wire that can deliver a value from the future, so
this hazard is fixed the only way it can be: a one-cycle stall, detected as:

```verilog
id_ex_mem_read && (id_ex_rd_addr != 0) &&
((id_ex_rd_addr == id_rs1_addr) || (id_ex_rd_addr == id_rs2_addr))
```

Note this compares the instruction **in EX** (`id_ex_*`, the ID/EX
register's outputs — a load about to move to MEM) against the instruction
**in ID** (`id_rs1_addr`/`id_rs2_addr` — about to move to EX) — one stage
earlier in the pipeline than where the forwarding comparisons above happen.
That's deliberate: by the time a load's data would even be
forwardable-in-principle, it's already too late to stop the wrong read from
happening. The only available fix at that point is to have prevented the
dependent instruction from advancing into EX in the first place, which
means detecting the hazard one cycle earlier, while the consumer is still
in ID. When detected, the hazard unit:
- holds the PC and IF/ID register (`pc_write_en = 0`, `if_id_write_en = 0`)
  — re-present the same next-instruction next cycle,
- inserts a bubble into ID/EX (`id_ex_flush = 1`) — the load's own
  instruction proceeds into EX normally; a synthetic NOP is inserted
  *behind* it instead.

One cycle later, the load has reached MEM and its result is available as
`fwd_exmem_data` — ordinary EX/MEM forwarding now picks it up, no further
stalling needed.

**A load-use stall must never block a redirect.** `pc_write_en` is
`!load_use_hazard || ex_redirect`, not simply `!load_use_hazard` —
`ex_redirect` has to win. Before traps existed this extra term would have
been dead code: `load_use_hazard` requires `id_ex_mem_read`, and only a
`mem_read == 0` instruction (a branch or jump) could ever assert
`ex_redirect`, so the two conditions were mutually exclusive by
construction. A misaligned load breaks that: the very instruction sitting
in EX can now be both a load (satisfying the hazard condition against
whatever's in ID) and the source of a trap redirect, in the same cycle.
Without the `|| ex_redirect` term, that redirect's target would never
actually reach the PC register — `pc_next` would compute the right value,
but `pc_write_en = 0` would silently discard it, leaving the PC stuck one
cycle behind while `if_id_flush` had already squashed the instructions
that should have been overwritten by the correct fetch. (`if_id_write_en`
needs no equivalent fix: `if_id_register.v`'s own flush already takes
priority over its write-enable whenever both are asserted, so its exact
value during a flush cycle is a don't-care.)

### Branch/jump/trap/mret redirect

Srotas has no branch prediction: it always fetches sequentially and only
finds out a branch was taken once it resolves in EX. By that point, two
wrong-path instructions have already been fetched (currently sitting in IF
and ID). The hazard unit flushes both the same cycle the redirect fires
(`if_id_flush = ex_redirect`, `id_ex_flush = ...  || ex_redirect`), and
`if_stage_top` steers the PC mux to `branch_target` instead of `PC+4`. This
costs a fixed 2-cycle penalty on every taken branch/jump — acceptable for a
single-issue in-order core, and the natural next optimization (see
`README.md`'s "Known limitations") if this were extended further.

Since `ex_redirect` is wired straight to `ex_stage_top.v`'s `redirect`
output (Section 5), and that output is now `trap_taken || mret ||
branch_redirect`, none of `hazard_detection.v`'s squash logic needed to
change to also cover traps and `mret` — it already treats "the EX-stage
instruction is redirecting" as one undifferentiated signal, which is
exactly the "reuse, don't rebuild, the squash path" principle this design
was built around from the start.

### A second, opposite-shaped stall: the multi-cycle muldiv hold (Phase 2)

The load-use stall above inserts its bubble *behind* the stalled
instruction: the load itself proceeds into MEM on schedule, and a
synthetic NOP is pushed into ID/EX in its place, one cycle late. That
shape works because a load only needs ONE extra cycle before its result
becomes forwardable. The M extension's `muldiv_unit.v` (Section 5) needs
the opposite: 32 cycles where the *instruction itself* cannot be allowed to
leave EX at all, since its result isn't ready and there's nowhere useful
to move it to.

So `ex_busy` (from `muldiv_unit.v`, high for the whole multi-cycle
operation) drives a genuinely different set of pipeline actions than
`load_use_hazard` does, even though both ultimately "stall the pipeline":

| | load-use stall | muldiv hold |
|---|---|---|
| What's held | PC, IF/ID | PC, IF/ID, **and ID/EX** |
| What happens to the stalling instruction | advances into MEM on schedule | stays in EX for the whole operation |
| How the bubble is made | `id_ex_flush` zeroes ID/EX's control fields *while its data fields still advance* | `eff_reg_write`/`eff_mem_read`/`eff_mem_write` are ANDed with `!ex_busy` in `ex_stage_top.v`, the same suppression a trapping instruction already gets (Section 5) |
| Duration | exactly 1 cycle, self-clearing | as many cycles as `ex_busy` stays high |

The second column is why `id_ex_register.v` needed a real `write_en` input
(a full hold — data *and* control frozen) in addition to its existing
`flush`: `flush` is a *kill*, not a hold — a squashed or bubbled
instruction's data fields advance right through it, since a zeroed-control
instruction is architecturally a NOP regardless of what data happens to be
sitting in the register (see the comment at the top of `id_ex_register.v`).
Reusing `flush` for a multi-cycle hold would have overwritten the
multiply's own operands with whatever the next ID-stage instruction
produced, mid-computation. `write_en` and `flush` never need to arbitrate
priority against each other in practice: `hazard_detection_unit`'s
`ex_busy` can only be asserted by a muldiv instruction sitting in EX, and a
muldiv is never itself a load (so it can never be the *source* of a
load-use hazard against whatever's in ID) and never a branch, jump, or trap
(so it can never itself assert `ex_redirect`) — the two suppression
mechanisms apply to disjoint instructions, not the same one at different
times.

`pc_write_en` and `if_id_write_en` are both additionally gated by
`!ex_busy` (on top of their existing `!load_use_hazard` term), for the same
reason IF/ID is already frozen during a load-use stall: nothing new should
enter the pipeline while an in-flight instruction can't yet make room for
it. Freezing ID as well as ID/EX (rather than just holding ID/EX and
letting ID keep decoding) is what guarantees the forwarding-staleness
problem described in Section 5's `muldiv_unit.v` writeup can't be made
worse by a *different* register happening to collide - no new instruction
is ever in flight to introduce one.

### A third case that needed no new stall at all: the A extension (Phase 2)

Given the two stall shapes above, it would be reasonable to guess the A
extension (`lr.w`/`sc.w`, the AMO ops) needs a third one — MEM stage, after
all, has never had to stall for anything. It doesn't. `data_memory.v`'s
read is already combinational and its write already synchronous to the
same address, so `amo_unit.v`'s read-modify-write (Section 7) fits in the
one cycle MEM already gets, with no new pipeline register and no change to
`hazard_detection_unit` at all. The only hazard-detection behavior an AMO
needs — its consumer stalling one cycle, the way a load's already does —
falls out of asserting `mem_read=1` for the whole AMO family (decided once,
in `control_unit.v`): `load_use_hazard`'s existing condition
(`id_ex_mem_read && ...`) doesn't care *why* `mem_read` is set, only that it
is. Compare this to M, which needed a brand-new `write_en`/`ex_busy` hold
specifically because its multi-cycle unit lives in EX and has to occupy
that stage for longer than one cycle — a problem A's single-cycle MEM-stage
design simply doesn't have.

## 7. MEM — Memory Access

**Job:** perform the load or store for instructions that need one; pass
everything else through untouched.

- **`data_memory.v`** — a byte-addressable RAM (default 16 KB), Harvard-
  style and completely separate from instruction memory. Two design
  choices are called out directly in the module's own comments because
  they're easy to "fix" into something worse:
  - **Reads are combinational**, not registered. If a load's data were
    registered inside `data_memory`, it would arrive one cycle later than
    the load's own control signals (`rd`, `reg_write`, etc.) traveling
    alongside it through the MEM/WB register — desynchronizing the two.
    Combinational read keeps everything the same age.
  - **No reset on the memory array.** Resetting every byte of a multi-KB
    array on `rst_n` would prevent Vivado from inferring the array as
    Block RAM (a reset that touches the whole array forces
    distributed/register-based memory instead) — which would silently
    make "synthesis-ready" false for any real FPGA target. Simulation
    contents start at zero regardless (Verilog's default), and
    `DMEM_INIT_FILE` is available for a preloaded data segment.
  - **Byte/half/word, signed and unsigned loads**: `funct3` selects the
    width and, for loads, whether to sign- or zero-extend (`LB`/`LH` sign-
    extend from the top bit of the loaded value; `LBU`/`LHU` zero-extend).
    Stores just write the low N bytes, little-endian, matching RV32I.

- **`amo_unit.v`** (Phase 2, A extension) — `lr.w`/`sc.w` and the nine AMO
  read-modify-write ops. Sits between `data_memory`'s read and write ports:
  its `old_value` input is that same cycle's combinational read output, and
  its `write_data`/`write_enable` outputs become what `data_memory` actually
  writes — a single-cycle RMW, not a new stall. This works because
  `data_memory.v`'s read is already combinational and its write already
  synchronous to the same address (see above): the old value is stable and
  observable for the *whole* cycle before the write commits at the next
  edge, so `mem_stage_top.v` can wire read-output-into-ALU-into-write-input
  without any new pipeline register at all — the biggest structural
  difference from the M extension, which needed a genuinely new EX-stage
  hold (Section 6).

  Owns one small piece of state: a reservation (one address register, one
  valid bit) for `lr.w`/`sc.w`, using the textbook address-matching model.
  `lr.w` arms it; `sc.w` always clears it, success or fail; any *other*
  write to the reserved address (a plain store, or a different AMO) also
  clears it — three priority-ordered cases, the third one covering both
  remaining possibilities by simply falling through the first two. The one
  subtlety: the reservation-set/clear branches are gated on `mem_read`/
  `mem_write` *as they arrive at MEM* (already trap-suppressed by
  `ex_stage_top.v`'s `eff_mem_read`/`eff_mem_write`), not on the raw
  `is_amo` flag — `is_amo` alone isn't trap-aware, so a misaligned `lr.w`
  still has it set all the way to MEM, and gating on the suppressed signal
  instead is what stops a trapping `lr.w`/`sc.w` from silently arming or
  consuming a reservation nothing should have touched. The *output-value*
  mux doesn't need this same care: `reg_write` is already 0 for a trapped
  instruction, so nothing downstream ever observes a wrong result
  regardless.

  An AMO's `rd` result rides the *existing* `RESULT_MEM` path with no new
  encoding — for `lr.w` and the nine regular ops it's simply the old memory
  value, exactly what `RESULT_MEM` already means. Only `sc.w`'s result (a
  0/1 success flag, not a memory value) needs an override, applied to
  `final_mem_read_data` inside `mem_stage_top.v` before it reaches
  `mem_wb_register` — the *only* change to the writeback path this whole
  feature needed. Asserting `mem_read=1` for every AMO variant (decided in
  `control_unit.v`, including `sc.w` — its result isn't ready before MEM
  either) is what makes the *existing* load-use hazard protect a consumer
  for free, the same way it already protects an ordinary load's consumer —
  no new hazard-detection logic, unlike M's `ex_busy`.

- **`mem_wb_register.v`** — pipeline register into WB. Nothing unusual:
  carries whichever of ALU result / memory data / PC+4 / old CSR value
  might be needed, plus `rd`/`reg_write`/`result_src` so WB knows what to
  do with them.

- **`mem_stage_top.v`** — wires `data_memory`, `amo_unit.v`, and
  `mem_wb_register` together; the memory address is always `ex_alu_result`,
  since address calculation already happened in EX regardless of
  instruction type (for an AMO, `ALU_PASS_A` in EX already reduced that to
  plain `rs1`, since AMO's encoding has no immediate field — see Section 5).
  The old CSR value passes straight through this module untouched — data
  memory has no interaction with it at all. This module went from a bare
  passthrough wrapper (Phase 1) to owning its first real logic in Phase 2:
  the three small muxes selecting between an AMO's computed values and the
  plain load/store path.

## 8. WB — Writeback

**Job:** pick the final value to write to the register file.

`wb_stage.v` is a single 4-way mux, keyed on `result_src`:

| `result_src` | Value written | Used by |
|---|---|---|
| `RESULT_ALU` | ALU result | Everything not listed below |
| `RESULT_MEM` | Loaded memory data | Loads |
| `RESULT_LINK` | `PC + 4` | `JAL`, `JALR` (the return address) |
| `RESULT_CSR` | Old CSR value (read in EX) | `csrrw`/`csrrs`/`csrrc` and immediate forms |

This is deliberately the *last* possible point to make this decision — WB
is where "the value this instruction produces" is finally, unambiguously
determined, which is also why `fwd_memwb_data` (Section 6) is wired to this
module's output rather than to any earlier, stage-specific field.

`wb_reg_write`/`wb_rd_addr`/`wb_rd_data` leave the WB stage and are routed,
at the top level, back into the ID stage's register-file write port and
into the forwarding logic — closing the loop that Section 4 describes.

## 9. Tying it together: `srotas_processor.v`

The top-level module (`src/top_level/srotas_processor.v`) does three jobs:

1. **Instantiates the five `_stage_top` modules** in order and wires each
   one's outputs to the next one's inputs, plus the two forwarding-data
   assignments that live here rather than inside any single stage, because
   they read state from two different stages at once:
   ```verilog
   assign fwd_exmem_data = (mem_result_src == `RESULT_LINK) ? mem_pc_plus4 :
                            (mem_result_src == `RESULT_CSR)  ? mem_csr_rdata :
                                                                mem_alu_result;
   assign fwd_memwb_data = final_wb_rd_data;
   ```
2. **Instantiates `hazard_detection_unit`** and connects its outputs
   (`pc_write_en`, `if_id_write_en`, `if_id_flush`, `id_ex_flush`,
   `forward_a`, `forward_b`) to the relevant stage modules — this is the
   one module in the design with visibility into signals from four
   different pipeline stages at once, which is exactly why it lives at the
   top level rather than inside any single stage.
3. **Exposes a minimal debug/commit interface** instead of any general
   external memory bus:
   ```verilog
   output wire        wb_commit_valid,  // a real register write just retired
   output wire [4:0]  wb_commit_rd,
   output wire [31:0] wb_commit_data,
   output wire [31:0] wb_commit_pc,     // PC of the retiring instruction
   output wire [31:0] if_pc_debug,
   output wire        trap_valid,       // a trap just resolved
   output wire [31:0] trap_pc,
   output wire [31:0] trap_cause,
   output wire [31:0] trap_mtval
   ```
   `wb_commit_valid` is gated by `rd != 0` — a write targeting `x0` is
   architecturally a no-op (e.g. `jal x0, ...`, a common idiom for "jump
   without saving a return address"), even though the control path still
   raises `reg_write` for it. `wb_commit_pc` needed no new pipeline field:
   `memwb_pc_plus4` is already threaded to WB for JAL/JALR link values, so
   the retiring instruction's own PC is just `memwb_pc_plus4 - 4`.

   `trap_*` mirrors `wb_commit_*` for trap events, which never produce a
   commit (a trapping instruction's `reg_write` is always suppressed —
   Section 5). Its signals are sourced from `ex_stage_top.v`'s internal
   trap logic but **deliberately delayed two clock cycles** by a small
   shift register before being exposed here — the trap itself still
   resolves and redirects in EX exactly as before; only these external
   *debug* copies are delayed, purely for external observation. Without
   that delay, `trap_valid` (tapped in EX) and `wb_commit_valid` (tapped
   in WB, two stages later) would report events from two different
   pipeline depths, and a later instruction's trap could appear in an
   external trace *before* an earlier instruction's commit simply because
   EX is two cycles ahead of WB — not a real reordering, just an artifact
   of comparing two debug taps at different depths. This is exactly what
   happened on the first real run of the lockstep harness (Section 10):
   an `ADDI` immediately followed by a load that trapped on misalignment
   had its trap reported before the `ADDI`'s own commit, purely from this
   timing skew, with the redirect/squash itself completely unaffected.

   Both testbenches and the lockstep harness (Section 10) watch only
   these ports, never internal signals, to decide pass or fail — they're
   the only place in the design that reports "an instruction just
   permanently changed architectural state, or excepted," which is the
   only thing a black-box observer should need.

## 10. How it's verified

Both testbenches in `src/testbenches/` are built around that same
`wb_commit_*` port, on the principle that a testbench should observe the
processor's architectural effects, not its internal wiring.

- **`tb_isa_directed.v`** — the real regression (196 checks). It builds a
  program from `emit(instr)` calls (using the encoder functions in
  `rv32i_encoder.vh`) interleaved with `chk(rd, expected_data)` calls, in
  true program order, forming an expected-commit queue. Because this
  pipeline is strictly in-order and single-issue, "the next commit the DUT
  produces" must equal "the next expected entry in program order" if and
  only if hazards, forwarding, and squashing are all correct — a missing
  commit, an extra commit (e.g. a squashed instruction leaking through
  after all), or a wrong value are all caught the same way, by comparing
  against the next queue entry. See `README.md`'s "Testing" section for
  the full coverage table (sections A–O) and for the three concrete
  cycle-by-cycle hazard traces (back-to-back forwarding, a load-use stall,
  and a taken-branch squash) with actual waveform timing. Four sections
  are worth calling out for what they prove *isn't* covered elsewhere,
  because each caught a real bug during development rather than a
  hypothetical one:
  - **Section K** (CSR) includes a CSR result forwarded via EX/MEM to the
    very next instruction, exercising the `RESULT_CSR` arm of
    `fwd_exmem_data` in `srotas_processor.v` (Section 9) - reverting that
    fix and rerunning reproduces the exact failure it was added to catch.
  - **Section L** (traps) ends its misaligned-store trigger with an
    `LW` from a *pre-primed* address, checking that the trap controller's
    `mem_write` suppression (Section 5) actually held - a store has no
    register result, so a suppression bug there is invisible to anything
    that only checks `rd` values. The address is primed with a known,
    all-nonzero-byte sentinel first rather than assumed to read as zero:
    genuinely untouched memory reads as `X` in Vivado's `xsim`, not 0, so
    comparing against an assumed-zero value would not have caught the bug
    it was written to catch.
  - **Section N** (M extension, Phase 2) includes a producer overwriting a
    register immediately before a multiply reads it, proving
    `muldiv_unit.v` samples the correctly forwarded operand at the exact
    cycle it starts rather than re-reading a value that (as Section 5's
    writeup on the unit explains) would otherwise decay back to a stale
    one partway through the 32-cycle hold; a taken branch and a trap each
    immediately following a divide, proving `ex_busy` dropping doesn't
    leave the redirect path mistimed; and a load-use hazard immediately
    adjacent to a muldiv, proving the two different stall shapes (Section
    6) don't interfere with each other.
  - **Section O** (A extension, Phase 2) mirrors Section N's structure for
    a different reason each time: a producer overwritten immediately
    before an AMO's operand needs it (the same forwarding-freshness point
    as Section N, but via ordinary EX/MEM forwarding here rather than an
    operand latch, since MEM stage never holds anything); the AMO's own
    result consumed by the very next instruction, which is a *load-use
    stall* rather than forwarding - the key architectural difference from
    how M's result reaches its consumer; a back-to-back `lr.w`→`sc.w`
    (the actual lock-acquire idiom) succeeding; `sc.w` failing after an
    intervening plain store to the same address invalidates the
    reservation; and a misaligned `lr.w` trapping while leaving no
    reservation armed, proving `amo_unit.v`'s trap-suppression gating
    (Section 7) isn't just theoretical.

- **`csr_file.v`**, and `control_unit.v`'s and `id_ex_register.v`'s CSR
  *and* trap-classification decode paths, also each have their own
  standalone unit testbenches (`tb_csr_file.v`, `tb_control_unit_csr.v`,
  `tb_id_ex_register_csr.v`, updated for both Phase 2 extensions'
  additions) — exercising the module in isolation with a minimal harness
  before it was wired into the full pipeline, the same incremental
  discipline the rest of this codebase follows. `muldiv_unit.v` and
  `amo_unit.v` each get the same treatment in their own standalone
  testbenches: `tb_muldiv_unit.v` covers every op, every sign combination,
  the divide-by-zero and signed-overflow special cases RISC-V mandates
  never trap, and the busy/done handshake timing including a back-to-back
  pair with no idle cycle between them; `tb_amo_unit.v` covers all nine
  regular ops and the reservation model's edge cases (success, no prior
  `lr.w`, an address mismatch, an intervening write, back-to-back
  `lr.w`→`sc.w`, and the trap-suppression gating itself). The trap
  controller's *resolution* logic (misalignment detection, cause/value
  selection, redirect priority, effect suppression) has no standalone unit
  test: it's integrated deeply enough into `ex_stage_top.v` (alongside the
  ALU, branch unit, and CSR file) that isolating it would mean re-stubbing
  most of that module: the full-pipeline Section L coverage above is the
  intended verification for it, the same way CSR *execution* (as opposed
  to CSR *decode*) has no standalone test either, and the same way
  Sections N and O above are the intended verification for `ex_busy`'s and
  `amo_unit.v`'s pipeline interactions rather than standalone tests of
  `hazard_detection.v`'s and `mem_stage_top.v`'s new logic in isolation.

- **`tb_program.v`** — a template for running an arbitrary compiled
  program from `mem/program.mem`, checking final architectural state
  (specific register values) rather than every intermediate commit. This
  is the file to copy when running your own program; see `README.md`'s
  "Running your own program" section for the `$readmemh` working-directory
  caveat that applies to both Icarus and Vivado.

- **`tools/golden_model.py` + `tools/lockstep_compare.py`** — a second,
  independent verification method for exactly the reason `tb_isa_directed.v`'s
  own header describes: a hand-authored `chk()` queue predicts what
  should happen, which stops scaling once trap timing and CSR
  interleaving make that prediction hard to do by hand. `golden_model.py`
  is a from-scratch instruction-level RV32I + Zicsr + M-mode-trap +
  M-extension + A-extension simulator that mirrors this design's specific CSR-masking and
  trap-detection choices (not the general RISC-V spec); `lockstep_compare.py`
  diffs its trace against a real simulation's, event by event.
  `tb_isa_directed.v` dumps both `mem/lockstep_test.mem` (the exact
  program it built) and `dut_trace.log` (every commit and trap it
  observed) as a side effect of running, so the harness's first target is
  the same program already hand-verified above - three independent
  methods (hand-written `chk()`, the golden model, and the RTL) agreeing
  on all events is the strongest confidence this design currently has -
  Section N's addition raised this to 164 events, and Section O's raised
  it further to 204. `golden_model.py` gained a `_muldiv` method for
  Phase 2's M extension (deliberately an if/elif
  chain rather than the dict-literal style `_alu_reg`/`_alu_imm` use,
  since a dict literal evaluates every branch eagerly and would raise a
  Python `ZeroDivisionError` on `DIV x,0` before the intended, spec-
  mandated non-trapping result could ever be selected) plus the `OP_REG`
  `funct7 == FUNCT7_MULDIV` discriminator mirroring `control_unit.v`'s own;
  and an `OP_AMO` dispatch arm plus reservation state for the A extension,
  mirroring `ex_stage_top.v`'s exact per-variant trap-cause choice
  (`lr.w` reports `LOAD_MISALIGNED` since it never sets `mem_write`;
  `sc.w` and the nine regular ops report `STORE_MISALIGNED`) - the
  existing `OP_STORE` arm also gained one addition, clearing the
  reservation on a plain store to the reserved address, mirroring
  `amo_unit.v`'s own generic "any other write invalidates it" branch.
  It isn't a live cycle-by-cycle co-simulation
  against something like Spike - no RISC-V toolchain or ISS is available
  in this repo's environment - but a trace diff achieves the same
  practical goal: no more hand-computing expected values for anything
  trap-shaped. See `srotas_processor.v`'s `trap_valid`/`trap_pc`/
  `trap_cause`/`trap_mtval` debug ports (Section 9) for a real bug this
  harness surfaced in its very first run - not in the design, but in how
  those ports were observed.

## 11. Scope and what's deliberately not here

RV32I plus Zicsr (CSR instructions execute, per Section 5), Zifencei
(`fence`/`fence.i`, both true no-ops per Section 4), M-mode exception
handling (`ecall`/`ebreak`/`mret`, illegal instructions, misaligned
instruction/load/store addresses, per Section 5's trap controller), the M
extension (multiply/divide, per Section 5's `muldiv_unit.v` and Section
6's stall-shape writeup), and now the A extension (atomics, per Section
7's `amo_unit.v`) — but no compressed (C) extension, and no interrupts or
S/U privilege modes: `mstatus`'s `MPP` field is hardwired to M-mode, and
`mie`/`mip` exist in `csr_file.v` but nothing drives or consumes them,
since there's no timer or external interrupt source yet (a CLINT/PLIC-
equivalent, a later roadmap phase). This closes out `docs/roadmap.md`'s
Phase 2. No branch prediction (every taken branch/jump costs a fixed
2-cycle bubble, per
Section 6). No caches, single outstanding memory access per cycle. These
aren't oversights; they're the stated current scope for a single
hobby-scale in-order core, being built out incrementally — see
[`docs/roadmap.md`](roadmap.md) for the phased plan toward a
Linux-capable core, and `README.md`'s "Known limitations" and
"Contributing" sections for a shorter summary.
