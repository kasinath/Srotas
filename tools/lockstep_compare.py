#!/usr/bin/env python3
"""
lockstep_compare.py - the actual "lockstep verification harness" from
docs/roadmap.md, Phase 1: runs golden_model.py against a program and
diffs its trace against a real RTL simulation's trace, event by event.

This is a trace-diff harness, not a live cycle-by-cycle DPI co-simulation
(no Spike or riscv-formal infrastructure is available in this repo's
environment - see docs/roadmap.md for why an RVFI-shaped trace interface
was chosen instead). It still achieves the goal that motivated it: no
more hand-computing expected register values for a program exercising
traps, CSR side effects, and their interleaving - the golden model
computes them, and this script is the pass/fail gate.

Trace format (produced by both golden_model.py and the DUT's
$fdisplay-based dump in tb_isa_directed.v):
    C <pc_hex8> <rd_dec> <data_hex8>    - a register write
    T <pc_hex8> <cause_dec> <mtval_hex8> - a trap

Comparison is over the *sequence* of events only (matching this
project's existing chk()-queue philosophy in tb_isa_directed.v) - not
simulation time, since the golden model has no notion of clock cycles.

Usage:
    python3 lockstep_compare.py <program.mem> <dut_trace.log>

Typical flow: run the Verilog regression first (which dumps
mem/lockstep_test.mem and dut_trace.log as a side effect - see
tb_isa_directed.v), then:
    python3 tools/lockstep_compare.py mem/lockstep_test.mem dut_trace.log
"""

import argparse
import sys

from golden_model import GoldenModel, load_mem_file


def load_trace(path):
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(line)
    return events


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mem_file", help="the program both sides execute ($readmemh format)")
    ap.add_argument("dut_trace", help="trace log dumped by the RTL simulation")
    ap.add_argument("--max-steps", type=int, default=100000)
    args = ap.parse_args()

    golden = GoldenModel(load_mem_file(args.mem_file)).run(args.max_steps)
    dut = load_trace(args.dut_trace)

    errors = 0
    n = max(len(golden), len(dut))
    for i in range(n):
        g = golden[i] if i < len(golden) else None
        d = dut[i] if i < len(dut) else None
        if g == d:
            print(f"[{i}] pass: {d}")
        else:
            errors += 1
            print(f"[{i}] FAIL: golden={g!r}  dut={d!r}")

    print()
    print("=" * 40)
    if errors == 0 and len(golden) == len(dut):
        print(f"RESULT: LOCKSTEP MATCH ({len(golden)} events)")
    else:
        print(f"RESULT: {errors} MISMATCH(ES), golden had {len(golden)} events, dut had {len(dut)}")
    print("=" * 40)

    return 1 if errors or len(golden) != len(dut) else 0


if __name__ == "__main__":
    sys.exit(main())
