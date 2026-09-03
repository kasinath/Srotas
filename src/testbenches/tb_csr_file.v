// ============================================================================
// Testbench: tb_csr_file
// File: tb_csr_file.v
//
// Directed unit test for csr_file.v, standalone from the pipeline - CSR
// instructions are not decoded or wired into ID/EX yet (see
// docs/roadmap.md, Phase 1). Exercises the generic software read/write
// port, the hardware trap-entry and mret interfaces, the write-priority
// ordering between them, and the read-only/WARL masking on
// mstatus/mtvec/mepc/misa/mip/mvendorid-family registers.
// ============================================================================

`timescale 1ns/1ps
`include "rv32i_defines.vh"

module tb_csr_file;

    reg clk = 0;
    reg rst_n;

    reg  [11:0] addr;
    reg  [31:0] wdata;
    reg         write_en;
    wire [31:0] rdata;

    reg         trap_en;
    reg  [31:0] trap_pc, trap_cause, trap_value;
    reg         mret_en;

    wire [31:0] mtvec_q, mepc_q;
    wire        mstatus_mie_q;

    integer errors;
    integer checks;

    csr_file dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr          (addr),
        .wdata         (wdata),
        .write_en      (write_en),
        .rdata         (rdata),
        .trap_en       (trap_en),
        .trap_pc       (trap_pc),
        .trap_cause    (trap_cause),
        .trap_value    (trap_value),
        .mret_en       (mret_en),
        .mtvec_q       (mtvec_q),
        .mepc_q        (mepc_q),
        .mstatus_mie_q (mstatus_mie_q)
    );

    always #5 clk = ~clk;

    // Generic 32-bit/1-bit checks report through $time-prefixed pass/fail
    // lines and a final "RESULT: ..." summary, matching the convention in
    // tb_isa_directed.v.
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

    task csr_write;
        input [11:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr = a; wdata = d; write_en = 1'b1;
            @(negedge clk);
            write_en = 1'b0;
        end
    endtask

    task csr_read;
        input [11:0] a;
        begin
            addr = a;
            #1; // let the combinational read settle
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        rst_n = 0; write_en = 0; trap_en = 0; mret_en = 0;
        addr = 12'b0; wdata = 32'b0;
        trap_pc = 32'b0; trap_cause = 32'b0; trap_value = 32'b0;
        @(negedge clk);
        rst_n = 1;

        // ---------------- Reset state ----------------
        csr_read(`CSR_MSTATUS);   check32(rdata, 32'h0000_1800); // MPP=11, rest 0
        csr_read(`CSR_MTVEC);     check32(rdata, 32'h0000_0000);
        csr_read(`CSR_MEPC);      check32(rdata, 32'h0000_0000);
        csr_read(`CSR_MISA);      check32(rdata, 32'h4000_1100); // 'I' + 'M' (Phase 2)
        csr_read(`CSR_MVENDORID); check32(rdata, 32'h0000_0000);
        csr_read(`CSR_MHARTID);   check32(rdata, 32'h0000_0000);
        csr_read(`CSR_MIP);       check32(rdata, 32'h0000_0000); // no interrupt source wired yet

        // ---------------- mstatus: only MIE/MPIE are writable ----------------
        csr_write(`CSR_MSTATUS, 32'hFFFF_FFFF);
        csr_read(`CSR_MSTATUS);
        check32(rdata, 32'h0000_1888); // MPP still forced 11, MIE=MPIE=1
        check1(mstatus_mie_q, 1'b1);

        // ---------------- mtvec: mode field forced to Direct (00) ----------------
        csr_write(`CSR_MTVEC, 32'h8000_0007); // vectored mode (01) requested
        csr_read(`CSR_MTVEC);
        check32(rdata, 32'h8000_0004);
        check32(mtvec_q, 32'h8000_0004);

        // ---------------- mepc: low 2 bits always 0 ----------------
        csr_write(`CSR_MEPC, 32'h0000_1003);
        csr_read(`CSR_MEPC);
        check32(rdata, 32'h0000_1000);

        // ---------------- mscratch/mcause/mtval: plain read/write ----------------
        csr_write(`CSR_MSCRATCH, 32'hDEAD_BEEF);
        csr_read(`CSR_MSCRATCH);
        check32(rdata, 32'hDEAD_BEEF);

        // ---------------- Read-only registers ignore software writes ----------------
        csr_write(`CSR_MISA, 32'hFFFF_FFFF);
        csr_read(`CSR_MISA);
        check32(rdata, 32'h4000_1100); // 'I' + 'M' (Phase 2)

        csr_write(`CSR_MVENDORID, 32'hFFFF_FFFF);
        csr_read(`CSR_MVENDORID);
        check32(rdata, 32'h0000_0000);

        csr_write(`CSR_MIP, 32'hFFFF_FFFF);
        csr_read(`CSR_MIP);
        check32(rdata, 32'h0000_0000);

        // ---------------- mie: only MSIE/MTIE/MEIE are implemented ----------------
        csr_write(`CSR_MIE, 32'hFFFF_FFFF);
        csr_read(`CSR_MIE);
        check32(rdata, 32'h0000_0888);

        // ---------------- Trap entry ----------------
        csr_write(`CSR_MSTATUS, 32'h0000_0008); // MIE=1, MPIE=0
        check1(mstatus_mie_q, 1'b1);

        @(negedge clk);
        trap_en = 1'b1;
        trap_pc = 32'h0000_2004; trap_cause = 32'd11; trap_value = 32'hCAFE_F00D;
        @(negedge clk);
        trap_en = 1'b0;

        csr_read(`CSR_MEPC);   check32(rdata, 32'h0000_2004);
        csr_read(`CSR_MCAUSE); check32(rdata, 32'd11);
        csr_read(`CSR_MTVAL);  check32(rdata, 32'hCAFE_F00D);
        check1(mstatus_mie_q, 1'b0);
        csr_read(`CSR_MSTATUS);
        check1(rdata[7], 1'b1); // MPIE saved the old MIE

        // ---------------- mret ----------------
        @(negedge clk);
        mret_en = 1'b1;
        @(negedge clk);
        mret_en = 1'b0;

        check1(mstatus_mie_q, 1'b1);
        csr_read(`CSR_MSTATUS);
        check1(rdata[7], 1'b1); // MPIE set to 1 by mret

        // ---------------- Priority: trap entry beats a concurrent sw write ----------------
        @(negedge clk);
        trap_en = 1'b1;
        trap_pc = 32'h0000_3000; trap_cause = 32'd2; trap_value = 32'h0;
        addr = `CSR_MEPC; wdata = 32'hFFFF_FFFF; write_en = 1'b1;
        @(negedge clk);
        trap_en = 1'b0; write_en = 1'b0;

        csr_read(`CSR_MEPC);
        check32(rdata, 32'h0000_3000);

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
