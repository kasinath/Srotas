# Day 3: Execute (EX) Stage - The Calculator Heart of Your Processor

## 🎯 What We Built Today

Welcome to **Day 3** of building your Srotas RISC-V processor! Today we created the **Execute (EX) Stage** - this is where all the actual computation happens. Think of it as the "calculator" inside your processor.

## 📁 Files Created

All files are in `/workspace/src/ex_stage/`:

1. **`alu.v`** - Arithmetic Logic Unit (the main calculator)
2. **`branch_unit.v`** - Branch decision logic
3. **`ex_mem_register.v`** - Pipeline register to MEM stage
4. **`ex_stage_top.v`** - Top-level integration module

## 🔍 Understanding the EX Stage

### What Does the Execute Stage Do?

The EX stage takes decoded instructions from the ID stage and:
1. **Performs calculations** (add, subtract, AND, OR, etc.)
2. **Compares values** (for branch decisions)
3. **Calculates memory addresses** (for load/store instructions)
4. **Decides if branches should be taken**

### The 5-Stage Pipeline So Far:

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│    IF   │ -> │    ID   │ -> │   EX    │ -> │   MEM   │ -> │   WB    │
│  Fetch  │    │  Decode │    │ Execute │    │ Memory  │ │WriteBack│
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │
     │              │              └─ We are HERE!
     │              │
     └──────────────┴── Already built
```

## 🧠 Component Breakdown

### 1. ALU (Arithmetic Logic Unit) - `alu.v`

The ALU is the workhorse of your processor. It performs ALL arithmetic and logical operations.

#### Supported Operations:
| Operation | ALU Control | Description | Example |
|-----------|-------------|-------------|---------|
| ADD | `0010` | Addition | `5 + 3 = 8` |
| SUB | `0110` | Subtraction | `5 - 3 = 2` |
| AND | `0111` | Bitwise AND | `0xA & 0x3 = 0x2` |
| OR | `0000` | Bitwise OR | `0xA \| 0x3 = 0xB` |
| XOR | `0100` | Bitwise XOR | `0xA ^ 0x3 = 0x9` |
| SLT | `0001` | Set Less Than (signed) | `3 < 5 ? 1 : 0` |
| SLTU | `1001` | Set Less Than (unsigned) | Same but unsigned |
| SLL | `1011` | Shift Left Logical | `5 << 2 = 20` |
| SRL | `1101` | Shift Right Logical | `20 >> 2 = 5` |
| SRA | `1110` | Shift Right Arithmetic | Preserves sign bit |

#### Key Features:
- **Zero Flag**: Goes high when result is zero (used for BEQ/BNE)
- **Overflow Flag**: Detects signed overflow in ADD/SUB
- **32-bit operations**: All operations work on 32-bit values

#### Code Example:
```verilog
// How ADD works in the ALU
4'b0010: result = operand_a + operand_b;

// How SLT works (Set Less Than)
4'b0001: result = ($signed(operand_a) < $signed(operand_b)) ? 32'b1 : 32'b0;
```

### 2. Branch Unit - `branch_unit.v`

This module decides whether to take a branch (jump to a different address).

#### Branch Types Supported:
| Type | Code | Condition | Example |
|------|------|-----------|---------|
| BEQ | `000` | Branch if Equal | `if (a == b)` |
| BNE | `001` | Branch if Not Equal | `if (a != b)` |
| BLT | `100` | Branch if Less Than (signed) | `if (a < b)` |
| BGE | `101` | Branch if >= (signed) | `if (a >= b)` |
| BLTU | `110` | Branch if Less Than (unsigned) | `if (a < b)` unsigned |
| BGEU | `111` | Branch if >= (unsigned) | `if (a >= b)` unsigned |

#### How It Works:
```verilog
// Calculate where to jump
branch_target = pc + imm;  // PC + offset

// Decide if we should jump
case (branch_type)
    3'b000: branch_taken = zero;      // BEQ: take if zero flag set
    3'b001: branch_taken = ~zero;     // BNE: take if zero flag NOT set
    3'b100: branch_taken = sign;      // BLT: take if result negative
    // ... etc
endcase
```

### 3. EX/MEM Pipeline Register - `ex_mem_register.v`

This register holds all data between EX and MEM stages.

#### What It Stores:
- **ALU Result**: The calculation result
- **Write Data**: Data to write to memory or register
- **PC**: Current program counter
- **RD**: Destination register number
- **Control Signals**: mem_read, mem_write, reg_write, etc.
- **Branch Info**: Whether branch was taken and target address

#### Special Features:
```verilog
// Stall: Pause the pipeline (hold current values)
if (!stall) begin
    alu_result_out <= alu_result;
    // ... update all outputs
end
// If stall=1, outputs stay the same

// Flush: Clear everything (create a bubble)
else if (flush) begin
    alu_result_out <= 32'b0;
    // ... zero out all outputs
end
```

### 4. EX Stage Top Module - `ex_stage_top.v`

This ties everything together!

#### Data Flow:
```
Inputs from ID/EX Register
         │
         ├──────────────┬──────────────┐
         │              │              │
         ▼              ▼              ▼
      ┌─────┐      ┌──────────┐   ┌─────────┐
      │ ALU │      │ Branch   │   │ Mux for │
      │     │      │ Unit     │   │ WriteData│
      └─────┘      └──────────┘   └─────────┘
         │              │              │
         └──────────────┴──────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │ EX/MEM Register │
              └─────────────────┘
                        │
                        ▼
                 To MEM Stage
```

## 🎓 Key Concepts Explained

### Concept 1: Why Do We Need an ALU?

**Question**: Why not just have separate adders, subtractors, etc.?

**Answer**: An ALU is more efficient! Instead of having 10 different circuits sitting idle most of the time, we have ONE circuit that can do ANY operation based on a control signal. This saves space and power.

### Concept 2: How Does Branching Work?

When you write code like:
```c
if (a == b) {
    // do something
}
```

The processor:
1. Subtracts `a - b` in the ALU
2. Checks if result is zero (zero flag)
3. If zero flag is set AND instruction is BEQ → take branch
4. Calculate new PC = old PC + offset
5. Send new PC back to IF stage (we'll do this in later stages)

### Concept 3: Pipeline Registers Are Critical

Without pipeline registers, all stages would interfere with each other!

**Example without pipeline register:**
- Clock 1: IF fetches instruction 1
- Clock 2: ID decodes instruction 1, BUT IF already fetched instruction 2 and overwrites data!

**With pipeline register:**
- Clock 1: IF fetches instruction 1 → stores in IF/ID register
- Clock 2: ID reads from IF/ID (instruction 1), IF fetches instruction 2 → stores in new IF/ID
- Both instructions progress safely!

## 🔧 How to Test Your Understanding

### Exercise 1: Trace an ADD Instruction
For `ADD x3, x1, x2` (where x1=5, x2=3):
1. What goes into operand_a? **Answer**: Value in x1 (5)
2. What goes into operand_b? **Answer**: Value in x2 (3)
3. What is alu_control? **Answer**: `0010` (ADD)
4. What is the result? **Answer**: 8
5. Does zero flag go high? **Answer**: No (8 ≠ 0)

### Exercise 2: Trace a BEQ Instruction
For `BEQ x1, x2, label` (where x1=5, x2=5):
1. What does ALU calculate? **Answer**: 5 - 5 = 0
2. What is zero flag? **Answer**: 1 (high)
3. What is branch_type? **Answer**: `000` (BEQ)
4. Is branch_taken? **Answer**: Yes!
5. What is branch_target? **Answer**: PC + immediate_offset

### Exercise 3: Understand Shifts
For `SLL x3, x1, x2` (where x1=5, x2=2):
1. What operation? **Answer**: Shift Left Logical
2. Calculation? **Answer**: 5 << 2
3. Binary: `0000...0101` shifted left by 2 = `0000...10100`
4. Result? **Answer**: 20

## 🚀 What's Next? (Day 4 Preview)

Tomorrow we build the **Memory (MEM) Stage**:

### What We'll Create:
1. **Data Memory** - Load/Store operations (LW, SW, LH, SH, LB, SB)
2. **MEM/WB Pipeline Register** - Pass data to Writeback stage
3. **MEM Stage Top** - Integration module

### Key Questions We'll Answer:
- How does the processor read/write memory?
- What's the difference between byte, half-word, and word access?
- How do we handle unaligned memory access?
- Why is memory access its own stage?

## 📝 Daily Checklist

- [ ] Read through all 4 Verilog files in `/workspace/src/ex_stage/`
- [ ] Understand what each control signal does
- [ ] Trace at least 3 different instructions through the EX stage
- [ ] Draw the EX stage datapath on paper
- [ ] Commit and push to GitHub:
  ```bash
  git add .
  git commit -m "Day 3: Complete EX stage with ALU, branch unit, and EX/MEM register"
  git push origin main
  ```

## 💡 Pro Tips

1. **Don't memorize ALU control codes** - Just understand they exist. The control unit generates these automatically.

2. **Focus on data flow** - Always ask: "Where does this value come from? Where does it go?"

3. **Pipeline registers are your friends** - They isolate stages and make debugging easier.

4. **Draw diagrams!** - Seriously, grab paper and draw boxes and arrows. It helps immensely.

## ❓ Common Questions

**Q: Why does the ALU have so many operations?**
A: Because RISC-V has many different instruction types. Each needs a specific operation.

**Q: What happens if I give the ALU an invalid control code?**
A: The `default` case passes operand_a through unchanged. This is safe but won't produce useful results.

**Q: Why do we need both zero and sign flags?**
A: Zero is for equality checks (BEQ/BNE). Sign is for inequality checks (BLT/BGE). Different branch types need different information.

**Q: Can the ALU do multiplication?**
A: Not in RV32I base ISA! Multiplication requires the 'M' extension. We're building the base ISA first.

---

**🎉 Congratulations!** You now have 3 out of 5 stages complete! 
- ✅ IF Stage (Instruction Fetch)
- ✅ ID Stage (Instruction Decode)  
- ✅ EX Stage (Execute) ← YOU ARE HERE
- ⏳ MEM Stage (Memory) - Tomorrow!
- ⏳ WB Stage (Writeback) - Day 5!

Keep going! You're building a real processor! 🚀
