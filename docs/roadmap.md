# Srotas Roadmap: Toward a Linux-Capable Core

This document lays out the planned path from Srotas's current state (a
verified RV32I base-ISA, 5-stage in-order pipeline with forwarding and
hazard stalling) to a core capable of booting Linux, as a sequence of
incremental, independently shippable releases.

## Guiding decisions

**Srotas 1.x stays a simple, in-order, single-issue scalar pipeline —
permanently.** No branch prediction, no superscalar issue, no
out-of-order execution go into this core, even after it's Linux-capable.
Everything added between here and "boots Linux" is *architectural*
completeness (privilege modes, an MMU, interrupts, extensions) — not
microarchitectural performance work. Two reasons:

1. It keeps the core's defining property intact: every instruction's
   effect can still be reasoned about and verified by a simple in-order
   commit trace, the same testing philosophy that already exists
   (`docs/processor_guide.md`, Section 10). Prediction and OoO execution
   are exactly the features that make that kind of verification hard.
2. **This is deliberate groundwork for Srotas 2.0**, a separate,
   higher-performance HPC-oriented core already in development. Once 2.0
   exists, a stable, well-verified, Linux-capable *in-order* Srotas 1.x
   becomes its golden reference model — the same role Rocket plays for
   BOOM in the Chipyard ecosystem, or a scalar ISS plays for validating a
   superscalar implementation. A lockstep/trace-comparison harness built
   for 1.x's own verification (see Phase 1 below) is directly reusable to
   validate 2.0 against 1.x later. Keeping 1.x architecturally simple is
   what makes it trustworthy enough to serve that role.

Performance ambition — prediction, wider issue, OoO, caches beyond
whatever minimal one Linux needs to run acceptably — belongs entirely to
2.0. This roadmap is scoped to 1.x only.

## Why this order

Each phase is a prerequisite for the one after it in a real sense, not
just a suggested sequence:

- CSRs and traps (Phase 1) are needed before any privileged software can
  exist at all, and the verification methodology has to evolve *before*
  the ISA gets complex enough that hand-written expected-value tables
  stop being tractable.
- M and A extensions (Phase 2) are needed because mainline Linux and its
  toolchain assume them are present (kernel spinlocks use atomics even on
  a single hart; most compiled code assumes hardware multiply/divide).
- A memory map and real peripherals (Phase 3) are needed before
  interrupts mean anything — an interrupt controller with nothing
  generating interrupts is untestable.
- Interrupts and privilege modes (Phase 4) are needed before an MMU
  matters — page faults are exceptions, and exceptions need the trap
  infrastructure from Phase 1 plus the S/M-mode split to express the
  firmware/kernel boundary.
- The MMU (Phase 5) is the largest single piece of work in the whole
  roadmap and touches both IF and MEM — it's scheduled last precisely
  because everything before it should be stable first.
- Boot flow (Phase 6) is just wiring the previous five phases together
  behind a standard interface (OpenSBI + device tree) so an unmodified
  upstream kernel can run.

## Phase 1 — Trap and CSR foundation

The prerequisite for every later phase. Nothing privileged can exist
without it.

**Progress: all six Zicsr CSR instructions execute end to end.**
`src/csr/csr_file.v` is the CSR register file — mstatus/misa/mie/mtvec/
mscratch/mepc/mcause/mtval/mip plus the read-only ID registers, with a
hardware trap-entry port and an `mret` port alongside its generic
software read/write port (verified standalone, `tb_csr_file.v`, 26
checks). `control_unit.v` decodes all six `csrrw`/`csrrs`/`csrrc`/
`csrrwi`/`csrrsi`/`csrrci` encodings (`OP_SYSTEM` with `funct3 != 000`)
into `reg_write`/`result_src=RESULT_CSR`/`csr_op`/`csr_use_imm` (verified
standalone, `tb_control_unit_csr.v`, 62 checks). `csr_op`/`csr_use_imm`/
`csr_addr` (`instruction[31:20]`, taken raw rather than through
`sign_extend.v` since it's an unsigned index, not a value to sign-extend)
are threaded through `id_ex_register.v` to the ID/EX boundary (verified
standalone, `tb_id_ex_register_csr.v`, 21 checks) — `csr_op` is zeroed on
flush alongside `reg_write`/`mem_read`/`mem_write`/`branch`/`jump`, while
`csr_use_imm`/`csr_addr` pass through unflushed like `alu_src_a`/`rd_addr`.

`csr_file.v` is now instantiated inside `ex_stage_top.v`, alongside the
ALU and branch unit (its trap-entry/`mret` ports tied inactive — no trap
controller exists yet). The write operand is the forwarded rs1 value for
`csrrw`/`csrrs`/`csrrc`, or the zero-extended 5-bit immediate packed into
the instruction's rs1 field for the `_i` forms — deliberately *not*
forwarded in that case, since the field isn't a register reference and
forwarding could substitute in an unrelated value that happens to
numerically coincide. The old CSR value threads through `ex_mem_register.v`
→ `mem_stage_top.v` (pure passthrough, untouched by `data_memory.v`) →
`mem_wb_register.v` → `wb_stage.v`'s mux, now with a `RESULT_CSR` arm.

Getting this right required fixing `fwd_exmem_data` in `srotas_processor.v`,
which previously only special-cased `RESULT_LINK` (JAL/JALR) before
defaulting to `mem_alu_result` — a CSR instruction's ALU result is
meaningless garbage, so a CSR producer sitting in MEM needed the same
kind of special-case, using the newly piped-through `mem_csr_rdata`. This
was caught for real: `tb_isa_directed.v`'s Section K includes a CSR
result forwarded via EX/MEM to the very next instruction, and deliberately
reverting the fix while re-running the suite reproduces the exact failure
(`x29` gets `0x55`, the stale ALU garbage, instead of the correct `5`) —
confirming the test actually exercises the code path it claims to.
Section K (8 checks: all six encodings, a back-to-back same-address CSR
access showing no special forwarding is needed between two CSR
instructions, a GPR value forwarded *into* a CSR write, and the EX/MEM
CSR-forwarding case above) was the first addition to the regression.

**The trap controller is done: `ecall`/`ebreak`/`mret`, illegal
instructions, and misaligned instruction/load/store addresses all trap
correctly, end to end, through the existing branch-squash path.**
`control_unit.v` decodes `ecall`/`ebreak`/`mret` from `OP_SYSTEM` with
`funct3 == 000` (distinguished by the same `imm[11:0]`/`csr_addr` field,
now also fed into `control_unit.v` for this purpose), treats `wfi` as a
legal NOP, and sets a new `illegal` signal for anything else in that
space or any entirely unrecognized opcode. All four signals are threaded
through `id_ex_register.v` exactly like `csr_op` — zeroed on flush, so a
squashed `ecall` on a mispredicted path can never fire.
`tb_control_unit_csr.v` and `tb_id_ex_register_csr.v` were both extended
to cover this decode/passthrough/flush behavior in isolation (now 110 and
32 checks respectively), matching the precedent set for `csr_op`.

The trap controller itself lives in `ex_stage_top.v`, alongside the ALU,
branch unit, and CSR file: `ecall`/`ebreak`/`illegal` pass through
directly; instruction-address-misaligned fires when `branch_unit` redirects
with target bit `[1]` set; load/store-address-misaligned comes from
`alu_result`/`funct3` gated on `mem_read`/`mem_write`. These five
conditions are mutually exclusive per instruction by construction (a
branch/jump and a load/store can never be the same instruction), so
there's no real priority conflict, just an `if`/`else if` selecting the
right `mcause`/`mtval` pair. `csr_file.v`'s trap-entry and `mret` ports —
tied inactive until now — are finally driven for real. The resulting
`trap_taken`/`mret` redirect reuses `ex_stage_top.v`'s existing
`redirect`/`redirect_target` outputs, taking priority over an ordinary
branch/jump redirect (target `mtvec_q` or `mepc_q` respectively) - the
"reuse, don't rebuild, the squash path" idea below, made concrete. A
trapping instruction's `reg_write`/`mem_read`/`mem_write` are ANDed with
`!trap_taken` before reaching `ex_mem_register.v`, so it completes none
of its normal effects (critical for a misaligned `JAL`/`JALR`, which would
otherwise still write its link value, and a misaligned store, which would
otherwise still corrupt memory).

One genuine pipeline-interaction bug turned up building this: a load-use
stall's `pc_write_en = !load_use_hazard` could never before conflict with
`ex_redirect`, since only a `mem_read == 0` instruction (branch/jump)
could ever redirect - mutually exclusive by construction from
`load_use_hazard`'s own `id_ex_mem_read` requirement. A *misaligned load*
breaks that: the EX-stage instruction can now be both a load-use hazard
source and a trap-redirect source in the same cycle. Fixed in
`hazard_detection.v` as `pc_write_en = !load_use_hazard || ex_redirect` -
without it, the trap redirect would compute correctly but never actually
reach the PC register, silently discarded by the stall.

`tb_isa_directed.v`'s new Section L (30 checks) reuses one inline handler
for all five trap causes, each verified via `mepc`/`mcause`/`mtval`
capture and a clean `mret` return to `mepc+4`. Its last check caught a
second real bug in the test itself, not the design: reading a
never-written memory address to confirm a misaligned store's write was
suppressed only works if untouched memory is guaranteed to read as zero -
which it isn't in Vivado's `xsim` (genuinely virgin memory reads `X`
there). Fixed by priming that address with a known, all-nonzero-byte
sentinel first and checking it survives unchanged, and confirmed
meaningful the same way as the CSR-forwarding fix: temporarily disabling
the suppression and rerunning reproduces exactly the corruption the check
exists to catch. Full regression: **134/134** (30 checks for Section L,
plus 2 for Section M below).

**Zifencei is done: `fence` and `fence.i` both decode and execute as true
no-ops.** `control_unit.v` gives `OP_MISC_MEM` (the shared opcode for
both) an explicit case that leaves every control signal at its safe
default and does *not* set `illegal` — a single in-order hart with no
caches has no memory reordering to fence and no instruction cache to
invalidate, so both are architecturally inert here, not merely
unimplemented. This also closed a latent RV32I-compliance gap: `FENCE`
is base-ISA, not an extension, and before this change its opcode fell
into the same unrecognized-opcode `default` case that (correctly) traps
`illegal` for everything else — a real base instruction would have
wrongly excepted. `tb_isa_directed.v`'s new Section M (2 checks) proves
both instructions neither trap nor disturb a forwarded dependency placed
across them.

**The lockstep verification harness is built and passing.** Not a live
cycle-by-cycle DPI co-simulation against Spike - no RISC-V toolchain or
ISS is available in this repo's environment, so the "RVFI-shaped trace
interface" alternative from the original plan was the realistic path:
`tools/golden_model.py` is a from-scratch RV32I + Zicsr + M-mode-trap
instruction-level simulator, and `tools/lockstep_compare.py` diffs its
trace against a real RTL simulation's, event by event. `tb_isa_directed.v`
now dumps its own program as `mem/lockstep_test.mem` and a trace of every
commit/trap it observes as `dut_trace.log`, so the harness's first real
run is against the exact same 134-check program already hand-verified -
three independent methods (hand-written `chk()`, the golden model, and
the RTL) agreeing on all 139 events (134 commits + 5 traps) is about as
much confidence as this design can currently get.

Two new debug ports made this possible: `wb_commit_pc` (derived as
`memwb_pc_plus4 - 4`, no new pipeline field needed - that value was
already threaded to WB for JAL/JALR link values) and
`trap_valid`/`trap_pc`/`trap_cause`/`trap_mtval` from `ex_stage_top.v`'s
internal trap signals. Getting the second one right surfaced a genuine
observation-timing bug, not a design bug: traps resolve in EX, two
stages earlier than `wb_commit_*`'s WB-stage timing, so a naive tap would
let a later instruction's trap appear in the trace *before* an earlier
instruction's commit whenever they were close together in the pipeline -
exactly what happened on the very first comparison run (an `ADDI`
immediately followed by the load that misaligned-traps). Fixed with a
two-stage shift register in `srotas_processor.v` that delays only the
*debug* copies of the trap signals to align with WB, leaving the real
redirect/squash timing (which must stay in EX) untouched. The
comparison harness itself was verified the same way as everything else
in this codebase: a deliberately wrong `mtval` was injected into
`golden_model.py`, confirmed to produce exactly the expected mismatch
report, then reverted.

- ✅ **Zicsr extension**: a CSR register file plus `csrrw` / `csrrs` /
  `csrrc` and their immediate forms.
- ✅ **Zifencei**: `fence.i`, trivial today since there's no instruction
  cache yet to invalidate.
- ✅ **M-mode-only traps**: `ecall`, `ebreak`, illegal-instruction, and
  misaligned-access exceptions, vectoring through `mtvec` and capturing
  `mepc` / `mcause` / `mtval`, returning via `mret`.
- ✅ **Reuse, don't rebuild, the squash path.** A trap is architecturally a
  mispredicted-branch-shaped redirect with extra state capture — the
  existing `redirect` / two-stage-squash mechanism built for
  `branch_unit.v` (see `docs/processor_guide.md`, Section 6) is the right
  place to drive trap entry/exit from, not a parallel mechanism.
- ✅ **Verification shift**: the lockstep harness (above) replaces
  hand-computed expected values as the primary tool for anything with
  nontrivial trap/CSR interleaving, going into Phase 2.

**Phase 1 is closed.** What's deliberately *not* in scope for it and
carried forward instead: interrupts and S/U privilege modes (`mie`/`mip`
exist in `csr_file.v` but nothing drives or consumes them yet - Phase
3/4), `sfence.vma` and CSR addresses outside the currently-implemented
set being treated as illegal-instruction rather than a spec-distinct
"illegal CSR access" cause, and the illegal-instruction `mtval` always
being 0 rather than the faulting instruction word (both are spec-legal
simplifications, not bugs - RV32I permits 0 for these). None of these
block Phase 2.

## Phase 2 — Integer extensions

**Progress: both M (multiply/divide, v1.2) and A (atomics, v1.3) are
done.** Splitting the two into separate releases kept each a reviewable,
independently-verified increment, the same discipline Phase 1 used.

- ✅ **M (multiply/divide)**: `src/ex_stage/muldiv_unit.v`, a 32-cycle
  iterative shift-add multiplier and restoring divider covering all eight
  ops (`mul/mulh/mulhsu/mulhu/div/divu/rem/remu`). **This needed a genuinely
  new stall mechanism, not just a new stall source** — the original plan
  above (a multi-cycle unit "stalls the pipeline the same way a load-use
  hazard does today, just for longer") turned out to be wrong once actually
  built against this code, for a structural reason: the existing load-use
  stall (`docs/processor_guide.md`, Section 6) *bubbles ID/EX forward* while
  the stalled instruction itself continues into MEM — exactly backwards
  from what a multi-cycle EX-stage unit needs, which is to *hold the
  instruction still in EX* while bubbles move forward into MEM instead.
  Concretely: `id_ex_register.v`'s flush is a *kill*, not a hold — data
  fields still advance through it every cycle — so reusing it would have
  overwritten the multiply's own operands mid-computation. `id_ex_register.v`
  gained an actual `write_en` (full hold, data and control alike) for this;
  `hazard_detection_unit`'s new `ex_busy` input drives it, and also freezes
  PC and IF/ID alongside it, so no new instruction can enter the pipeline at
  all while a multiply/divide is in flight. The result rides the existing
  `alu_result` path into `ex_mem_register` (no new `result_src` encoding —
  that 2-bit space was already fully used), suppressed the same way a
  trapping instruction's effects already are. See
  `docs/processor_guide.md`, Section 6, for the two stall shapes compared
  side by side.

  This closed a real latent bug in the process: `control_unit.v` only ever
  checked `funct7[5]` to distinguish `ADD`/`SUB` and `SRL`/`SRA`, and
  `FUNCT7_MULDIV` (`0000001`) has that bit clear — so before this change, a
  `MUL` instruction silently decoded and executed as an `ADD` instead of
  being recognized at all. Same class of bug as the `FENCE` one Phase 1
  found (an unhandled encoding falling through to the wrong default), not a
  new kind of mistake.

- ✅ **A (atomics)**: `src/mem_stage/amo_unit.v` implements `lr.w`/`sc.w`
  and the nine AMO ops. Unlike M, **this needed zero new stall mechanism
  and zero new result-routing** — the two hard problems M had to solve
  simply don't apply here, for reasons specific to where each extension
  lives:
  - `data_memory.v`'s read is already combinational and its write already
    synchronous to the same address, so a same-cycle read-old/write-new
    is timing-safe with no changes to that module and no new pipeline
    register needed anywhere - MEM stays a single-cycle stage.
  - An AMO's `rd` result (the *old* memory value, for `lr.w` and the nine
    regular ops) is exactly what `RESULT_MEM` already means, so it rides
    the existing path with no new `result_src` encoding. Only `sc.w`'s
    result (a 0/1 success flag) needs a value override, done entirely
    inside `mem_stage_top.v`.
  - Asserting `mem_read=1` for the whole AMO family (including `sc.w`,
    since its result isn't ready until MEM either) makes the *existing*
    load-use hazard protect a consumer for free — no new hazard-detection
    logic, unlike M's brand-new `ex_busy`-driven hold.

  `amo_unit.v` owns a small reservation register (one address, one valid
  bit) using the textbook address-matching model: `lr.w` arms it, `sc.w`
  always clears it, and any *other* write to the reserved address (a plain
  store, or a different AMO) also clears it. Getting this right required
  gating the reservation-set/clear branches on the already trap-suppressed
  `mem_read`/`mem_write` signals arriving at MEM, not the raw `is_amo` flag
  — `is_amo` alone isn't trap-aware, so a misaligned `lr.w` would otherwise
  silently arm a reservation nothing should have set. See
  `docs/processor_guide.md`, Section 7, for the full design.

## Phase 3 — Minimal SoC

Turn the core into a machine, not just a datapath.

- A real memory-mapped address-decode/bus layer in front of the current
  parameterized IMEM/DMEM — this doesn't exist yet; today the processor
  module owns its memories directly.
- A memory-mapped UART — the first genuinely fun milestone: bare-metal
  "hello world" over serial.
- A CLINT-equivalent (`mtime` / `mtimecmp`) — the timer interrupt source
  every OS scheduler depends on.

## Phase 4 — Interrupts and privilege modes

- A minimal PLIC-equivalent for external interrupts (UART RX, to start).
- M/S/U privilege modes, `mideleg`/`medeleg`, `sret` — the split that
  lets firmware (M-mode) and kernel (S-mode) be separate trust domains,
  which is required before anything OpenSBI-shaped can sit underneath a
  kernel.

## Phase 5 — Sv32 virtual memory

- Two-level Sv32 page-table walker, a small TLB, and page-fault
  exceptions feeding the Phase 1 trap infrastructure.
- Touches both IF (instruction fetch now needs translation) and MEM
  (load/store address translation) — expect this to be the single
  largest phase in the roadmap.

## Phase 6 — Boot flow: Srotas boots Linux

- OpenSBI running in M-mode, kernel in S-mode, standard RISC-V Linux
  boot protocol (`a0` = hart ID, `a1` = device-tree pointer).
- A device tree describing the Phase 3 memory map.
- Target: a minimal buildroot `rv32ima` configuration with an initramfs
  (no block device needed yet — that's a post-Linux polish item).

This phase is the release that earns the "Linux-capable" description.

## Beyond Phase 6 (polish, not prerequisites)

- `virtio-blk` or similar for a real root filesystem instead of an
  initramfs.
- The C (compressed) extension, mainly to shrink kernel/rootfs image
  size — not required for correctness.
- F/D (floating point) only if userspace workloads need it; the kernel
  itself doesn't require it.

## Suggested versioning

| Version | Milestone |
|---|---|
| v1.0 | Verified RV32I, 5-stage in-order, forwarding, hazard stalling |
| v1.1 | ✅ Phase 1 (done): Zicsr, Zifencei, M-mode traps, lockstep verification harness |
| v1.2 | ✅ Phase 2, part 1 (done): M extension (multiply/divide) |
| v1.3 | ✅ Phase 2, part 2 (done): A extension (atomics) |
| v1.4 | Phase 3 (current target): memory map, UART, CLINT |
| v1.5 | Phase 4: PLIC, M/S/U privilege modes |
| v1.6 | Phase 5: Sv32 MMU + TLB |
| v2.0 | Phase 6: boots Linux |

(This "Srotas v2.0" is a version number for the in-order core described
here — distinct from the separately-developed **Srotas 2.0 HPC core**
mentioned above, which is a different, higher-performance
microarchitecture. The naming overlap is worth resolving before the v2.0
release ships, to avoid confusing the two.)
