/*
 * Register File for RISC-V Processor
 * 
 * Features:
 * - 32 general-purpose registers (x0-x31), each 32-bit wide
 * - x0 is hardwired to zero (reads always return 0)
 * - Dual read ports (rs1, rs2) for reading two registers simultaneously
 * - Single write port (rd) for writing one register per cycle
 * - Synchronous write (writes on positive clock edge)
 * - Asynchronous read (reads happen immediately)
 * 
 * RV32I Specification:
 * - Register width: 32 bits
 * - Number of registers: 32 (5-bit address)
 * - x0: Hardwired zero
 * - x1-x31: General purpose
 */

module register_file (
    input wire clk,              // Clock signal
    input wire rst_n,            // Active-low asynchronous reset
    
    // Read Port 1
    input wire [4:0] rs1_addr,   // Address of register to read (port 1)
    output wire [31:0] rs1_data, // Data read from register (port 1)
    
    // Read Port 2
    input wire [4:0] rs2_addr,   // Address of register to read (port 2)
    output wire [31:0] rs2_data, // Data read from register (port 2)
    
    // Write Port
    input wire [4:0] rd_addr,    // Address of register to write
    input wire [31:0] rd_data,   // Data to write
    input wire reg_write_en,     // Write enable signal
    input wire mem_to_reg      // Select between ALU result and memory data (for WB stage)
);

    // Internal register array (32 registers, 32-bit each)
    reg [31:0] registers [0:31];
    
    // Temporary wires for read data
    wire [31:0] read_data1;
    wire [31:0] read_data2;
    
    // Read operations (asynchronous - combinational logic)
    // x0 always returns 0
    assign read_data1 = (rs1_addr == 5'b0) ? 32'b0 : registers[rs1_addr];
    assign read_data2 = (rs2_addr == 5'b0) ? 32'b0 : registers[rs2_addr];
    
    // Output assignment
    assign rs1_data = read_data1;
    assign rs2_data = read_data2;
    
    // Write operation (synchronous - sequential logic)
    // Only write if:
    // 1. Write enable is active
    // 2. Destination register is not x0 (x0 is hardwired to zero)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to 0
            integer i;
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'b0;
            end
        end
        else if (reg_write_en && (rd_addr != 5'b0)) begin
            // Write data to destination register
            // Note: In a complete processor, rd_data would be selected between
            // ALU result and memory data based on mem_to_reg signal
            registers[rd_addr] <= rd_data;
        end
    end
    
    // Optional: Add read-after-write forwarding logic here in future
    // For now, we assume the pipeline handles hazards through stalling
    
endmodule

/*
 * Testbench Notes:
 * 1. Test that x0 always reads as 0
 * 2. Test writing to registers and reading back
 * 3. Test simultaneous read from two registers
 * 4. Test that writing to x0 has no effect
 * 5. Test reset functionality
 */
