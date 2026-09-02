# The Srotas Processor: A Complete Guide

This document walks through every module in the Srotas RISC-V processor,
stage by stage, explaining not just what each piece does but *why it exists*
and why it's built the way it is. It replaces the original day-by-day build
log (`day1_summary.md` – `day5_summary.md`) with a single reference that
describes the processor as it actually is today, after the correctness pass
documented in `day6_correctness_pass.md`.

If you just want a quick architectural overview and the datapath diagram,
see the "Architecture" section of the top-level `README.md` — this document
goes deeper, module by module, for anyone extending or debugging the design.

## 1. The big picture

Srotas implements the **RV32I base integer ISA** — the smallest complete
RISC-V instruction set, 47 instructions covering arithmetic, logic, shifts,
loads/stores, branches, and jumps — as a **classic 5-stage in-order
pipeline**:

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
reasoned about independently — the ALU doesn't know it's part of a
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
 31       25 24    20 19    15 14  12 11     8 7       6         0
├──────────┼─────────┼─────────┼───────┼────────┼───┼─────────┤
│imm[12|10:5]│  rs2  │   rs1   │funct3 │imm[4:1]│imm[11]│opcode │
└──────────┴─────────┴─────────┴───────┴────────┴───┴─────────┘

U-type (LUI, AUIPC):
 31                          12 11     7 6         0
├──────────────────────────────┼─────────┼─────────┤
│         imm[31:12]           │   rd    │ opcode  │
└──────────────────────────────┴─────────┴─────────┘

J-type (JAL):
 31                                     12 11     7 6         0
├───────────────────────────────────────┼─────────┼─────────┤
│  imm[20|10:1|11|19:12]                 │   rd    │ opcode  │
└───────────────────────────────────────┴─────────┴─────────┘
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
  hazard is detected (Section 7), the PC must *not* advance, so the same
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
    which matters because RV32I doesn't include compressed, M-extension,
    or CSR opcodes, and encountering one shouldn't silently misbehave.

- **`id_ex_register.v`** — the pipeline register into EX. Its `flush`
  behavior is more selective than `if_id_register`'s: it zeros out only the
  *control* signals (`reg_write`, `mem_read`, `mem_write`, `branch`,
  `jump`, `is_jalr`, `result_src`) and leaves data fields (registers,
  immediate, PC) untouched. A "bubble" only needs to look like a NOP to the
  rest of the pipeline — and an instruction is architecturally inert the
  moment none of its control signals can cause a write, a memory access, or
  a redirect, regardless of what stale data bits happen to still be sitting
  in the register. This one register handles two different reasons to
  flush: a load-use stall bubble, and squashing whatever was decoded down
  the wrong path of a branch.

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
  data. This exact bug existed in the original Day 5 build (see
  `day6_correctness_pass.md`).

- **`ex_mem_register.v`** — pipeline register into MEM. Carries the ALU
  result, the store data, the destination register, and every control
  signal MEM/WB will need.

- **`ex_stage_top.v`** — integrates the forwarding muxes, ALU, branch unit,
  and EX/MEM register, and exposes `redirect`/`redirect_target` — the
  signals that travel all the way back to the IF stage to steer the PC mux.

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

### Branch/jump misprediction

Srotas has no branch prediction: it always fetches sequentially and only
finds out a branch was taken once it resolves in EX. By that point, two
wrong-path instructions have already been fetched (currently sitting in IF
and ID). The hazard unit flushes both the same cycle the redirect fires
(`if_id_flush = ex_redirect`, `id_ex_flush = ...  || ex_redirect`), and
`if_stage_top` steers the PC mux to `branch_target` instead of `PC+4`. This
costs a fixed 2-cycle penalty on every taken branch/jump — acceptable for a
single-issue in-order core, and the natural next optimization (see
`README.md`'s "Known limitations") if this were extended further.

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

- **`mem_wb_register.v`** — pipeline register into WB. Nothing unusual:
  carries whichever of ALU result / memory data / PC+4 might be needed,
  plus `rd`/`reg_write`/`result_src` so WB knows what to do with them.

- **`mem_stage_top.v`** — wires `data_memory` and `mem_wb_register`
  together; the memory address is always `ex_alu_result`, since address
  calculation already happened in EX regardless of instruction type.

## 8. WB — Writeback

**Job:** pick the final value to write to the register file.

`wb_stage.v` is a single 3-way mux, keyed on `result_src`:

| `result_src` | Value written | Used by |
|---|---|---|
| `RESULT_ALU` | ALU result | Everything not listed below |
| `RESULT_MEM` | Loaded memory data | Loads |
| `RESULT_LINK` | `PC + 4` | `JAL`, `JALR` (the return address) |

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
   assign fwd_exmem_data = (mem_result_src == `RESULT_LINK) ? mem_pc_plus4 : mem_alu_result;
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
   output wire [31:0] if_pc_debug
   ```
   `wb_commit_valid` is gated by `rd != 0` — a write targeting `x0` is
   architecturally a no-op (e.g. `jal x0, ...`, a common idiom for "jump
   without saving a return address"), even though the control path still
   raises `reg_write` for it. Both testbenches (Section 10) watch only this
   port, never internal signals, to decide pass or fail — it's the one
   place in the design that reports "an instruction just permanently
   changed architectural state," which is the only thing a black-box test
   should need to observe.

## 10. How it's verified

Both testbenches in `src/testbenches/` are built around that same
`wb_commit_*` port, on the principle that a testbench should observe the
processor's architectural effects, not its internal wiring.

- **`tb_isa_directed.v`** — the real regression (94 checks). It builds a
  program from `emit(instr)` calls (using the encoder functions in
  `rv32i_encoder.vh`) interleaved with `chk(rd, expected_data)` calls, in
  true program order, forming an expected-commit queue. Because this
  pipeline is strictly in-order and single-issue, "the next commit the DUT
  produces" must equal "the next expected entry in program order" if and
  only if hazards, forwarding, and squashing are all correct — a missing
  commit, an extra commit (e.g. a squashed instruction leaking through
  after all), or a wrong value are all caught the same way, by comparing
  against the next queue entry. See `README.md`'s "Testing" section for
  the full coverage table (sections A–J) and for the three concrete
  cycle-by-cycle hazard traces (back-to-back forwarding, a load-use stall,
  and a taken-branch squash) with actual waveform timing.

- **`tb_program.v`** — a template for running an arbitrary compiled
  program from `mem/program.mem`, checking final architectural state
  (specific register values) rather than every intermediate commit. This
  is the file to copy when running your own program; see `README.md`'s
  "Running your own program" section for the `$readmemh` working-directory
  caveat that applies to both Icarus and Vivado.

## 11. Scope and what's deliberately not here

RV32I only — no compressed (C), multiply/divide (M), CSRs, exceptions, or
interrupts. No branch prediction (every taken branch/jump costs a fixed
2-cycle bubble, per Section 6). No caches, single outstanding memory access
per cycle. These aren't oversights; they're the stated v1 scope for a
single hobby-scale in-order core (see `README.md`'s "Known limitations" and
"Contributing" sections for what's intended to come next).
