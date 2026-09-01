// ============================================================================
// Module: data_memory.v
// Stage:  MEM (Memory Access)
// Project: Srotas - 5-Stage RISC-V Processor
// Day:    4
//
// Description:
//   Simulates Data Memory for Load/Store operations.
//   Supports byte, half-word, and word access.
//   In a real system, this would be SRAM or connected to a memory controller.
//
// Features:
//   - 32-bit address bus
//   - 32-bit data input/output
//   - Byte-enable support for LB, LH, LW, SB, SH, SW
//   - Synchronous read/write (single clock cycle)
//   - 4KB memory size (expandable)
//
// Interface:
//   - clk: Clock signal
//   - rst_n: Active-low reset
//   - mem_addr: Address from EX/MEM register
//   - mem_write_data: Data to write from EX/MEM register
//   - mem_read: Read enable signal
//   - mem_write: Write enable signal
//   - mem_func3: Function code for access size (3 bits)
//   - mem_read_data: Data read from memory
// ============================================================================

module data_memory (
    input  wire        clk,
    input  wire        rst_n,
    
    // Address and data from EX stage
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_write_data,
    
    // Control signals
    input  wire        mem_read,      // MemRead control signal
    input  wire        mem_write,     // MemWrite control signal
    input  wire [2:0]  mem_func3,     // Access size: 000(LB), 001(LH), 010(LW), 100(SB), 101(SH), 011(SW)
    
    // Output to WB stage
    output reg  [31:0] mem_read_data
);

    // Memory parameters
    localparam MEM_SIZE = 4096;  // 4KB memory
    localparam ADDR_WIDTH = 12;  // log2(4096) = 12 bits
    
    // Memory array (byte-addressable)
    reg [7:0] memory [0:MEM_SIZE-1];
    
    // Internal signals
    wire [ADDR_WIDTH-1:0] aligned_addr;
    wire [31:0] word_data;
    
    // Align address to word boundary for indexing
    assign aligned_addr = mem_addr[ADDR_WIDTH+1:2];  // Ignore lower 2 bits for word alignment
    
    // =========================================================================
    // WRITE OPERATION
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize memory to zero on reset (optional, for simulation)
            integer i;
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] <= 8'd0;
            end
        end
        else if (mem_write) begin
            case (mem_func3)
                3'b100: begin // SB - Store Byte
                    memory[mem_addr[ADDR_WIDTH-1:0]] <= mem_write_data[7:0];
                end
                3'b101: begin // SH - Store Half-word
                    memory[mem_addr[ADDR_WIDTH-1:0]] <= mem_write_data[7:0];
                    memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1] <= mem_write_data[15:8];
                end
                3'b011: begin // SW - Store Word
                    memory[mem_addr[ADDR_WIDTH-1:0]] <= mem_write_data[7:0];
                    memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1] <= mem_write_data[15:8];
                    memory[mem_addr[ADDR_WIDTH-1:0] + 2'b10] <= mem_write_data[23:16];
                    memory[mem_addr[ADDR_WIDTH-1:0] + 2'b11] <= mem_write_data[31:24];
                end
                default: begin
                    // Invalid store operation
                end
            endcase
        end
    end
    
    // =========================================================================
    // READ OPERATION
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_read_data <= 32'd0;
        end
        else if (mem_read) begin
            case (mem_func3)
                3'b000: begin // LB - Load Byte (signed)
                    mem_read_data <= {{24{memory[mem_addr[ADDR_WIDTH-1:0]][7]}}, memory[mem_addr[ADDR_WIDTH-1:0]]};
                end
                3'b001: begin // LH - Load Half-word (signed)
                    mem_read_data <= {{16{memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1][7]}}, 
                                      memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1], 
                                      memory[mem_addr[ADDR_WIDTH-1:0]]};
                end
                3'b010: begin // LW - Load Word
                    mem_read_data <= {memory[mem_addr[ADDR_WIDTH-1:0] + 2'b11],
                                      memory[mem_addr[ADDR_WIDTH-1:0] + 2'b10],
                                      memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1],
                                      memory[mem_addr[ADDR_WIDTH-1:0]]};
                end
                3'b100: begin // LBU - Load Byte Unsigned
                    mem_read_data <= {24'd0, memory[mem_addr[ADDR_WIDTH-1:0]]};
                end
                3'b101: begin // LHU - Load Half-word Unsigned
                    mem_read_data <= {16'd0, 
                                      memory[mem_addr[ADDR_WIDTH-1:0] + 1'b1], 
                                      memory[mem_addr[ADDR_WIDTH-1:0]]};
                end
                default: begin
                    mem_read_data <= 32'd0; // Invalid load
                end
            endcase
        end
        else begin
            mem_read_data <= mem_read_data; // Hold previous value
        end
    end
    
    // =========================================================================
    // DEBUG: Display memory access (for simulation)
    // =========================================================================
    `ifdef DEBUG
    always @(posedge clk) begin
        if (mem_read) begin
            $display("[%0t] MEM READ: addr=%h, func3=%b, data=%h", $time, mem_addr, mem_func3, mem_read_data);
        end
        if (mem_write) begin
            $display("[%0t] MEM WRITE: addr=%h, func3=%b, data=%h", $time, mem_addr, mem_func3, mem_write_data);
        end
    end
    `endif

endmodule
