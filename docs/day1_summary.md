# Day 1: Building the Instruction Fetch (IF) Stage

## 🎯 What We Built Today

Welcome to **Srotas** - your hobby RISC-V processor! Today we built the **first stage** of our 5-stage pipeline: the **Instruction Fetch (IF) Stage**.

### The 5-Stage Pipeline Overview
```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│    IF   │ →  │    ID   │ →  │    EX   │ →  │   MEM   │ →  │    WB   │
│  Fetch  │    │ Decode  │    │ Execute │    │ Memory  │    │ Writeback│
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
```

## 📦 Files Created

### 1. `src/if_stage/pc_register.v`
**What it does:** Stores the current instruction address (Program Counter)
- Updates every clock cycle (unless stalled)
- Resets to 0x00000000 on reset
- Can jump to any address (for branches/jumps)

**Key Concept:** The PC is like a bookmark telling us which instruction to fetch next.

### 2. `src/if_stage/instruction_memory.v`
**What it does:** Simulates instruction storage (ROM)
- Takes a 32-bit address, returns a 32-bit instruction
- In real hardware: connects to cache or ROM
- For simulation: we'll load programs using `$readmemh`

**Key Concept:** Instructions are stored in memory, just like data, but fetched separately.

### 3. `src/if_stage/if_id_register.v`
**What it does:** Pipeline register between IF and ID stages
- Captures instruction + PC at end of IF stage
- Supports **stall** (hold) and **flush** (clear) for hazard handling
- Inserts NOP (0x00000013) when flushed

**Key Concept:** Pipeline registers isolate stages and enable parallel execution.

### 4. `src/if_stage/if_stage_top.v`
**What it does:** Top-level module combining all IF components
- Calculates next PC (sequential +4 or branch target)
- Coordinates PC register, memory, and pipeline register
- Interfaces with control signals from later stages

## 🔧 Key Concepts Explained

### Why Pipeline Registers?
```
Without pipelining: 
  [Fetch] → [Decode] → [Execute] → ... (one instruction at a time)

With pipelining:
  Cycle 1: [IF1] 
  Cycle 2: [ID1] [IF2]
  Cycle 3: [EX1] [ID2] [IF3]  ← Multiple instructions in progress!
```

### Stall vs Flush
- **Stall**: Pause the pipeline (hold current values) - used for data hazards
- **Flush**: Clear the pipeline (insert NOPs) - used for branch mispredictions

### RV32I Basics
- 32-bit instructions (all instructions are 4 bytes)
- Byte-addressed memory (but instructions aligned to 4 bytes)
- PC increments by 4 for sequential execution

## 📝 Directory Structure
```
/workspace
├── README.md
├── docs/
│   └── day1_summary.md
├── src/
│   ├── if_stage/          ← TODAY'S WORK
│   │   ├── pc_register.v
│   │   ├── instruction_memory.v
│   │   ├── if_id_register.v
│   │   └── if_stage_top.v
│   ├── id_stage/          ← Coming next
│   ├── ex_stage/          ← Coming soon
│   ├── mem_stage/         ← Coming soon
│   ├── wb_stage/          ← Coming soon
│   ├── common/            ← Shared modules (register file, ALU, etc.)
│   └── testbenches/       ← Test files
```

## 🚀 Next Steps (Day 2)

Tomorrow we'll build the **Instruction Decode (ID) Stage**:
1. **Instruction Decoder** - Parse the 32-bit instruction into fields
2. **Register File** - 32 registers (x0-x31) with dual read/write ports
3. **Sign Extend Unit** - Extend immediate values to 32 bits
4. **Control Unit** - Generate control signals based on opcode
5. **ID/EX Pipeline Register** - Pass decoded info to EX stage

## 🧪 Testing Plan (for later)
Once we have more stages, we'll:
1. Create testbenches with sample programs
2. Simulate with Verilog simulators (ModelSim, Icarus, or Vivado)
3. Verify each stage independently, then integrated

## 💡 Learning Tips
- Read the comments in each `.v` file - they explain the "why" not just the "what"
- Draw the datapath on paper as we build - visualizing helps!
- Think about what happens each clock cycle
- Don't worry about optimization yet - focus on correctness first

---

**Ready to commit?** Let's push today's work to GitHub!

```bash
git add .
git commit -m "Day 1: Complete IF stage with PC, instruction memory, and pipeline register"
git push origin main
```

See you tomorrow for the ID stage! 🎉
