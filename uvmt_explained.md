# UVMT — UVM Testbench for CV32E20

`uvmt` (UVM Testbench) is the top layer of the verification environment. It is the simulation entry point: it instantiates the DUT, wires up all SystemVerilog interfaces, binds non-intrusive checkers, and launches the UVM test via `run_test()`. Everything above the RTL boundary lives here.

---

## Repository layout

```
tb/uvmt/                    ← top-level SV files (this document's focus)
env/uvme/                   ← UVM environment (agents, virtual sequencer, scoreboard)
tests/uvmt/                 ← test classes and virtual sequences
mk/uvmt/                    ← Makefile fragments (one per simulator)
sim/uvmt/                   ← working directory for simulation runs
```

---

## File map

| File | Purpose |
|---|---|
| `uvmt_cv32e20_tb.sv` | **Top module** — instantiates DUT wrap, all interfaces, bind statements, and UVM entry point |
| `uvmt_cv32e20_dut_wrap.sv` | **DUT wrapper** — instantiates `cve2_top_tracing`, connects OBI buses and control signals |
| `uvmt_cv32e20_pkg.sv` | **Package** — imports, includes all constants/types/tests in compile order |
| `uvmt_cv32e20_tb_ifs.sv` | **Custom interfaces** — clock gen, VP status, core status, ISA coverage, debug coverage/assert |
| `uvmt_cv32e20_constants.sv` | Package-level numeric constants |
| `uvmt_cv32e20_tdefs.sv` | Enums: `test_program_type_e`, `ref_model_e` |
| `uvmt_cv32e20_vseq_lib.sv` | Virtual sequence library (coordinated stimulus) |
| `uvmt_cv32e20_test_cfg.sv` | Test configuration class — timeouts, firmware path, reference model selector |
| `uvmt_cv32e20_test_randvars.sv` | Randomizable test knobs |
| `uvmt_cv32e20_base_test.sv` | Abstract base test — UVM phase flow, watchdog, heartbeat |
| `uvmt_cv32e20_general_purpose_test.sv` | Concrete test — loads firmware, waits for VP exit/pass/fail signals |
| `uvmt_cv32e20_step_compare.sv` | ISS step-and-compare logic |
| `uvmt_cv32e20_imperas_dv_wrap.sv` | Imperas DV reference model wrapper |
| `uvmt_cv32e20_interrupt_assert.sv` | Interrupt protocol assertions (bound to DUT wrap) |
| `uvmt_cv32e20_debug_assert.sv` | Debug mode assertions |
| `uvmt_cv32e20_dut_chk.sv` | Additional DUT-level checks |
| `uvmt_cv32e20_macros.sv` | Local macro definitions |
| `uvmt_cv32e20.flist` | Compilation file list in dependency order |

---

## Top-level module: `uvmt_cv32e20_tb`

`uvmt_cv32e20_tb` is a plain SystemVerilog module (not a class). It is the simulation top. The simulator elaborates it, then UVM takes over inside it.

### Parameters

```systemverilog
parameter int CORE_PARAM_NUM_MHPMCOUNTERS = 1;  // overridable via +define+SET_NUM_MHPMCOUNTERS
parameter int ENV_PARAM_INSTR_ADDR_WIDTH  = 32;
parameter int ENV_PARAM_INSTR_DATA_WIDTH  = 32;
parameter int ENV_PARAM_RAM_ADDR_WIDTH    = 22;
```

### Interface instances

All interfaces are declared at module scope and passed to sub-instances either by name or via `.*`:

```
uvma_clknrst_if      clknrst_if          — clock + active-low reset (drives the whole TB)
uvma_clknrst_if      clknrst_if_iss      — separate clock for the ISS reference model
uvma_debug_if        debug_if            — debug request line to the core
uvma_interrupt_if    interrupt_if        — interrupt bus driven by UVM interrupt agent
uvma_interrupt_if    vp_interrupt_if     — interrupt bus driven by virtual peripheral logic
uvma_obi_memory_if   obi_memory_instr_if — instruction fetch bus (OBI v1.0, read-only)
uvma_obi_memory_if   obi_memory_data_if  — load/store bus (OBI v1.0, read-write)

uvmt_cv32e20_vp_status_if    vp_status_if    — tests_passed/failed, exit_valid/value
uvme_cv32e20_core_cntrl_if   core_cntrl_if   — fetch_en, boot_addr, mtvec_addr …
uvmt_cv32e20_core_status_if  core_status_if  — core_busy, sec_lvl
uvmt_cv32e20_step_compare_if step_compare_if — events for ISS step-and-compare
uvmt_cv32e20_isa_covg_if     isa_covg_if     — ISA coverage event + instruction data

rvviTrace #(.NHART(1),.RETIRE(1)) rvvi_if    — RVVI standard trace interface (for Imperas DV)
uvmt_cv32e20_debug_cov_assert_if debug_cov_assert_if — debug signals for assertions/coverage
```

### Bind statements

`bind` injects sub-modules into existing hierarchies without modifying the RTL source:

```
bind cve2_core
    uvma_rvfi_instr_if rvfi_instr_probe_if(...)
        — probes all RVFI instruction-retirement signals out of the core

bind cve2_cs_registers
    uvma_rvfi_unified_csr_if#(4096,32) rvfi_csr_probe_if(...)
        — probes CSR read/write masks and data out of the register file

bind uvmt_cv32e20_dut_wrap
    uvma_obi_memory_assert_if_wrp obi_instr_memory_assert_i(...)
        — OBI protocol checker on the instruction bus

bind uvmt_cv32e20_dut_wrap
    uvma_obi_memory_assert_if_wrp obi_data_memory_assert_i(...)
        — OBI protocol checker on the data bus

bind uvmt_cv32e20_dut_wrap
    uvmt_cv32e20_interrupt_assert interrupt_assert_i(...)
        — interrupt handling assertions (mcause, mip, mie, ctrl_fsm)
```

The bound interfaces get access to internal RTL signals via hierarchical references without changing the DUT files.

### UVM entry point (`initial` block)

The single `initial` block in the whole environment does three things in order:

1. **Register all virtual interfaces** into `uvm_config_db`. Each agent retrieves its `vif` handle from here in its `build_phase`. The key registrations are:

   ```
   "*.env.clknrst_agent"          → clknrst_if
   "*.env.interrupt_agent"        → interrupt_if
   "*.env.obi_memory_instr_agent" → obi_memory_instr_if
   "*.env.obi_memory_data_agent"  → obi_memory_data_if
   "*.env.debug_agent"            → debug_if
   "*.env.rvfi_agent"             → rvfi_instr_probe_if (bound into cve2_core)
   "*.env.rvfi_agent"             → rvfi_csr_probe_if   (bound into cve2_cs_registers)
   "*"                            → vp_status_if, core_cntrl_if, core_status_if, …
   ```

2. **Fork** two concurrent threads:
   - One calls `imperas_dv.ref_init()` after a 0.9 ns race-avoidance delay.
   - The other calls `uvm_top.run_test()`, which starts the UVM phase machinery.

3. **Capture VP status flags** in an `always @(posedge clk)` block that monitors `vp_status_if` and mirrors `tests_passed`, `tests_failed`, `exit_valid`, `exit_value` back into `uvm_config_db` so the test class can poll them without direct interface access.

### End-of-test `final` block

After `run_test()` returns, a `final` block reads the UVM report server counts (errors, warnings, fatals) and prints an ASCII PASSED/FAILED banner to stdout.

---

## DUT wrapper: `uvmt_cv32e20_dut_wrap`

This module translates between the agent interfaces and the RTL port list of `cve2_top_tracing`.

### Core instantiation

```systemverilog
cve2_top_tracing #(
    .MHPMCounterNum   (MHPMCounterNum),
    .MHPMCounterWidth (MHPMCounterWidth),
    .RV32E            (RV32E),
    .RV32M            (RV32M)
) cv32e20_top_i (...);
```

`cve2_top_tracing` wraps the real `cve2_top` and adds RVFI output ports so the RVFI probe interfaces can be bound into `cve2_core` and `cve2_cs_registers` inside it.

### Bus connections

| Signal group | Direction | Notes |
|---|---|---|
| `obi_memory_instr_if.{req,gnt,rvalid,addr,rdata}` | Core ↔ agent | `we=0`, `be='1` — instruction bus is read-only |
| `obi_memory_data_if.{req,gnt,rvalid,we,be,addr,wdata,rdata}` | Core ↔ agent | Full read/write with byte enables |
| `irq[31:0]` | Agent → core | OR of `irq_uvma` (UVM agent) and `irq_vp` (virtual peripheral) |
| `debug_req` | Agent/VP → core | OR of `debug_req_uvma` and `debug_req_vp` |
| `fetch_enable_i` | `core_cntrl_if` → core | Controlled by the core-control agent |
| `boot_addr_i` | Hardcoded | Fixed at `32'h0000_4000` (overrides `core_cntrl_if.boot_addr`) |

### IRQ acknowledge feedback

The interrupt acknowledge (`irq_ack`) and accepted interrupt ID (`irq_id`) are read back from internal RTL signals rather than dedicated top-level ports:

```systemverilog
assign interrupt_if.irq_id  = cv32e20_top_i.u_cve2_top.u_cve2_core
                                  .id_stage_i.controller_i.exc_cause_o[4:0];
assign interrupt_if.irq_ack = (cv32e20_top_i.u_cve2_top.u_cve2_core
                                  .id_stage_i.controller_i.ctrl_fsm_cs == 4'h7);
```

This is a common technique when the RTL does not expose acknowledge ports at the top level.

### Macro path aliases (for assertions)

```
`define RVFI_INSTR_PATH  rvfi_instr_if
`define RVFI_CSR_PATH    rvfi_csr_if
`define DUT_PATH         cv32e20_top_i
`define CSR_PATH         `DUT_PATH.u_cve2_top.u_cve2_core.cs_registers_i
```

These shorten hierarchical references used by the bound assertion modules.

---

## Custom interfaces (`uvmt_cv32e20_tb_ifs.sv`)

### `uvmt_cv32e20_clk_gen_if`

Generates the simulation clock and reset waveform. Activated by calling `start()`.

```
core_clock_period       = 1500 ps  →  ~666.7 MHz
reset_assert_duration   = 7400 ps
reset_deassert_duration = 7400 ps
```

The clock toggles in a `forever` loop; reset is asserted low then released after the configured duration.

### `uvmt_cv32e20_vp_status_if`

Carries the four signals written by the virtual peripheral memory map:

```
tests_passed  — firmware called the "pass" VP address
tests_failed  — firmware called the "fail" VP address
exit_valid    — exit code has been written
exit_value    — 32-bit exit code
```

The top module's `always` block latches these and re-publishes them via `uvm_config_db` so the test class can terminate cleanly.

### `uvmt_cv32e20_core_status_if`

Read-only view of core status outputs: `core_busy`, `sec_lvl`.

### `uvmt_cv32e20_isa_covg_if`

Provides an event (`ins_valid`) and an instruction record (`ins_t ins`). The ISS wrapper fires this event at each committed instruction to drive ISA functional coverage.

### `uvmt_cv32e20_step_compare_if`

Used by the ISS step-and-compare flow. Contains events for both sides:

```
ovp_cpu_valid / ovp_cpu_trap / ovp_cpu_halt   — from reference model
riscv_retire  / riscv_trap  / riscv_halt      — from RTL (via RVFI)
```

Step-compare logic synchronises these two streams and reports mismatches.

### `uvmt_cv32e20_debug_cov_assert_if`

Wires together all signals needed by debug assertions and coverage: `fetch_enable`, interrupts, CSR ops, controller FSM state, WFI, trigger match, `debug_req`, `dcsr`, `depc`, etc. Most ports are currently unconnected (`()`) — this is work-in-progress for the CV32E20 port.

---

## Package: `uvmt_cv32e20_pkg`

Compiled as a SystemVerilog package. Include order matters:

```
1. uvmt_cv32e20_constants.sv       — numeric constants
2. uvmt_cv32e20_tdefs.sv           — enums (test_program_type_e, ref_model_e)
3. uvmt_cv32e20_vseq_lib.sv        — virtual sequence library
4. uvmt_cv32e20_test_cfg.sv        — test configuration class
5. uvmt_cv32e20_test_randvars.sv   — randomizable knobs
6. uvmt_cv32e20_base_test.sv       — abstract base test
7. uvmt_cv32e20_general_purpose_test.sv  — concrete firmware test
```

The package imports:

```
uvm_pkg                       — UVM standard library
uvme_cv32e20_pkg              — environment (agents, env, scoreboard)
uvmc_rvfi_reference_model_pkg — RVFI reference model comparison
uvma_core_cntrl_pkg           — core-control agent types
uvml_hrtbt_pkg                — heartbeat utility
uvml_logs_pkg                 — logging utility
```

After the package declaration, `uvmt_cv32e20_tb_ifs.sv` is `\`include`d at file scope (not inside the package) because interfaces cannot be declared inside packages.

---

## Test class hierarchy

```
uvm_test
  └── uvmt_cv32e20_base_test_c          (abstract)
        └── uvmt_cv32e20_general_purpose_test_c
```

### Base test (`uvmt_cv32e20_base_test_c`)

Owns: `test_cfg`, `test_randvars`, `env_cfg`, `env_cntxt`, the UVM environment, and the virtual sequencer.

UVM phase flow:

| Phase | Action |
|---|---|
| `build_phase` | Create config objects, retrieve `vif` handles from `uvm_config_db`, create environment |
| `connect_phase` | Connect virtual sequencer sequencer handles |
| `start_of_simulation` | Print topology (optional) |
| `run_phase` | Fork: watchdog timeout + `reset_phase` → `configure_phase` → `main_phase` |
| `reset_phase` | Assert/deassert reset via `clknrst_agent` virtual sequence |
| `configure_phase` | Load firmware ELF into instruction memory via DPI-C |
| `main_phase` | Raise UVM objection, run test virtual sequences |
| `final_phase` | Set `sim_finished` flag in `uvm_config_db` for the `final` block |

A heartbeat monitor (`uvml_hrtbt_c`) detects hang conditions during `run_phase`.

### General purpose test (`uvmt_cv32e20_general_purpose_test_c`)

- Selects test program type `GENERAL_PURPOSE`.
- Optionally randomizes: debug requests, interrupt injection, fetch-enable toggling.
- Starts firmware execution by deasserting reset and asserting `fetch_enable`.
- Polls `uvm_config_db` for `tp` (tests_passed), `tf` (tests_failed), or `evalid` (exit_valid).
- Waits 100 additional clock cycles after completion, then drops the UVM objection.

### Test configuration (`uvmt_cv32e20_test_cfg_c`)

Key fields:

```
startup_timeout     — time limit before reset is released
heartbeat_period    — period between heartbeat checks
watchdog_timeout    — global simulation timeout
test_program_type   — enum: GENERAL_PURPOSE, NO_TEST_PROGRAM, …
ref_model           — enum: NONE, SPIKE, IMPERAS_DV, BOTH
firmware            — path to ELF/hex (parsed from +firmware=<path> plusarg)
```

---

## Environment layer: `uvme_cv32e20_env`

Lives in `env/uvme/`. The UVMT layer is a shell around this.

### Agents (8 total)

| Agent | Interface | Role |
|---|---|---|
| `uvma_clknrst_agent` | `uvma_clknrst_if` | Clock and reset generation |
| `uvma_interrupt_agent` | `uvma_interrupt_if` | Inject interrupts into `irq[31:0]` |
| `uvma_debug_agent` | `uvma_debug_if` | Drive `debug_req` |
| `uvma_obi_memory_agent` (×2) | `uvma_obi_memory_if` | Respond to instruction and data memory requests |
| `uvma_rvfi_agent` | `rvfi_instr_probe_if`, `rvfi_csr_probe_if` | Monitor all instruction retirements and CSR accesses |
| `uvma_isacov_agent` | `uvmt_cv32e20_isa_covg_if` | Collect ISA functional coverage |
| `uvma_cv32e20_core_cntrl_agent` | `uvme_cv32e20_core_cntrl_if` | Drive `fetch_enable`, `boot_addr`, etc. |

### Virtual peripheral (VP) system

VPs are memory-mapped devices emulated by the OBI data-memory agent. When the core writes to a VP address the agent interprets the write and triggers an action:

| Address | VP name | Function |
|---|---|---|
| `0x10000000` | `vp_virtual_printer` | Write character to simulation log |
| `0x15000000` | `vp_interrupt_timer` | Schedule a timer interrupt |
| `0x15000008` | `vp_debug_control` | Request a debug halt from firmware |
| `0x15001000` | `vp_rand_num` | Return a random 32-bit value |
| `0x15001004` | `vp_cycle_counter` | Return cycle count |
| `0x20000000` | `vp_status_flags` | Set `tests_passed` / `tests_failed` / `exit_valid` |
| `0x20000008` | `vp_sig_writer` | Write compliance signature to file |

Firmware writes to these addresses using normal store instructions. The OBI agent intercepts the transaction and drives the corresponding interface signal or side effect.

### Predictor and scoreboard

- The **predictor** observes stimulus (from agents) and computes the expected architectural state.
- The **scoreboard** compares predicted state against observed state (from RVFI).
- When a reference model (`IMPERAS_DV` or `SPIKE`) is enabled, its output is also compared.

---

## RVFI — RISC-V Formal Interface

RVFI is the primary observation channel. It is a standardised set of signals the RTL drives for every retired instruction:

```
rvfi_valid      — this retirement is valid
rvfi_order      — instruction retirement sequence number
rvfi_insn       — 32-bit instruction word
rvfi_trap       — instruction caused a trap
rvfi_halt       — core is halting
rvfi_dbg        — debug-mode trap
rvfi_dbg_mode   — core is in debug mode
rvfi_intr       — interrupt taken
rvfi_mode       — privilege mode
rvfi_pc_rdata   — PC at instruction fetch
rvfi_pc_wdata   — next PC
rvfi_rs1/rs2/rs3_addr, _rdata
rvfi_rd1_addr, _wdata
rvfi_mem_addr, _rdata/_wdata, _rmask/_wmask
```

The RVFI signals are physically wired inside `cve2_top_tracing`. The bound `rvfi_instr_probe_if` copies them out so the `uvma_rvfi_agent` can read them without hierarchical references from the TB top.

CSR accesses are captured separately via `rvfi_csr_probe_if`, which carries read/write masks and data for all 4096 possible CSR addresses.

---

## Step-and-compare with Imperas DV

When `USE_ISS=IMPERAS` is set:

1. `uvmt_cv32e20_imperas_dv_wrap` instantiates the Imperas OVPsim ISS and connects it to the `rvvi_if` trace interface.
2. `imperas_dv.ref_init()` loads the same ELF firmware into the ISS at time 0.
3. The ISS steps one instruction at a time, driven by RVFI retirements from the RTL.
4. `uvmt_cv32e20_step_compare` compares PC, register file, and memory access fields after each step.
5. Any mismatch raises a UVM error.

---

## Build infrastructure

### Main Makefile fragment: `mk/uvmt/uvmt.mk`

Key variables:

```makefile
CV_CORE_LC   = cv32e20         # core name (lowercase)
SIMULATOR    = dsim            # target simulator: dsim | xrun | vsim | vcs | riviera
USE_ISS      = NONE            # reference model: NONE | IMPERAS | SPIKE
UVM_TEST_NAME = uvmt_cv32e20_general_purpose_test_c
SEED         = 1               # random seed ("random" picks a new one each run)
```

Simulator-specific fragments are included conditionally:

```makefile
include $(MK_DIR)/dsim.mk
# or xrun.mk / vsim.mk / vcs.mk / riviera.mk
```

### Key targets

| Target | Action |
|---|---|
| `make compile` | Compile RTL + TB (runs file list through simulator) |
| `make elaborate` | Elaborate the design |
| `make simulate` | Elaborate + run one test (passes `+UVM_TESTNAME` and firmware path) |
| `make compliance` | Run RISC-V compliance suite |
| `make embench` | Run EMBench benchmark suite |
| `make wave` | Dump waveforms |

### Compilation file list: `uvmt_cv32e20.flist`

Compiled in dependency order:

```
1.  UVM utilities (heartbeat, logs, scoreboards, memory model)
2.  Agent packages (clknrst, interrupt, OBI memory, debug, core_cntrl, RVFI, isacov)
3.  Reference model and scoreboard packages
4.  External verification libraries (Imperas DV)
5.  uvme_cv32e20_pkg  — environment package
6.  uvmt_cv32e20_pkg  — testbench package (includes all TB files)
7.  uvmt_cv32e20_tb.sv — top module
8.  Assertion and coverage modules
```

---

## Simulation flow end-to-end

```
Simulator elaborates uvmt_cv32e20_tb
  │
  ├─ Instantiates uvmt_cv32e20_dut_wrap (DUT + OBI buses)
  ├─ Instantiates all agent interfaces
  ├─ Binds RVFI probe interfaces into RTL hierarchy
  ├─ Binds OBI + interrupt assertion checkers
  │
  └─ initial block runs:
       ├─ Registers all vif handles in uvm_config_db
       ├─ fork:
       │    ├─ imperas_dv.ref_init() at #0.9ns
       │    └─ uvm_top.run_test("uvmt_cv32e20_general_purpose_test_c")
       │         │
       │         ├─ build_phase:  create env, retrieve vifs
       │         ├─ reset_phase:  assert then release reset via clknrst agent
       │         ├─ configure_phase: load ELF into OBI memory model via DPI-C
       │         ├─ main_phase:   assert fetch_enable, run virtual sequences
       │         │                poll vp_status_if for pass/fail/exit
       │         └─ final_phase:  set sim_finished flag
       │
       └─ final block prints PASSED/FAILED banner
```

---

## Known work-in-progress items (TODOs in code)

- `debug_cov_assert_if` has most ports unconnected — debug coverage/assertions are placeholders from the CV32E40P version and need CV32E20-specific wiring.
- `uvmt_cv32e20_debug_assert` is instantiated but its `cov_assert_if` port is commented out.
- `rvvi_memory_vif` config_db registration is commented out (reference model memory sharing not yet wired).
- `boot_addr_i` is hardcoded to `0x0000_4000` instead of using `core_cntrl_if.boot_addr`.
- Imperas DV is instantiated unconditionally; the `ifdef USE_ISS_IMPERAS` guard is commented out.
