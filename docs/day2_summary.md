# Day 2: Instruction Decode (ID) Stage - Complete Guide

## 🎯 What We Built Today

Congratulations! You've now completed the **Instruction Decode (ID) Stage** - the second stage of your 5-stage RISC-V pipeline. This is where the magic of instruction interpretation happens!

## 📁 Files Created (5 New Modules)

### 1. `register_file.v` - The Processor's Memory Bank
- **32 general-purpose registers** (x0-x31), each 32-bit wide
- **Dual read ports**: Can read TWO registers simultaneously (rs1, rs2)
- **Single write port**: Writes ONE register per cycle (rd)
- **Special x0 register**: Hardwired to always return 0
- **Synchronous writes**: Data written on clock edge
- **Asynchronous reads**: Data available immediately

```verilog
// Key feature: x0 is always zero
assign read_data1 = (rs1_addr == 5'b0) ? 32'b0 : registers[rs1_addr];
```

### 2. `sign_extend.v` - Immediate Value Expander
- Converts short immediate values from instructions to full 32-bit signed numbers
- Handles **5 different instruction formats**:
  - **I-type**: Load operations, immediate arithmetic (12-bit → 32-bit)
  - **S-type**: Store operations (12-bit → 32-bit)
  - **B-type**: Branch operations (13-bit → 32-bit, LSB=0)
  - **U-type**: Upper immediate (20-bit → 32-bit, shifted)
  - **J-type**: Jump operations (21-bit → 32-bit, LSB=0)

```verilog
// Example: I-type sign extension
extended_imm = {{20{instruction[31]}}, instruction[31:20]};
```

### 3. `control_unit.v` - The Brain of the Processor
- Decodes the **opcode** and generates all control signals
- Produces **9 control signals**:
  - `reg_write_en`: Enable register writeback
  - `alu_src`: Choose ALU input (register or immediate)
  - `alu_op`: Select ALU operation (ADD, SUB, AND, OR, etc.)
  - `mem_read`/`mem_write`: Memory access control
  - `mem_to_reg`: Choose WB data source (ALU or memory)
  - `branch`/`jump`: Control flow signals
  - `pc_src`: PC source selection
  - `imm_format`: Tell sign extender which format to use

```verilog
// Example: ADD instruction control
OP_OP with funct3=000 and funct7[5]=0 → ALU_ADD, reg_write_en=1
```

### 4. `id_ex_register.v` - Pipeline Bridge
- Stores all data between ID and EX stages
- **Stall support**: Holds values when pipeline must wait (data hazards)
- **Flush support**: Clears control signals for mispredicted branches
- Stores: PC, register addresses, register data, immediate, ALL control signals

```verilog
// Three operating modes:
if (!rst_n)       // Reset everything
else if (flush)   // Clear control signals (bubble)
else if (!stall)  // Normal operation: pass data through
```

### 5. `id_stage_top.v` - Integration Module
- Connects all ID stage components together
- Extracts instruction fields (opcode, rs1, rs2, rd, funct3, funct7)
- Routes signals between modules
- Provides clean interface to IF and EX stages

## 🔍 How the ID Stage Works (Step-by-Step)

### Clock Cycle Breakdown:

```
┌─────────────────────────────────────────────────────────────┐
│                    ID STAGE FLOW                            │
├─────────────────────────────────────────────────────────────┤
│ 1. Instruction arrives from IF stage (32 bits)              │
│ 2. Extract fields:                                          │
│    - opcode [6:0]    → Control Unit                         │
│    - rs1 [19:15]     → Register File Read Port 1            │
│    - rs2 [24:20]     → Register File Read Port 2            │
│    - rd [11:7]       → Passed to EX stage                   │
│    - funct3 [14:12]  → Control Unit + ALU decode            │
│    - funct7 [31:25]  → Control Unit (for shifts, add/sub)   │
│                                                             │
│ 3. Register File reads rs1 and rs2 simultaneously           │
│ 4. Control Unit generates 9 control signals                 │
│ 5. Sign Extend creates 32-bit immediate                     │
│ 6. ID/EX Register stores everything                         │
│ 7. Next cycle: Data moves to EX stage                       │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Instruction Format Reference

### R-type (Register-Register Operations)
```
31        25 24    20 19    15 14  12 11     7 6         0
├───────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│  funct7   │   rs2   │   rs1   │ funct3│   rd    │ opcode  │
│  (7 bits) │ (5 bits)│ (5 bits)│(3 bits)│(5 bits) │(7 bits) │
└───────────┴─────────┴─────────┴───────┴─────────┴─────────┘
Example: ADD rd, rs1, rs2
```

### I-type (Immediate Operations)
```
31        20 19    15 14  12 11     7 6         0
├───────────────┼─────────┼───────┼─────────┼─────────┤
│   imm[11:0]   │   rs1   │ funct3│   rd    │ opcode  │
│   (12 bits)   │ (5 bits)│(3 bits)│(5 bits) │(7 bits) │
└───────────────┴─────────┴───────┴─────────┴─────────┘
Example: ADDI rd, rs1, imm
```

### S-type (Store Operations)
```
31        25 24    20 19    15 14  12 11     7 6         0
├───────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│ imm[11:5] │   rs2   │   rs1   │ funct3│imm[4:0] │ opcode  │
└───────────┴─────────┴─────────┴───────┴─────────┴─────────┘
Example: SW rs2, imm(rs1)
```

### B-type (Branch Operations)
```
31        25 24    20 19    15 14  12 11     8 7   6         0
├───────────┼─────────┼─────────┼───────┼─────────┼───┼─────────┤
│ imm[12]   │imm[10:5]│   rs1   │ funct3│imm[4:1] │rs2│ opcode  │
└───────────┴─────────┴─────────┴───────┴─────────┴───┴─────────┘
Example: BEQ rs1, rs2, offset
```

## 🎓 Key Concepts Explained

### 1. Why Dual Read Ports?
RISC-V instructions often need TWO source operands (e.g., `ADD x3, x1, x2`). 
The register file can read both x1 and x2 in the SAME clock cycle!

### 2. Sign Extension Importance
```verilog
// Without sign extension:
imm = 12'b1111_1111_1111  // This is -1 in 12-bit two's complement
// If we just zero-extend: 0000_0000_0000_0000_1111_1111_1111_1111 = 4095 (WRONG!)
// With sign-extend:      1111_1111_1111_1111_1111_1111_1111_1111 = -1 (CORRECT!)
```

### 3. Stall vs Flush
- **Stall**: "Pause" - Keep current instruction waiting (data hazard)
- **Flush**: "Cancel" - Discard current instruction (wrong path after branch)

### 4. Control Signal Encoding
Each instruction type needs different control signals:
```
LOAD:  reg_write=1, alu_src=1, mem_read=1, mem_to_reg=1
STORE: reg_write=0, alu_src=1, mem_write=1
ADD:   reg_write=1, alu_src=0, alu_op=ADD
```

## 🔧 Testing Your ID Stage

### Simple Test Scenarios:
1. **Register File Test**:
   - Write value to x5, read it back
   - Verify x0 always returns 0
   - Test simultaneous reads from x3 and x7

2. **Sign Extension Test**:
   - I-type: `0xFFF` → `0xFFFFFFFF` (-1)
   - I-type: `0x001` → `0x00000001` (+1)
   - B-type: Verify LSB is always 0

3. **Control Unit Test**:
   - Apply ADD opcode → Check alu_op=ADD, reg_write=1
   - Apply LW opcode → Check mem_read=1, mem_to_reg=1
   - Apply SW opcode → Check mem_write=1, reg_write=0

## 🚀 What's Next? (Day 3 Preview)

Tomorrow we'll build the **Execute (EX) Stage**:

### Components to Build:
1. **ALU (Arithmetic Logic Unit)** - The calculator
   - Add, Subtract, AND, OR, XOR, Shift operations
   - Comparison for branches (SLT, SLTU)
   
2. **Branch Comparator** - Decision maker
   - Check if result is zero (for BEQ/BNE)
   - Compare values (for BLT/BGE)
   
3. **EX/MEM Pipeline Register** - Bridge to memory stage

### Big Picture Progress:
```
✅ Day 1: IF Stage (Fetch instructions)
✅ Day 2: ID Stage (Decode & read registers)
⏭️ Day 3: EX Stage (Execute operations)
⏭️ Day 4: MEM Stage (Memory access)
⏭️ Day 5: WB Stage (Writeback results)
⏭️ Day 6: Top-level integration & testing
```

## 💡 Learning Tips

1. **Draw the datapath** on paper as you read the code
2. **Trace an instruction** through each module:
   - Pick `ADDI x5, x3, 10`
   - Follow: IF → ID (extract fields, read x3, decode) → EX → ...
3. **Understand the "why"**: Why do we need stall? Why sign-extend?
4. **Don't memorize** - understand the patterns

## 📝 Homework (Optional)

Try to answer these questions:
1. What happens if we try to write to x0?
2. Why do B-type and J-type immediates have LSB=0?
3. How does the control unit know the difference between ADD and SUB?
4. What control signals are active for a STORE instruction?

---

**Ready to continue?** Let me know when you want to move to Day 3 (EX Stage)! 

Remember: You're building a complete processor from scratch. Every line of code you write brings you closer to understanding how computers really work at the deepest level! 🎉
