// ============================================================================
// Module: data_memory
// File: data_memory.v
// Stage: MEM
//
// Byte-addressable data RAM with byte/half/word load and store support
// (signed and unsigned loads), little-endian, matching RV32I semantics.
//
// Read is combinational (asynchronous) so the loaded value is available
// within the same cycle the address is presented, matching the timing of
// every other combinational stage output feeding the MEM/WB register -
// registering the read here would add a spurious extra cycle of latency
// that would desync the load data from the rd/control signals traveling
// alongside it.
//
// Deliberately has no reset on the memory array: an active reset touching
// every byte of a multi-KB array will not infer as Block RAM in Vivado (it
// forces distributed/register-based memory instead), which defeats the
// point of using a RAM primitive on an FPGA. Initial contents are zero in
// simulation and don't-care/BRAM-default on hardware; students who need a
// preloaded data segment can use DMEM_INIT_FILE.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module data_memory #(
    parameter integer MEM_BYTES  = 16384, // 16KB data memory
    parameter         INIT_FILE  = ""     // optional $readmemh preload (hex bytes)
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_write_data,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,

    output reg  [31:0] mem_read_data
);

    localparam ADDR_BITS = $clog2(MEM_BYTES);

    reg [7:0] memory [0:MEM_BYTES-1];

    wire [ADDR_BITS-1:0] addr0 = mem_addr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] addr1 = addr0 + 32'd1;
    wire [ADDR_BITS-1:0] addr2 = addr0 + 32'd2;
    wire [ADDR_BITS-1:0] addr3 = addr0 + 32'd3;

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    // -----------------------------------------------------------------
    // Write (synchronous)
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB
                    memory[addr0] <= mem_write_data[7:0];
                end
                3'b001: begin // SH
                    memory[addr0] <= mem_write_data[7:0];
                    memory[addr1] <= mem_write_data[15:8];
                end
                3'b010: begin // SW
                    memory[addr0] <= mem_write_data[7:0];
                    memory[addr1] <= mem_write_data[15:8];
                    memory[addr2] <= mem_write_data[23:16];
                    memory[addr3] <= mem_write_data[31:24];
                end
                default: ; // invalid store width: no-op
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Read (combinational)
    // -----------------------------------------------------------------
    always @(*) begin
        case (funct3)
            `FUNCT3_LB:  mem_read_data = {{24{memory[addr0][7]}}, memory[addr0]};
            `FUNCT3_LH:  mem_read_data = {{16{memory[addr1][7]}}, memory[addr1], memory[addr0]};
            `FUNCT3_LW:  mem_read_data = {memory[addr3], memory[addr2], memory[addr1], memory[addr0]};
            `FUNCT3_LBU: mem_read_data = {24'b0, memory[addr0]};
            `FUNCT3_LHU: mem_read_data = {16'b0, memory[addr1], memory[addr0]};
            default:     mem_read_data = 32'b0;
        endcase
    end

    `ifdef SROTAS_DEBUG
    always @(posedge clk) begin
        if (mem_write)
            $display("[%0t] MEM WRITE addr=0x%08h data=0x%08h funct3=%b", $time, mem_addr, mem_write_data, funct3);
    end
    `endif

endmodule
