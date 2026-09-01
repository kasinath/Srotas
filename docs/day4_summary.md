# 📅 Day 4: Memory Access (MEM) Stage Complete!

## 🎯 What We Built Today

Welcome to **Day 4** of building your **Srotas RISC-V Processor**! Today we completed the **Memory Access (MEM) Stage**, the fourth of five stages in our pipelined processor.

---

## 📁 Files Created

### In `/workspace/src/mem_stage/`:

1. **`data_memory.v`** - Data Memory Unit
   - 4KB byte-addressable memory
   - Supports LB, LH, LW, LBU, LHU (load operations)
   - Supports SB, SH, SW (store operations)
   - Sign-extension for signed loads
   - Zero-extension for unsigned loads

2. **`mem_wb_register.v`** - MEM/WB Pipeline Register
   - Holds data between MEM and WB stages
   - Stall support (pause pipeline)
   - Flush support (clear pipeline bubble)
   - Passes: result data, memory data, destination register, control signals

3. **`mem_stage_top.v`** - Top-Level MEM Stage Module
   - Integrates data memory and pipeline register
   - Routes signals from EX/MEM to MEM/WB
   - Controls memory read/write operations

---

## 🔍 Understanding the MEM Stage

### Where Does MEM Fit in the Pipeline?

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│    IF   │ -> │    ID   │ -> │    EX   │ -> │   MEM   │ -> │    WB   │
│ Fetch   │    │ Decode  │    │ Execute │    │ Memory  │    │Writeback│
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
                                      ↑              ↑
                                 EX/MEM Reg     MEM/WB Reg
```

### What Does the MEM Stage Do?

The MEM stage has **one primary job**: **Access data memory for load and store instructions**.

#### For LOAD Instructions (LB, LH, LW, LBU, LHU):
1. Address comes from ALU result (computed in EX stage)
2. Read data from memory at that address
3. Send data to WB stage for register writeback

#### For STORE Instructions (SB, SH, SW):
1. Address comes from ALU result
2. Write data to memory at that address
3. No writeback to registers (RegWrite = 0)

#### For Other Instructions (R-type, I-type non-load, branches):
- Memory is NOT accessed
- Data simply passes through to WB stage
- ALU result goes to WB for register writeback

---

## 🧠 Key Concepts Explained

### 1. Byte-Addressable Memory

In RISC-V, memory is **byte-addressable**, meaning each address points to one byte (8 bits).

```
Address:  0x1000    0x1001    0x1002    0x1003
         ┌────────┬────────┬────────┬────────┐
Data:    │  0xAB  │  0xCD  │  0xEF  │  0x12  │
         └────────┴────────┴────────┴────────┘
```

For a **LW (Load Word)** at address 0x1000:
- Read 4 bytes: 0x1000, 0x1001, 0x1002, 0x1003
- Combine into 32-bit word: `0x12EFCDAB` (little-endian)

### 2. Load Operations with Sign Extension

| Instruction | Size | Sign/Zero | Example |
|-------------|------|-----------|---------|
| **LB**  | 1 byte | Sign-extend | 0xFF → 0xFFFFFFFF |
| **LH**  | 2 bytes| Sign-extend | 0xFF00 → 0xFFFF_FF00 |
| **LW**  | 4 bytes| N/A (already 32-bit) |
| **LBU** | 1 byte | Zero-extend | 0xFF → 0x000000FF |
| **LHU** | 2 bytes| Zero-extend | 0xFF00 → 0x0000FF00 |

**Sign Extension Example:**
```verilog
// LB: Load byte 0xFF (-1 in signed)
// Sign bit is 1, so extend with 1s
mem_read_data = {{24{1'b1}}, 8'hFF} = 32'hFFFFFFFF // -1

// LBU: Load byte 0xFF (255 in unsigned)
// Zero-extend with 0s
mem_read_data = {24'd0, 8'hFF} = 32'h000000FF // 255
```

### 3. Store Operations

| Instruction | Size | Action |
|-------------|------|--------|
| **SB** | 1 byte | Store lowest 8 bits |
| **SH** | 2 bytes| Store lowest 16 bits |
| **SW** | 4 bytes| Store all 32 bits |

**Store Word Example:**
```verilog
// SW: Store 0x12345678 at address 0x1000
memory[0x1000] = 0x78  // Lowest byte
memory[0x1001] = 0x56
memory[0x1002] = 0x34
memory[0x1003] = 0x12  // Highest byte
```

### 4. Control Signals in MEM Stage

| Signal | Source | Purpose |
|--------|--------|---------|
| **MemRead** | Control Unit (ID stage) | Enable memory read |
| **MemWrite** | Control Unit (ID stage) | Enable memory write |
| **func3** | Instruction (decoded in ID) | Select access size (B/H/W) |
| **MemtoReg** | Control Unit (ID stage) | Mux select in WB stage |

---

## 📊 Data Flow Through MEM Stage

### Scenario 1: LOAD Instruction (LW x3, 0(x1))

```
EX Stage Output:
  - ALU Result = x1 + 0 = 0x1000 (address)
  - Write Data = X (not used for load)
  - Rd = x3
  - MemRead = 1
  - MemWrite = 0
  - func3 = 010 (word)
  
        ↓ EX/MEM Register
        
MEM Stage:
  - Address 0x1000 sent to data_memory
  - MemRead = 1 → Read enabled
  - Memory returns data at 0x1000-0x1003
  - mem_read_data = [memory[0x1003], memory[0x1002], 
                     memory[0x1001], memory[0x1000]]
  
        ↓ MEM/WB Register
        
WB Stage Input:
  - wb_read_data = value from memory
  - wb_rd = x3
  - wb_reg_write = 1
  - wb_mem_to_reg = 1 (select memory data)
```

### Scenario 2: STORE Instruction (SW x2, 4(x1))

```
EX Stage Output:
  - ALU Result = x1 + 4 = 0x1004 (address)
  - Write Data = value in x2
  - Rd = x0 (not used for store)
  - MemRead = 0
  - MemWrite = 1
  - func3 = 011 (word)
  
        ↓ EX/MEM Register
        
MEM Stage:
  - Address 0x1004 sent to data_memory
  - Write Data sent to data_memory
  - MemWrite = 1 → Write enabled
  - Memory updated at addresses 0x1004-0x1007
  
        ↓ MEM/WB Register
        
WB Stage Input:
  - wb_reg_write = 0 (no register writeback for stores)
  - Data not needed by WB stage
```

### Scenario 3: ADD Instruction (ADD x3, x1, x2)

```
EX Stage Output:
  - ALU Result = x1 + x2
  - Write Data = X (not used)
  - Rd = x3
  - MemRead = 0
  - MemWrite = 0
  
        ↓ EX/MEM Register
        
MEM Stage:
  - No memory access (MemRead=0, MemWrite=0)
  - ALU result passes through
  
        ↓ MEM/WB Register
        
WB Stage Input:
  - wb_result = ALU result (x1 + x2)
  - wb_rd = x3
  - wb_reg_write = 1
  - wb_mem_to_reg = 0 (select ALU result)
```

---

## 🔧 Technical Details

### Memory Size and Addressing

```verilog
localparam MEM_SIZE = 4096;  // 4KB memory
localparam ADDR_WIDTH = 12;  // log2(4096) = 12 bits
```

- **4KB** = 4096 bytes = enough for small programs
- **12-bit address** can access 2^12 = 4096 locations
- In real processors, this would be much larger (MB or GB)
- For learning, 4KB is perfect!

### Little-Endian vs Big-Endian

Our implementation uses **Little-Endian** (same as RISC-V standard):
- Least Significant Byte (LSB) at lowest address
- Most Significant Byte (MSB) at highest address

Example: Storing 0x12345678 at address 0x1000
```
Address  0x1000  0x1001  0x1002  0x1003
Data     0x78    0x56    0x34    0x12
         (LSB)                    (MSB)
```

---

## ✅ Progress Check

You've now completed **4 out of 5 stages**!

| Stage | Status | Components |
|-------|--------|------------|
| **IF** | ✅ Done | PC, Instruction Memory, IF/ID Register |
| **ID** | ✅ Done | Register File, Decoder, Sign Extend, ID/EX Register |
| **EX** | ✅ Done | ALU, Branch Unit, EX/MEM Register |
| **MEM**| ✅ Done | Data Memory, MEM/WB Register |
| **WB** | ⏳ Next | Writeback Mux, Register Write Logic |

**Completion: 80%** 🎉

---

## 🎓 Learning Exercises

### Exercise 1: Trace a Load Instruction
Given: `LW x5, 8(x3)` where x3 = 0x2000
1. What address does the ALU compute?
2. Which bytes are read from memory?
3. How is the 32-bit value reconstructed?

### Exercise 2: Trace a Store Instruction
Given: `SW x2, 12(x1)` where x1 = 0x3000, x2 = 0xDEADBEEF
1. What address is computed?
2. What values are written to which memory locations?
3. Is anything written back to a register?

### Exercise 3: Memory Alignment
Why must LW addresses be multiples of 4? What happens if you try `LW x1, 3(x0)`?

*(Answers in tomorrow's summary!)*

---

## 🚀 What's Next? Day 5: Writeback (WB) Stage

Tomorrow we'll complete the final stage:

### Writeback Stage Will Include:
1. **Result Multiplexer** - Choose between ALU result and memory data
2. **Register Write Logic** - Write final result to register file
3. **Pipeline Completion** - Close the loop!

### After WB Stage:
- Connect all 5 stages together
- Add hazard detection unit
- Add forwarding unit
- Create top-level processor module
- Test with sample programs!

---

## 💡 Pro Tips

1. **Understand the Data Path**: Draw how data flows from EX → MEM → WB
2. **Memory is Optional**: Most instructions don't use memory (only LOAD/STORE)
3. **Control Signals Matter**: MemRead/MemWrite come from ID stage control unit
4. **Think Pipelined**: While one instruction is in MEM, others are in IF, ID, EX!

---

## 📝 Quick Reference

### RV32I Load/Store Instructions

| Mnemonic | Format | Operation | func3 |
|----------|--------|-----------|-------|
| **LB**  | I | `x[rd] = sext(M[x[rs1]+imm][7:0])` | 000 |
| **LH**  | I | `x[rd] = sext(M[x[rs1]+imm][15:0])` | 001 |
| **LW**  | I | `x[rd] = M[x[rs1]+imm][31:0]` | 010 |
| **LBU** | I | `x[rd] = zero_ext(M[x[rs1]+imm][7:0])` | 100 |
| **LHU** | I | `x[rd] = zero_ext(M[x[rs1]+imm][15:0])` | 101 |
| **SB**  | S | `M[x[rs1]+imm][7:0] = x[rs2][7:0]` | 100 |
| **SH**  | S | `M[x[rs1]+imm][15:0] = x[rs2][15:0]` | 101 |
| **SW**  | S | `M[x[rs1]+imm][31:0] = x[rs2][31:0]` | 011 |

---

## 🎯 Tomorrow's Goal

**Complete the processor!** 

Day 5 will finish the WB stage and then we'll connect everything together to create a fully functional 5-stage pipelined RISC-V processor!

See you tomorrow for the grand finale! 🚀

---

*Keep building, keep learning! You're almost there!* 💪
