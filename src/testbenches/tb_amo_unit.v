// ============================================================================
// Testbench: tb_amo_unit
// File: tb_amo_unit.v
//
// Directed unit test for amo_unit.v, standalone from the pipeline - the
// same discipline tb_muldiv_unit.v used for the M extension. Covers all
// nine regular AMO ops, the lr.w/sc.w reservation model (success, no prior
// LR, address mismatch, an intervening plain-store-shaped write, and
// back-to-back LR->SC with zero idle cycle), and the trap-suppression
// gating itself: feeding mem_read_in/mem_write_in=0 (simulating a trapped
// lr.w/sc.w) must not arm or consume a reservation. Pipeline-level
// interaction (operand/result forwarding into and out of an AMO, a
// misaligned AMO trap) is covered by tb_isa_directed.v's Section O
// instead, mirroring the M extension's split between tb_muldiv_unit.v and
// Section N.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_amo_unit;

    reg clk = 0;
    reg rst_n;

    reg        is_amo;
    reg [4:0]  amo_funct5;
    reg [31:0] mem_addr;
    reg [31:0] old_value;
    reg [31:0] operand;
    reg        mem_read_in;
    reg        mem_write_in;

    wire [31:0] write_data;
    wire        write_enable;
    wire [31:0] rd_value;

    integer errors;
    integer checks;

    amo_unit dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .is_amo       (is_amo),
        .amo_funct5   (amo_funct5),
        .mem_addr     (mem_addr),
        .old_value    (old_value),
        .operand      (operand),
        .mem_read_in  (mem_read_in),
        .mem_write_in (mem_write_in),
        .write_data   (write_data),
        .write_enable (write_enable),
        .rd_value     (rd_value)
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

    // Drives one cycle's inputs and lets the combinational outputs settle.
    // Any state transition (the reservation FSM) is applied on the NEXT
    // posedge, i.e. visible starting with the following do_op call - the
    // same edge-to-edge cadence tb_csr_file.v's clocked tasks use.
    task do_op;
        input        req_is_amo;
        input [4:0]  req_funct5;
        input [31:0] req_addr;
        input [31:0] req_old;
        input [31:0] req_operand;
        input        req_mem_read_in;
        input        req_mem_write_in;
        begin
            @(negedge clk);
            is_amo       = req_is_amo;
            amo_funct5   = req_funct5;
            mem_addr     = req_addr;
            old_value    = req_old;
            operand      = req_operand;
            mem_read_in  = req_mem_read_in;
            mem_write_in = req_mem_write_in;
            #1; // let write_data/write_enable/rd_value settle
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        is_amo = 1'b0; amo_funct5 = 5'b0; mem_addr = 32'b0;
        old_value = 32'b0; operand = 32'b0;
        mem_read_in = 1'b0; mem_write_in = 1'b0;

        rst_n = 0;
        #12 rst_n = 1;

        // ---------------- All nine regular AMO ops ----------------
        do_op(1'b1, `AMO_F5_SWAP, 32'h1000, 32'd10, 32'd20, 1'b1, 1'b1);
        check32(write_data, 32'd20); check1(write_enable, 1'b1); check32(rd_value, 32'd10);

        do_op(1'b1, `AMO_F5_ADD, 32'h1000, 32'd10, 32'd5, 1'b1, 1'b1);
        check32(write_data, 32'd15); check1(write_enable, 1'b1); check32(rd_value, 32'd10);

        do_op(1'b1, `AMO_F5_XOR, 32'h1000, 32'hF0F0F0F0, 32'h0F0F0F0F, 1'b1, 1'b1);
        check32(write_data, 32'hFFFFFFFF);

        do_op(1'b1, `AMO_F5_AND, 32'h1000, 32'hFF00FF00, 32'h0FF00FF0, 1'b1, 1'b1);
        check32(write_data, 32'h0F000F00);

        do_op(1'b1, `AMO_F5_OR, 32'h1000, 32'h0000FFFF, 32'hFFFF0000, 1'b1, 1'b1);
        check32(write_data, 32'hFFFFFFFF);

        do_op(1'b1, `AMO_F5_MIN, 32'h1000, -32'sd5, 32'sd3, 1'b1, 1'b1);
        check32(write_data, -32'sd5); // signed: -5 < 3

        do_op(1'b1, `AMO_F5_MAX, 32'h1000, -32'sd5, 32'sd3, 1'b1, 1'b1);
        check32(write_data, 32'sd3);

        do_op(1'b1, `AMO_F5_MINU, 32'h1000, 32'hFFFFFFFF, 32'd5, 1'b1, 1'b1);
        check32(write_data, 32'd5); // unsigned: 5 < 0xFFFFFFFF

        do_op(1'b1, `AMO_F5_MAXU, 32'h1000, 32'hFFFFFFFF, 32'd5, 1'b1, 1'b1);
        check32(write_data, 32'hFFFFFFFF);

        // ---------------- LR/SC: success ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h2000, 32'hDEADBEEF, 32'b0, 1'b1, 1'b0);
        check1(write_enable, 1'b0); check32(rd_value, 32'hDEADBEEF); // lr.w never writes; returns old value

        do_op(1'b1, `AMO_F5_SC, 32'h2000, 32'b0, 32'hCAFEF00D, 1'b1, 1'b1);
        check1(write_enable, 1'b1); check32(write_data, 32'hCAFEF00D); check32(rd_value, 32'd0); // success

        // ---------------- SC with no prior LR: fails ----------------
        do_op(1'b1, `AMO_F5_SC, 32'h3000, 32'b0, 32'hFFFFFFFF, 1'b1, 1'b1);
        check1(write_enable, 1'b0); check32(rd_value, 32'd1); // failure

        // ---------------- LR then SC to a DIFFERENT address: fails ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h4000, 32'd0, 32'b0, 1'b1, 1'b0);
        do_op(1'b1, `AMO_F5_SC, 32'h4004, 32'b0, 32'hFFFFFFFF, 1'b1, 1'b1);
        check1(write_enable, 1'b0); check32(rd_value, 32'd1);

        // ---------------- LR, then an intervening plain-store-shaped write
        // to the reserved address, then SC: fails ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h5000, 32'd0, 32'b0, 1'b1, 1'b0);
        do_op(1'b0, 5'b0, 32'h5000, 32'b0, 32'hAAAAAAAA, 1'b0, 1'b1); // plain store, is_amo=0
        do_op(1'b1, `AMO_F5_SC, 32'h5000, 32'b0, 32'hFFFFFFFF, 1'b1, 1'b1);
        check1(write_enable, 1'b0); check32(rd_value, 32'd1);

        // ---------------- Back-to-back LR->SC, zero idle cycle ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h6000, 32'h11111111, 32'b0, 1'b1, 1'b0);
        check32(rd_value, 32'h11111111);
        do_op(1'b1, `AMO_F5_SC, 32'h6000, 32'b0, 32'h22222222, 1'b1, 1'b1);
        check1(write_enable, 1'b1); check32(write_data, 32'h22222222); check32(rd_value, 32'd0);

        // ---------------- Trap-gating: a "trapped" lr.w must not arm a
        // reservation - mem_read_in=0 even though is_amo/funct5 say LR ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h7000, 32'd0, 32'b0, 1'b0, 1'b0); // mem_read_in=0: trapped
        do_op(1'b1, `AMO_F5_SC, 32'h7000, 32'b0, 32'hFFFFFFFF, 1'b1, 1'b1);
        check1(write_enable, 1'b0); check32(rd_value, 32'd1); // still fails - no reservation was armed

        // ---------------- Trap-gating: a "trapped" sc.w must not consume
        // an existing valid reservation ----------------
        do_op(1'b1, `AMO_F5_LR, 32'h8000, 32'd0, 32'b0, 1'b1, 1'b0);
        do_op(1'b1, `AMO_F5_SC, 32'h8000, 32'b0, 32'hDEADC0DE, 1'b1, 1'b0); // mem_write_in=0: trapped
        check1(write_enable, 1'b0); // trapped SC itself never writes
        do_op(1'b1, `AMO_F5_SC, 32'h8000, 32'b0, 32'hFEEDFACE, 1'b1, 1'b1); // real SC, reservation still live
        check1(write_enable, 1'b1); check32(write_data, 32'hFEEDFACE); check32(rd_value, 32'd0);

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
