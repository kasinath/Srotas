// ============================================================================
// Module: register_file
// File: register_file.v
// Stage: ID (reads) / WB (writes, fed back from the top level)
//
// 32 x 32-bit RV32I general-purpose registers. x0 always reads as zero.
// Read is asynchronous/combinational; write is synchronous on posedge clk.
//
// Same-cycle write-then-read bypass: if the WB stage is writing register R
// in this very cycle and ID is simultaneously reading R, the new value is
// forwarded out combinationally instead of the stale pre-write value. This
// is required correctness for a 3-apart RAW hazard (producer in WB, exactly
// its 3rd successor in ID) which the EX-stage forwarding unit cannot reach.
// ============================================================================

`timescale 1ns/1ps

module register_file (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        reg_write_en
);

    reg [31:0] registers [1:31]; // x0 is not stored, hardwired to zero

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else if (reg_write_en && (rd_addr != 5'd0)) begin
            registers[rd_addr] <= rd_data;
        end
    end

    wire bypass1 = reg_write_en && (rd_addr != 5'd0) && (rd_addr == rs1_addr);
    wire bypass2 = reg_write_en && (rd_addr != 5'd0) && (rd_addr == rs2_addr);

    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 :
                       bypass1            ? rd_data :
                                             registers[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 :
                       bypass2            ? rd_data :
                                             registers[rs2_addr];

endmodule
