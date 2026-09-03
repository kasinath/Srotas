// ============================================================================
// Testbench: tb_muldiv_unit
// File: tb_muldiv_unit.v
//
// Directed unit test for muldiv_unit.v, standalone from the pipeline - the
// same incremental discipline tb_csr_file.v and tb_control_unit_csr.v used
// for Phase 1's CSR file and decode logic before either was wired in.
// Covers all eight RV32M ops, every sign combination that matters for each,
// the divide-by-zero and signed-overflow special cases (RISC-V mandates
// these never trap), the busy/done handshake timing, and a back-to-back
// pair with no idle cycle between them. Pipeline-level interaction (operand
// forwarding into and out of a held muldiv instruction, redirects/traps
// immediately after one) is covered by tb_isa_directed.v's Section N
// instead - the same split Phase 1 used between csr_file's own unit test
// and tb_isa_directed.v's Section K/L.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_muldiv_unit;

    reg clk = 0;
    reg rst_n;

    reg         req;
    reg  [2:0]  op;
    reg  [31:0] operand_a, operand_b;
    wire        busy;
    wire        done;
    wire [31:0] result;

    integer errors;
    integer checks;

    muldiv_unit dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (req),
        .op        (op),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .busy      (busy),
        .done      (done),
        .result    (result)
    );

    always #5 clk = ~clk;

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        begin
            checks = checks + 1;
            if (actual === expected) begin
                $display("[%0t] pass: 0x%08h", $time, actual);
            end else begin
                $display("[%0t] FAIL: expected 0x%08h, got 0x%08h", $time, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check1;
        input actual;
        input expected;
        begin
            checks = checks + 1;
            if (actual === expected) begin
                $display("[%0t] pass: %0b", $time, actual);
            end else begin
                $display("[%0t] FAIL: expected %0b, got %0b", $time, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    // Issues one op and blocks until `done`, checking the result. Drops
    // req for one cycle afterward, mirroring the pipeline handing the next
    // instruction into EX after the held one retires.
    task run_op;
        input [2:0]  top_op;
        input [31:0] a, b;
        input [31:0] expected;
        begin
            @(negedge clk);
            req = 1'b1; op = top_op; operand_a = a; operand_b = b;
            while (!done) @(negedge clk);
            check32(result, expected);
            @(negedge clk);
            req = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        req = 1'b0; op = 3'b0; operand_a = 32'b0; operand_b = 32'b0;

        rst_n = 0;
        #12 rst_n = 1;

        // ---------------- MUL: low 32 bits, sign-independent ----------------
        run_op(`FUNCT3_MUL, 32'd6, 32'd7, 32'd42);
        run_op(`FUNCT3_MUL, -32'd6, 32'd7, -32'd42);
        run_op(`FUNCT3_MUL, -32'd6, -32'd7, 32'd42);
        run_op(`FUNCT3_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1);        // (-1)*(-1) low32 = 1
        run_op(`FUNCT3_MUL, 32'h0000_0000, 32'hDEAD_BEEF, 32'd0);

        // ---------------- MULH: high 32 bits, signed x signed ----------------
        run_op(`FUNCT3_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF); // (2^31-1)^2 >> 32
        run_op(`FUNCT3_MULH, -32'd1, -32'd1, 32'd0);                    // (-1)*(-1)=1, high=0
        run_op(`FUNCT3_MULH, -32'd1, 32'd1, 32'hFFFFFFFF);              // -1, high=all-ones

        // ---------------- MULHSU: high 32 bits, signed x unsigned ----------------
        run_op(`FUNCT3_MULHSU, -32'd1, 32'hFFFFFFFF, 32'hFFFFFFFF);     // -1 * (2^32-1) = -(2^32-1)
        run_op(`FUNCT3_MULHSU, 32'd2, 32'h8000_0000, 32'd1);            // 2 * 2^31 = 2^32, high=1

        // ---------------- MULHU: high 32 bits, unsigned x unsigned ----------------
        run_op(`FUNCT3_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE); // (2^32-1)^2 >> 32
        run_op(`FUNCT3_MULHU, 32'h8000_0000, 32'd2, 32'd1);

        // ---------------- DIV: signed ----------------
        run_op(`FUNCT3_DIV, 32'd20, 32'd6, 32'd3);
        run_op(`FUNCT3_DIV, -32'd20, 32'd6, -32'd3);
        run_op(`FUNCT3_DIV, 32'd20, -32'd6, -32'd3);
        run_op(`FUNCT3_DIV, -32'd20, -32'd6, 32'd3);
        run_op(`FUNCT3_DIV, 32'd5, 32'd0, 32'hFFFFFFFF);                 // /0 -> -1
        run_op(`FUNCT3_DIV, 32'h8000_0000, 32'hFFFFFFFF, 32'h8000_0000); // overflow -> dividend

        // ---------------- DIVU: unsigned ----------------
        run_op(`FUNCT3_DIVU, 32'd20, 32'd6, 32'd3);
        run_op(`FUNCT3_DIVU, 32'hFFFFFFFF, 32'd2, 32'h7FFFFFFF);
        run_op(`FUNCT3_DIVU, 32'd5, 32'd0, 32'hFFFFFFFF);                // /0 -> all-ones

        // ---------------- REM: signed ----------------
        run_op(`FUNCT3_REM, 32'd20, 32'd6, 32'd2);
        run_op(`FUNCT3_REM, -32'd20, 32'd6, -32'd2);                     // sign follows dividend
        run_op(`FUNCT3_REM, 32'd20, -32'd6, 32'd2);
        run_op(`FUNCT3_REM, -32'd20, -32'd6, -32'd2);
        run_op(`FUNCT3_REM, 32'd5, 32'd0, 32'd5);                        // /0 -> dividend
        run_op(`FUNCT3_REM, 32'h8000_0000, 32'hFFFFFFFF, 32'd0);         // overflow -> 0

        // ---------------- REMU: unsigned ----------------
        run_op(`FUNCT3_REMU, 32'd20, 32'd6, 32'd2);
        run_op(`FUNCT3_REMU, 32'hFFFFFFFF, 32'd2, 32'd1);
        run_op(`FUNCT3_REMU, 32'd5, 32'd0, 32'd5);                       // /0 -> dividend

        // ---------------- busy/done handshake ----------------
        @(negedge clk);
        req = 1'b1; op = `FUNCT3_MUL; operand_a = 32'd3; operand_b = 32'd4;
        #1; // let the combinational busy/start chain settle
        check1(busy, 1'b1);   // asserted the same cycle the op is recognized
        check1(done, 1'b0);
        while (!done) @(negedge clk);
        check1(busy, 1'b0);   // deasserts exactly on the done cycle
        check1(done, 1'b1);
        @(negedge clk);
        req = 1'b0;

        // ---------------- back-to-back: no idle cycle between two ops ----------------
        // req is held high across the boundary (as the pipeline hold would
        // present it: is_muldiv stays asserted until the held instruction
        // finally retires) and the second op's operands are already valid
        // by the time the first one's `done` is sampled.
        @(negedge clk);
        req = 1'b1; op = `FUNCT3_MUL; operand_a = 32'd6; operand_b = 32'd7;
        while (!done) @(negedge clk);
        check32(result, 32'd42);
        op = `FUNCT3_DIV; operand_a = 32'd20; operand_b = 32'd6; // new op, req never dropped
        @(negedge clk);
        check1(busy, 1'b1);  // recognized as a fresh start with zero idle cycles
        while (!done) @(negedge clk);
        check32(result, 32'd3);
        @(negedge clk);
        req = 1'b0;

        $display("");
        $display("========================================");
        if (errors == 0) begin
            $display("RESULT: ALL %0d CHECKS PASSED", checks);
        end else begin
            $display("RESULT: %0d ERROR(S) - SEE LOG ABOVE", errors);
        end
        $display("========================================");
        $finish;
    end

endmodule
