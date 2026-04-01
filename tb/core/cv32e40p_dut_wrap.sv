// CV32E40P DUT wrapper — selects between v1.8.3 and v1.0.0 RTL at compile time.
//
// Copyright 2025 Eclipse Foundation
// SPDX-License-Identifier: Apache-2.0 WITH SHL-0.51
//
// Compile with +define+CV32E40P_V100 to instantiate the v1.0.0 wrapper
// (cv32e40p_wrapper, PULP_* parameter names, APU ports exposed).
// Without the define, instantiates the v1.8.3 wrapper
// (cv32e40p_tb_wrapper, COREV_* parameter names, no APU ports).

module cv32e40p_dut_wrap
    #(parameter INSTR_RDATA_WIDTH = 32,
      parameter FPU_EN            = 0)
    (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [31:0]                  boot_addr_i,

    // OBI instruction bus
    output logic                         instr_req_o,
    input  logic                         instr_gnt_i,
    input  logic                         instr_rvalid_i,
    output logic [31:0]                  instr_addr_o,
    input  logic [INSTR_RDATA_WIDTH-1:0] instr_rdata_i,

    // OBI data bus
    output logic                         data_req_o,
    input  logic                         data_gnt_i,
    input  logic                         data_rvalid_i,
    output logic [31:0]                  data_addr_o,
    output logic                         data_we_o,
    output logic [3:0]                   data_be_o,
    output logic [31:0]                  data_wdata_o,
    input  logic [31:0]                  data_rdata_i,

    // IRQ
    input  logic [31:0]                  irq_i,
    output logic                         irq_ack_o,
    output logic [4:0]                   irq_id_o
    );

`ifdef CV32E40P_V100
    // v1.0.0: PULP_* parameter names; APU ports exposed and tied off
    cv32e40p_wrapper
      #(.PULP_XPULP      (0),
        .PULP_CLUSTER    (0),
        .FPU             (FPU_EN),
        .PULP_ZFINX      (0),
        .NUM_MHPMCOUNTERS(1))
    core_i
      (.clk_i               (clk_i),
       .rst_ni              (rst_ni),
       .pulp_clock_en_i     (1'b1),
       .scan_cg_en_i        (1'b0),
       .boot_addr_i         (boot_addr_i),
       .mtvec_addr_i        (boot_addr_i),
       .dm_halt_addr_i      (32'h1A110800),
       .hart_id_i           (32'h0),
       .dm_exception_addr_i (32'h1A110808),
       .instr_req_o         (instr_req_o),
       .instr_gnt_i         (instr_gnt_i),
       .instr_rvalid_i      (instr_rvalid_i),
       .instr_addr_o        (instr_addr_o),
       .instr_rdata_i       (instr_rdata_i),
       .data_req_o          (data_req_o),
       .data_gnt_i          (data_gnt_i),
       .data_rvalid_i       (data_rvalid_i),
       .data_we_o           (data_we_o),
       .data_be_o           (data_be_o),
       .data_addr_o         (data_addr_o),
       .data_wdata_o        (data_wdata_o),
       .data_rdata_i        (data_rdata_i),
       // APU tie-offs (FPU internalized in v1.8.3; exposed as APU in v1.0.0)
       .apu_req_o           (),
       .apu_gnt_i           (1'b0),
       .apu_operands_o      (),
       .apu_op_o            (),
       .apu_flags_o         (),
       .apu_rvalid_i        (1'b0),
       .apu_result_i        (32'b0),
       .apu_flags_i         ('0),
       .irq_i               (irq_i),
       .irq_ack_o           (irq_ack_o),
       .irq_id_o            (irq_id_o),
       .debug_req_i         (1'b0),
       .debug_havereset_o   (),
       .debug_running_o     (),
       .debug_halted_o      (),
       .fetch_enable_i      (1'b1),
       .core_sleep_o        ());
`else
    // v1.8.3: COREV_* parameter names; FPU internalized, no APU ports
    cv32e40p_tb_wrapper
      #(.COREV_PULP      (0),
        .COREV_CLUSTER   (0),
        .FPU             (FPU_EN),
        .FPU_ADDMUL_LAT  (0),
        .FPU_OTHERS_LAT  (0),
        .ZFINX           (0),
        .NUM_MHPMCOUNTERS(1))
    core_i
      (.clk_i               (clk_i),
       .rst_ni              (rst_ni),
       .pulp_clock_en_i     (1'b1),
       .scan_cg_en_i        (1'b0),
       .boot_addr_i         (boot_addr_i),
       .mtvec_addr_i        (boot_addr_i),
       .dm_halt_addr_i      (32'h1A110800),
       .hart_id_i           (32'h0),
       .dm_exception_addr_i (32'h1A110808),
       .instr_req_o         (instr_req_o),
       .instr_gnt_i         (instr_gnt_i),
       .instr_rvalid_i      (instr_rvalid_i),
       .instr_addr_o        (instr_addr_o),
       .instr_rdata_i       (instr_rdata_i),
       .data_req_o          (data_req_o),
       .data_gnt_i          (data_gnt_i),
       .data_rvalid_i       (data_rvalid_i),
       .data_we_o           (data_we_o),
       .data_be_o           (data_be_o),
       .data_addr_o         (data_addr_o),
       .data_wdata_o        (data_wdata_o),
       .data_rdata_i        (data_rdata_i),
       .irq_i               (irq_i),
       .irq_ack_o           (irq_ack_o),
       .irq_id_o            (irq_id_o),
       .debug_req_i         (1'b0),
       .debug_havereset_o   (),
       .debug_running_o     (),
       .debug_halted_o      (),
       .fetch_enable_i      (1'b1),
       .core_sleep_o        ());
`endif

endmodule
