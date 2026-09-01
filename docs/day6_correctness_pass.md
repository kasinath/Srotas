# Day 6: Correctness Pass

Before publishing, the Day 1-5 integration was reviewed end-to-end and
simulated for the first time as a complete design. It didn't compile: each
stage's `_top` module had been built independently and the final top-level
(`srotas_processor.v`) invented different port names when instantiating
every one of them. Once the interfaces were made consistent, several
functional gaps remained underneath the mismatch:

- **No data forwarding.** Every back-to-back dependent instruction (the
  single most common pattern in any real program) would read a stale
  register value, since writeback happens two stages after decode and
  nothing bypassed the gap.
- **Load-use hazard detection compared the wrong pipeline stages** (the
  ID/EX-vs-EX/MEM boundary was checked using the EX/MEM-vs-MEM/WB signals),
  so it wouldn't actually catch the hazard it was meant to catch.
- **Branches and jumps never redirected the PC.** The EX-stage branch/jump
  target was computed but never wired back to the IF stage, and the two
  wrong-path instructions that get fetched after a branch were never
  flushed.
- **The register file's write port was tied to constants** (`rd_data =
  32'b0`, `reg_write_en` wired to an ID-stage signal instead of the WB
  stage's), so writeback never reached the register file at all.
- **`sw` stored the wrong data.** The store-data path reused the ALU's B
  operand, which for a store is the address immediate, not the register
  value being stored.
- **Load data arrived a cycle late** relative to its control signals,
  because the data memory's read output was registered instead of
  combinational, desyncing it from the MEM/WB latch that was supposed to
  capture it the same cycle.
- **The top-level's external memory ports were dead wiring** — declared,
  and driven by nothing, while the real datapath used its own internal
  instruction/data memories. The old testbench assumed the external ports
  were live and would have silently observed nothing.

## What changed

- Every stage's ports were made consistent end to end, with a shared
  `src/common/rv32i_defines.vh` so the control unit and ALU can never
  disagree about what an opcode or ALU-op encoding means.
- Added a real forwarding unit (EX/MEM → EX and MEM/WB → EX) plus a
  same-cycle write-then-read bypass inside the register file itself for the
  one hazard distance forwarding can't reach (producer exactly 3
  instructions ahead). Load-use hazards still stall one cycle, correctly
  detected against the right pipeline boundary this time.
- Branch/jump resolution in EX now drives a real `redirect`/`redirect_target`
  back to IF, and squashes both the IF and ID stage's in-flight instructions
  the same cycle.
- The register file's write port is driven by the WB stage's actual output,
  fed back through the top level into the ID stage.
- Store data is now always the forwarded rs2 value, independent of what the
  ALU's B operand is doing.
- Data memory read is combinational; its full-array reset was removed (a
  reset touching every byte of a multi-KB array won't infer as Block RAM on
  an FPGA, which would have silently made "synthesis-ready" false for any
  real board target).
- Dropped the unused external memory interface; the top level now exposes
  `clk`/`rst_n` plus a small commit-monitor (`wb_commit_*`) for testbenches
  to watch, instead of dead ports.

## Verification

A 94-check self-checking directed testbench
(`src/testbenches/tb_isa_directed.v`) exercises every R-type/I-type ALU op,
LUI/AUIPC, every load/store width signed and unsigned, store-data
forwarding, a load-use stall, the register-file bypass case, a forwarding-
priority stress case, all six branch comparisons with squash verification,
a backward-branch loop, and a JAL/JALR call/return - all passing. A second
testbench (`tb_program.v`) runs a small compiled program from
`mem/program.mem` end to end as a template for loading your own program.
