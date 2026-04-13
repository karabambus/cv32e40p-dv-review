// Top level testbench for the CV32E40P
//
// Copyright 2025 Eclipse Foundation
// SPDX-License-Identifier: Apache-2.0 WITH SHL-0.51
//
// Copyright 2017 Embecosm Limited <www.embecosm.com>
// Copyright 2018 Robert Balas <balasr@student.ethz.ch>
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Contributor: Robert Balas <balasr@student.ethz.ch>
//              Jeremy Bennett <jeremy.bennett@embecosm.com>

`timescale 1ns/100ps

module tb_top
    #(parameter INSTR_RDATA_WIDTH = 32,
      parameter RAM_ADDR_WIDTH    = 22,
      parameter FPU_EN            = 0
     );

    // boot_addr: set from +boot_addr=<hex> plusarg, or extracted from ELF header
    // when +elf_file= is used. Defaults to 0x100 if neither is provided.
    logic [31:0] boot_addr;
    initial boot_addr = 32'h100;

    const int CLK_PHASE_HI        = 5;
    const int CLK_PHASE_LO        = 5;
    const int CLK2NRESET_DELAY    = 1;
    const int RESET_ASSERT_CYCLES = 4;

    // clock and reset for tb
    logic                   core_clk;
    logic                   core_rst_n;

    // cycle counter
    int unsigned            cycle_cnt_q;

    // exit status flags
    logic                   tests_passed;
    logic                   tests_failed;
    logic                   exit_valid;
    logic [31:0]            exit_value;

    // strings for $display() and plusarg processing
    string id = "tb_top";
    string wave_file;

    // OBI instruction bus
    logic                         instr_req;
    logic                         instr_gnt;
    logic                         instr_rvalid;
    logic [31:0]                  instr_addr;
    logic [INSTR_RDATA_WIDTH-1:0] instr_rdata;

    // OBI data bus
    logic                         data_req;
    logic                         data_gnt;
    logic                         data_rvalid;
    logic [31:0]                  data_addr;
    logic                         data_we;
    logic [3:0]                   data_be;
    logic [31:0]                  data_rdata;
    logic [31:0]                  data_wdata;

    // IRQ (32-bit, from mm_ram)
    logic [31:0]                  irq;
    logic                         irq_ack;
    logic [4:0]                   irq_id;

    // dumps waves
    initial begin
        if ($value$plusargs("wave_file=%s", wave_file)) begin
            $display("[%s] @ t=%0t: dumping waves to %s", id, $time, wave_file);
            $dumpfile(wave_file);
            $dumpvars(0, tb_top);
        end
    end

    // Load the test program into RAM.
    //
    // +elf_file=<path>      Read ELF32 header to extract the entry point (boot_addr),
    //                       derive the pre-generated <base>.hex path, load via $readmemh.
    //                       Requires "make gen" to pre-generate the .hex files.
    //
    // +test_program=<path>  Legacy: load a Verilog hex file directly.
    //                       boot_addr must be supplied via +boot_addr=<hex>.
    initial begin: load_prog
        automatic string  test_program;
        automatic string  elf_file;
        automatic string  hex_file;
        automatic logic [7:0] ehdr[0:51];  // ELF32 header (52 bytes)
        automatic integer     elf_fd;
        automatic int         last_dot;

        if ($value$plusargs("elf_file=%s", elf_file)) begin
            // Extract entry point: e_entry is at byte offset 24, little-endian
            elf_fd = $fopen(elf_file, "rb");
            if (elf_fd == 0)
                $fatal(1, "[%s] Cannot open ELF file: %s", id, elf_file);
            void'($fread(ehdr, elf_fd));
            $fclose(elf_fd);
            boot_addr = {ehdr[27], ehdr[26], ehdr[25], ehdr[24]};

            // Derive <base>.hex by stripping the last file extension and appending .hex
            last_dot = -1;
            for (int i = elf_file.len() - 1; i >= 0; i--) begin
                if (elf_file.getc(i) == 8'h2e && last_dot == -1)
                    last_dot = i;
            end
            hex_file = (last_dot >= 0) ? {elf_file.substr(0, last_dot - 1), ".hex"}
                                       : {elf_file, ".hex"};

            if ($test$plusargs("verbose"))
                $display("[%s] @ t=%0t: loading ELF %0s, boot_addr=0x%08h, hex=%0s",
                         id, $time, elf_file, boot_addr, hex_file);
            $readmemh(hex_file, mm_ram_i.dp_ram_inst.mem);

        end else if ($value$plusargs("test_program=%s", test_program)) begin
            if (!$value$plusargs("boot_addr=%h", boot_addr))
                boot_addr = 32'h100;
            if ($test$plusargs("verbose"))
                $display("[%s] @ t=%0t: loading test-program %0s", id, $time, test_program);
            $readmemh(test_program, mm_ram_i.dp_ram_inst.mem);

        end else begin
            $display("[%s] @ t=%0t: No +elf_file or +test_program specified... terminating.",
                     id, $time);
            end_of_sim();
        end
    end

    initial begin: clock_gen
        core_clk = 1'b1;
        // FIXME: using a forever loop here hangs Verilator
        repeat(10_000_000) begin
            #CLK_PHASE_HI core_clk = 1'b0;
            #CLK_PHASE_LO core_clk = 1'b1;
        end
    end: clock_gen


    // timing format, reset generation and parameter check
    initial begin
        $timeformat(-9, 0, "ns", 9);
        core_rst_n   = 1'b1; // deassert reset at t=0

        @(negedge core_clk) core_rst_n = 1'b0; // assert reset
        // hold in reset for a few cycles
        repeat (RESET_ASSERT_CYCLES) @(posedge core_clk);
        // start running
        #CLK2NRESET_DELAY core_rst_n = 1'b1;
        core_rst_n = 1'b1;
        if($test$plusargs("verbose")) begin
            $display("[%s] @ t=%0t: reset deasserted", id, $time);
        end

        if ( !( (INSTR_RDATA_WIDTH == 128) || (INSTR_RDATA_WIDTH == 32) ) ) begin
         $fatal(2, "[%s] @ t=%0t: invalid INSTR_RDATA_WIDTH, choose 32 or 128", id, $time);
        end
    end

    // abort after n cycles, if we want to
    always_ff @(posedge core_clk, negedge core_rst_n) begin
        automatic int maxcycles;
        if($value$plusargs("maxcycles=%d", maxcycles)) begin
            if (~core_rst_n) begin
                cycle_cnt_q <= 0;
            end else begin
                cycle_cnt_q     <= cycle_cnt_q + 1;
                if (cycle_cnt_q >= maxcycles) begin
                    $fatal(2, "[%s] @ t=%0t: Simulation aborted due to maximum cycle limit", id, $time);
                end
            end
        end
    end

    // Check for virtual peripheral status flags that the test-program may (or
    // may not) use to indicate the end of a test.
    always_ff @(posedge core_clk) begin: vp_check
        if (tests_passed) begin
            $display("[%s] @ t=%0t: ALL TESTS PASSED", id, $time);
            end_of_sim();
        end
        if (tests_failed) begin
            $display("[%s] @ t=%0t: TEST(S) FAILED!", id, $time);
            end_of_sim();
        end
        if (exit_valid) begin
            if (exit_value == 0)
                $display("[%s] @ %0t: EXIT SUCCESS", id, $time);
            else
                $display("[%s] @ %0t: EXIT FAILURE: %d", id, $time, exit_value);
            end_of_sim();
        end
    end

    // End Of Simulation control:
    //   - If the test-program invokes the virtual peripheral status flags
    //     (see 'vp_check' block, above) then end_of_sim() is called and it
    //     will trigger the 'final' block.
    //   - If the test-program invokes the C stdlib macro EXIT_SUCCESS or
    //     EXIT_FAILURE, then the simulation process is terminated and
    //     end_of_sim() is never called.  In this case the 'final' block
    //     is used to display the end of simulation messages, if any.
    task end_of_sim();
        $finish;
    endtask

    final begin
        if (wave_file != "") begin
            $display("[%s] @ t=%0t: waves written to %s", id, $time, wave_file);
        end
        $display("\n[%s] @ t=%0t: simulation ending...", id, $time);
    end

    // DUT — version selected at compile time inside cv32e40p_dut_wrap
    cv32e40p_dut_wrap
      #(.INSTR_RDATA_WIDTH (INSTR_RDATA_WIDTH),
        .FPU_EN            (FPU_EN))
    dut_i
      (.clk_i          (core_clk),
       .rst_ni         (core_rst_n),
       .boot_addr_i    (boot_addr),
       .instr_req_o    (instr_req),
       .instr_gnt_i    (instr_gnt),
       .instr_rvalid_i (instr_rvalid),
       .instr_addr_o   (instr_addr),
       .instr_rdata_i  (instr_rdata),
       .data_req_o     (data_req),
       .data_gnt_i     (data_gnt),
       .data_rvalid_i  (data_rvalid),
       .data_addr_o    (data_addr),
       .data_we_o      (data_we),
       .data_be_o      (data_be),
       .data_wdata_o   (data_wdata),
       .data_rdata_i   (data_rdata),
       .irq_i          (irq),
       .irq_ack_o      (irq_ack),
       .irq_id_o       (irq_id));

    // mm_ram: memory mapped virtual peripheral and RAM model
    mm_ram
        #(.RAM_ADDR_WIDTH  (RAM_ADDR_WIDTH),
          .INSTR_RDATA_WIDTH(INSTR_RDATA_WIDTH))
    mm_ram_i
        (.clk_i          (core_clk),
         .rst_ni         (core_rst_n),
         .dm_halt_addr_i (32'h1A110800),

         .instr_req_i    (instr_req),
         .instr_addr_i   ({{10{1'b0}}, instr_addr[RAM_ADDR_WIDTH-1:0]}),
         .instr_rdata_o  (instr_rdata),
         .instr_rvalid_o (instr_rvalid),
         .instr_gnt_o    (instr_gnt),

         .data_req_i     (data_req),
         .data_addr_i    (data_addr),
         .data_we_i      (data_we),
         .data_be_i      (data_be),
         .data_wdata_i   (data_wdata),
         .data_rdata_o   (data_rdata),
         .data_rvalid_o  (data_rvalid),
         .data_gnt_o     (data_gnt),

         .irq_id_i       (irq_id),
         .irq_ack_i      (irq_ack),
         .irq_o          (irq),

         .debug_req_o    (),
         .pc_core_id_i   ('0),

         .tests_passed_o (tests_passed),
         .tests_failed_o (tests_failed),
         .exit_valid_o   (exit_valid),
         .exit_value_o   (exit_value));

endmodule // tb_top
