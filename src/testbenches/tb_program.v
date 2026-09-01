// ============================================================================
// Module: tb_program
// File: tb_program.v
// Project: Srotas RISC-V Processor
//
// This is the testbench a student would copy and adapt to run their own
// compiled program: it just points IMEM_INIT_FILE at a $readmemh-format
// .mem file and lets the processor run. No other wiring is needed - the
// instruction and data memories live inside the processor itself.
//
// The bundled mem/program.mem sums 1..10 into x5 (via a real loop, i.e. a
// backward branch), doubles it into x8, and stores both results to data
// memory address 0 and 4, then halts by jumping to itself. This testbench
// checks that demo program's result; swap PROGRAM_FILE to point at your
// own .mem to run something else, and adjust/remove the checks below.
// ============================================================================

`timescale 1ns/1ps

module tb_program;

    // Bare filename, not "mem/program.mem": both Icarus and Vivado resolve
    // $readmemh relative to the simulator's working directory at runtime,
    // and Vivado's project flow auto-exports memory-init files into the
    // xsim run directory by basename only (dropping any subfolder). Run
    // the simulator with its working directory set to wherever this file
    // actually sits - see README.md "Running your own program".
    parameter PROGRAM_FILE = "program.mem";
    parameter RUN_CYCLES   = 200;

    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;

    wire        wb_commit_valid;
    wire [4:0]  wb_commit_rd;
    wire [31:0] wb_commit_data;
    wire [31:0] if_pc_debug;

    srotas_processor #(
        .IMEM_WORDS     (1024),
        .IMEM_INIT_FILE (PROGRAM_FILE),
        .DMEM_BYTES     (4096),
        .DMEM_INIT_FILE ("")
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .wb_commit_valid (wb_commit_valid),
        .wb_commit_rd    (wb_commit_rd),
        .wb_commit_data  (wb_commit_data),
        .if_pc_debug     (if_pc_debug)
    );

    // Trace every architectural register write as the program runs.
    always @(posedge clk) begin
        if (rst_n && wb_commit_valid)
            $display("[%0t] PC redirected/committed: x%0d <= 0x%08h", $time, wb_commit_rd, wb_commit_data);
    end

    initial begin
        $dumpfile("tb_program.vcd");
        $dumpvars(0, tb_program);

        rst_n = 0;
        #12 rst_n = 1;

        #(RUN_CYCLES * 10);

        $display("");
        $display("========================================");
        $display("Final PC: 0x%08h", if_pc_debug);
        $display("x5  (sum)      = %0d (0x%08h)", dut.u_id_stage.u_register_file.registers[5], dut.u_id_stage.u_register_file.registers[5]);
        $display("x8  (sum * 2)  = %0d (0x%08h)", dut.u_id_stage.u_register_file.registers[8], dut.u_id_stage.u_register_file.registers[8]);
        $display("mem[0]         = 0x%08h", {dut.u_mem_stage.u_data_memory.memory[3], dut.u_mem_stage.u_data_memory.memory[2],
                                               dut.u_mem_stage.u_data_memory.memory[1], dut.u_mem_stage.u_data_memory.memory[0]});
        $display("mem[4]         = 0x%08h", {dut.u_mem_stage.u_data_memory.memory[7], dut.u_mem_stage.u_data_memory.memory[6],
                                               dut.u_mem_stage.u_data_memory.memory[5], dut.u_mem_stage.u_data_memory.memory[4]});
        $display("========================================");

        if (PROGRAM_FILE == "program.mem") begin
            if (dut.u_id_stage.u_register_file.registers[5] == 32'd55 &&
                dut.u_id_stage.u_register_file.registers[8] == 32'd110) begin
                $display("RESULT: PASS (sum(1..10) = 55, doubled = 110)");
            end else begin
                $display("RESULT: FAIL");
            end
        end

        $finish;
    end

endmodule
