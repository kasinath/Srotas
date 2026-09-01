/**
 * Program Counter (PC) Register
 * 
 * Description:
 * - Stores the current instruction address
 * - Updates on every clock cycle (unless stalled)
 * - Supports incremental updates (+4 for RV32I) and branch/jump targets
 * 
 * Interface:
 * - clk: Clock signal
 * - rst_n: Active-low asynchronous reset
 * - pc_next: Next PC value from control logic
 * - pc_update: Enable signal to update PC
 * - pc_current: Current PC value (output to IF stage)
 */

module pc_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc_next,
    input  wire        pc_update,
    output reg  [31:0] pc_current
);

    // On reset, initialize PC to 0x00000000 (reset vector)
    // Otherwise, update only when pc_update is high
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_current <= 32'h00000000;
        end else if (pc_update) begin
            pc_current <= pc_next;
        end
        // If pc_update is low, hold current value (pipeline stall)
    end

endmodule
