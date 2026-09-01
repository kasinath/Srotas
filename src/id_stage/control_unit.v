/*
 * Control Unit for RISC-V Processor (RV32I Subset)
 * 
 * Purpose:
 * - Decodes opcode and generates control signals for datapath
 * - Determines instruction type and required operations
 * 
 * Control Signals Generated:
 * - reg_write_en: Enable register writeback
 * - alu_src: Select ALU input (register or immediate)
 * - alu_op: ALU operation code
 * - mem_read: Enable data memory read
 * - mem_write: Enable data memory write
 * - mem_to_reg: Select WB data source (ALU result or memory)
 * - branch: Branch instruction detected
 * - jump: Jump instruction detected
 * - imm_format: Immediate format selector for sign extension
 */

module control_unit (
    input wire [6:0] opcode,     // Instruction opcode
    input wire [2:0] funct3,     // Function code 3
    input wire [6:0] funct7,     // Function code 7
    
    // Control signals output
    output reg reg_write_en,     // Register write enable
    output reg alu_src,          // ALU source select (0=reg, 1=imm)
    output reg [3:0] alu_op,     // ALU operation
    output reg mem_read,         // Memory read enable
    output reg mem_write,        // Memory write enable
    output reg mem_to_reg,       // WB source select (0=ALU, 1=MEM)
    output reg branch,           // Branch signal
    output reg jump,             // Jump signal
    output reg [2:0] imm_format, // Immediate format
    output reg pc_src            // PC source select (for branches/jumps)
);

    // Opcode definitions (RV32I)
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_OPIMM  = 7'b0010011;
    localparam OP_OP     = 7'b0110011;
    
    // ALU operation codes
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_OR   = 4'b0111;
    localparam ALU_AND  = 4'b1000;
    localparam ALU_COPY = 4'b1001; // Pass first operand unchanged
    
    // Immediate format selectors
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;
    
    // Default values (combinational logic)
    always @(*) begin
        // Default values - most instructions don't write to memory or registers
        reg_write_en = 1'b0;
        alu_src = 1'b0;
        alu_op = ALU_ADD;
        mem_read = 1'b0;
        mem_write = 1'b0;
        mem_to_reg = 1'b0;
        branch = 1'b0;
        jump = 1'b0;
        imm_format = IMM_I;
        pc_src = 1'b0;
        
        case (opcode)
            OP_LUI: begin
                // LUI: Load Upper Immediate
                reg_write_en = 1'b1;
                alu_src = 1'b1;        // Use immediate
                alu_op = ALU_COPY;     // Just pass immediate
                imm_format = IMM_U;
            end
            
            OP_AUIPC: begin
                // AUIPC: Add Upper Immediate to PC
                reg_write_en = 1'b1;
                alu_src = 1'b1;        // Use immediate
                alu_op = ALU_ADD;      // PC + imm
                imm_format = IMM_U;
            end
            
            OP_JAL: begin
                // JAL: Jump and Link
                reg_write_en = 1'b1;   // Write return address to rd
                jump = 1'b1;
                pc_src = 1'b1;
                imm_format = IMM_J;
            end
            
            OP_JALR: begin
                // JALR: Jump and Link Register
                reg_write_en = 1'b1;   // Write return address to rd
                alu_src = 1'b1;        // Use immediate for target calculation
                alu_op = ALU_ADD;      // rs1 + imm
                jump = 1'b1;
                pc_src = 1'b1;
                imm_format = IMM_I;
            end
            
            OP_BRANCH: begin
                // BRANCH: Conditional branches
                branch = 1'b1;
                pc_src = 1'b1;
                alu_src = 1'b0;        // Compare two registers
                imm_format = IMM_B;
                
                // Set ALU operation based on funct3 for different branch types
                case (funct3)
                    3'b000: alu_op = ALU_SUB;  // BEQ
                    3'b001: alu_op = ALU_SUB;  // BNE
                    3'b100: alu_op = ALU_SLT;  // BLT
                    3'b101: alu_op = ALU_SLT;  // BGE
                    3'b110: alu_op = ALU_SLTU; // BLTU
                    3'b111: alu_op = ALU_SLTU; // BGEU
                    default: alu_op = ALU_SUB;
                endcase
            end
            
            OP_LOAD: begin
                // LOAD: Load from memory
                reg_write_en = 1'b1;
                alu_src = 1'b1;        // Use immediate for address calculation
                alu_op = ALU_ADD;      // Calculate effective address
                mem_read = 1'b1;
                mem_to_reg = 1'b1;     // Write memory data to register
                imm_format = IMM_I;
            end
            
            OP_STORE: begin
                // STORE: Store to memory
                alu_src = 1'b1;        // Use immediate for address calculation
                alu_op = ALU_ADD;      // Calculate effective address
                mem_write = 1'b1;
                imm_format = IMM_S;
            end
            
            OP_OPIMM: begin
                // OP-IMM: Immediate arithmetic/logic operations
                reg_write_en = 1'b1;
                alu_src = 1'b1;        // Use immediate
                imm_format = IMM_I;
                
                // Set ALU operation based on funct3
                case (funct3)
                    3'b000: alu_op = ALU_ADD;   // ADDI
                    3'b010: alu_op = ALU_SLT;   // SLTI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    3'b100: alu_op = ALU_XOR;   // XORI
                    3'b110: alu_op = ALU_OR;    // ORI
                    3'b111: alu_op = ALU_AND;   // ANDI
                    3'b001: alu_op = ALU_SLL;   // SLLI
                    3'b101: begin
                        // SRLI/SRAI - check funct7[5]
                        if (funct7[5]) 
                            alu_op = ALU_SUB;   // SRAI (arithmetic right shift)
                        else 
                            alu_op = ALU_SRL;   // SRLI (logical right shift)
                    end
                    default: alu_op = ALU_ADD;
                endcase
            end
            
            OP_OP: begin
                // OP: Register arithmetic/logic operations
                reg_write_en = 1'b1;
                alu_src = 1'b0;        // Use register operands
                imm_format = IMM_I;    // Don't care, but set to default
                
                // Set ALU operation based on funct3 and funct7
                case (funct3)
                    3'b000: begin
                        if (funct7[5]) 
                            alu_op = ALU_SUB;   // SUB
                        else 
                            alu_op = ALU_ADD;   // ADD
                    end
                    3'b001: alu_op = ALU_SLL;   // SLL
                    3'b010: alu_op = ALU_SLT;   // SLT
                    3'b011: alu_op = ALU_SLTU;  // SLTU
                    3'b100: alu_op = ALU_XOR;   // XOR
                    3'b101: begin
                        if (funct7[5]) 
                            alu_op = ALU_SUB;   // SRA (arithmetic right shift)
                        else 
                            alu_op = ALU_SRL;   // SRL (logical right shift)
                    end
                    3'b110: alu_op = ALU_OR;    // OR
                    3'b111: alu_op = ALU_AND;   // AND
                    default: alu_op = ALU_ADD;
                endcase
            end
            
            default: begin
                // Unknown opcode - set all controls to safe defaults
                reg_write_en = 1'b0;
                alu_src = 1'b0;
                alu_op = ALU_ADD;
                mem_read = 1'b0;
                mem_write = 1'b0;
                mem_to_reg = 1'b0;
                branch = 1'b0;
                jump = 1'b0;
                pc_src = 1'b0;
            end
        endcase
    end

endmodule

/*
 * Control Signal Summary Table:
 * 
 * Instruction | RegWrite | ALUSrc | MemRead | MemWrite | MemtoReg | Branch | Jump
 * ------------|----------|--------|---------|----------|----------|--------|------
 * LUI         |    1     |   1    |    0    |    0     |    0     |   0    |  0
 * AUIPC       |    1     |   1    |    0    |    0     |    0     |   0    |  0
 * JAL         |    1     |   X    |    0    |    0     |    0     |   0    |  1
 * JALR        |    1     |   1    |    0    |    0     |    0     |   0    |  1
 * BEQ/BNE/etc |    0     |   0    |    0    |    0     |    0     |   1    |  0
 * LB/LH/etc   |    1     |   1    |    1    |    0     |    1     |   0    |  0
 * SB/SH/etc   |    0     |   1    |    0    |    1     |    0     |   0    |  0
 * ADDI/etc    |    1     |   1    |    0    |    0     |    0     |   0    |  0
 * ADD/etc     |    1     |   0    |    0    |    0     |    0     |   0    |  0
 * 
 * Note: X = Don't care
 */
