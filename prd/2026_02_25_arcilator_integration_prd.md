# Arcilator Integration Plan: RHDL -> CIRCT (MLIR) -> Native Simulation

**Status:** Proposed
**Date:** 2026-02-25

## Context

RHDL currently supports multiple simulation backends for the Apple II:

| Backend | Pipeline | Apple II Rate | Startup |
|---------|----------|---------------|---------|
| IR Compiler | RHDL -> IR JSON -> Rust AOT (rustc) | ~0.28M cycles/s | 6-8s |
| Verilator | RHDL -> Verilog -> Verilator (C++) -> .so | ~5.6M cycles/s | 15-30s |

[Arcilator](https://circt.llvm.org/docs/Dialects/Arc/) is a cycle-accurate hardware simulator in the [CIRCT](https://github.com/llvm/circt) project that compiles hardware designs through MLIR's `arc` dialect down to LLVM IR, then to native machine code. Benchmarks on RISC-V cores (Rocket Chip, BOOM) show arcilator matching or beating Verilator performance while staying entirely within the MLIR/LLVM ecosystem.

RHDL already has a FIRRTL 5.1.0 code generator (`lib/rhdl/codegen/circt/firrtl.rb`) and a Verilog exporter, either of which can serve as the input to CIRCT tooling. The existing Verilator runner pattern (export -> compile -> FFI bridge via Fiddle) is directly reusable for arcilator.

This PRD proposes adding arcilator as a new simulation backend and benchmarking it against Verilator and the IR Compiler on the Apple II example.

## Goals

1. Establish an end-to-end pipeline: RHDL -> FIRRTL -> firtool -> arcilator -> native simulation binary.
2. Create a Ruby FFI bridge (Fiddle) to drive the arcilator-compiled simulation, following the same API pattern as VerilogRunner.
3. Run the Apple II benchmark suite across all three backends (IR Compiler, Verilator, Arcilator) and compare: initialization time, simulation rate (cycles/s), correctness (cycle-level output parity).
4. Validate correctness by comparing VCD traces or memory/register snapshots between backends.

## Non-Goals

- Full production integration of arcilator into the interactive `rhdl examples apple2` runner (that comes after evaluation).
- Supporting arcilator for all example systems (MOS6502, GameBoy, RISC-V) in this phase.
- Replacing Verilator -- this is an evaluation of arcilator as a complementary or alternative backend.
- Optimizing the FIRRTL export itself (existing generator is sufficient for evaluation).
- Building CIRCT from source -- we use pre-built releases or system packages.

## Phased Plan

### Phase 0: Toolchain Setup & FIRRTL Validation

**Objective:** Verify that CIRCT tooling can consume RHDL-generated FIRRTL for the Apple II and produce MLIR core dialects.

**Steps:**
1. Install CIRCT pre-built binaries (firtool, arcilator) or document build-from-source steps.
2. Export the Apple II design to FIRRTL: `Codegen.circt(Apple2, top_name: 'apple2')`.
3. Run `firtool --ir-hw apple2.fir` to lower FIRRTL to HW+Comb+Seq core dialects.
4. Fix any FIRRTL generation issues (unsupported constructs, memory semantics, clock inference).
5. Verify firtool produces clean MLIR output without errors or unsupported-op diagnostics.

**Red/Green:**
- Red: `firtool` rejects the generated FIRRTL or produces diagnostics.
- Green: `firtool --ir-hw apple2.fir` succeeds cleanly and produces valid MLIR.

**Exit Criteria:**
- FIRRTL for the full Apple II design compiles through firtool without errors.
- Document any FIRRTL generator patches needed.

**Alternative path:** If FIRRTL has blocking issues, try the Verilog path instead: `Codegen.verilog(Apple2)` -> `circt-verilog apple2.v` -> `firtool`. RHDL generates Verilog-2001 which the slang frontend in CIRCT can parse. However, the FIRRTL path is preferred since firtool's FIRRTL frontend is more mature than the SystemVerilog/slang path for arcilator use cases.

---

### Phase 1: Arcilator Compilation & C++ Harness

**Objective:** Compile the Apple II design through arcilator to a shared library and write a C++ simulation harness.

**Steps:**
1. Run `arcilator apple2.mlir --state-file=apple2_state.json` to compile MLIR to an object file (or use the JIT/AOT modes arcilator provides).
2. Write a C++ harness (`sim_wrapper.cpp`) modeled on the existing Verilator wrapper pattern:
   - `sim_create()` / `sim_destroy()` -- allocate/free simulation state.
   - `sim_reset()` -- toggle reset sequence (matching Apple II reset protocol).
   - `sim_eval()` -- evaluate one combinational step.
   - `sim_poke(name, value)` / `sim_peek(name)` -- drive inputs / read outputs.
   - `sim_run_cycles(n, halted_out)` -- batch cycle execution with memory bridging.
   - `sim_load_memory(data, offset, len)` -- bulk memory initialization.
3. Compile harness + arcilator output into a shared library (`.so`).
4. Document the full build command sequence.

**Key arcilator integration details:**
- Arcilator produces functions that operate on a flat state buffer (all registers, memories packed into a byte array).
- The state layout is described by a JSON state file (`--state-file`).
- The harness needs to map signal names to byte offsets in the state buffer.
- `arcilator-runtime.h` from CIRCT provides helper macros for state access.

**Red/Green:**
- Red: Arcilator rejects the MLIR, or the harness doesn't compile/link.
- Green: A shared library is produced that can be loaded via `dlopen`.

**Exit Criteria:**
- `libapple2_arc_sim.so` builds successfully.
- Loading the library and calling `sim_create()` returns a valid context.

---

### Phase 2: Ruby FFI Bridge (ArcilatorRunner)

**Objective:** Create an `ArcilatorRunner` class that drives the arcilator-compiled simulation via Fiddle FFI, following the same interface as `VerilogRunner`.

**Steps:**
1. Create `examples/apple2/utilities/runners/arcilator_runner.rb`.
2. Implement the standard runner interface:
   - `initialize(mode:, sim:, sub_cycles:)` -- build if needed, load library.
   - `load_rom(path_or_bytes, base_addr:)` / `load_program(path, base_addr:)`.
   - `reset` / `run_steps(n)` / `run_cycles(n)`.
   - `cpu_state` -- returns `{pc:, a:, x:, y:, sp:, p:, cycles:}`.
   - `read_screen_array` / `screen_dirty?` / `clear_screen_dirty`.
   - `inject_key(ascii)`.
   - `halted?` / `cycle_count`.
3. Wire into `HeadlessRunner` factory as a new `:arcilator` mode.
4. Add dependency check (is `arcilator` binary available in PATH?).

**Red/Green:**
- Red: `ArcilatorRunner.new` fails; `run_steps(100)` crashes or returns garbage.
- Green: Runner initializes, runs 1000 cycles, and `cpu_state` returns plausible register values.

**Exit Criteria:**
- The demo program (`Apple2::DemoProgram`) runs under ArcilatorRunner and produces the expected "APPLE II" text screen output.
- `runner.read_screen_array` matches output from VerilogRunner for the same program after the same cycle count.

---

### Phase 3: Correctness Validation

**Objective:** Verify arcilator simulation produces identical results to Verilator and IR Compiler at the cycle level.

**Steps:**
1. **Snapshot comparison test**: Run the Apple II demo program for 100K cycles on all three backends. After every 10K cycles, capture `cpu_state` and first 256 bytes of screen memory. Assert snapshots match across backends.
2. **Karateka boot test**: Load Karateka memory dump, run 1M cycles on each backend, compare final CPU state and screen contents.
3. **VCD trace comparison** (optional): If arcilator VCD output is available, run a short simulation (10K cycles) and diff traces against Verilator VCD using the `diffvcd.py` approach from `circt/arc-tests`.

**Test location:** `spec/examples/apple2/integration/arcilator_parity_spec.rb`

**Red/Green:**
- Red: Divergence detected between backends (different PC, different screen output).
- Green: All three backends produce identical snapshots at every checkpoint.

**Exit Criteria:**
- Parity spec passes for demo program (100K cycles).
- Parity spec passes for Karateka boot (1M cycles).
- Any divergences are documented with root cause (e.g., X-value handling, reset sequence differences).

---

### Phase 4: Benchmark Comparison

**Objective:** Produce a quantitative performance comparison of all three backends on the Apple II.

**Steps:**
1. Add `:arcilator` backend to `benchmark_apple2` in `BenchmarkTask`.
2. Run benchmarks at 1M and 5M cycles for each backend:
   - IR Compiler (`:ir` / `:compile`)
   - Verilator (`:verilog`)
   - Arcilator (`:arcilator`)
3. Measure and report:
   - **Init time**: Design export + compilation + library loading.
   - **Run time**: Batch execution of N cycles.
   - **Simulation rate**: Cycles per second (steady-state).
   - **Peak memory**: RSS during simulation.
4. Add `rake bench:arcilator[CYCLES]` task.
5. Update `docs/performance.md` with arcilator results.

**Expected results (hypothesis based on published arcilator benchmarks):**

| Backend | Init Time | Rate (Apple II) | Relative |
|---------|-----------|-----------------|----------|
| IR Compiler | 6-8s | ~0.28M cycles/s | 1.0x |
| Verilator | 15-30s | ~5.6M cycles/s | 20x |
| Arcilator | 5-15s | ~3-8M cycles/s | 10-30x |

Arcilator should have faster compilation than Verilator (LLVM JIT vs full C++ compile) and comparable simulation throughput.

**Red/Green:**
- Red: Benchmark crashes, or arcilator is slower than IR Compiler.
- Green: Benchmark completes, arcilator achieves at least 1M cycles/s on Apple II.

**Exit Criteria:**
- Benchmark results for all three backends at 1M and 5M cycles are documented.
- `docs/performance.md` is updated with the new backend row.

---

### Phase 5: Integration & Documentation

**Objective:** Clean up, document, and integrate arcilator as an optional backend.

**Steps:**
1. Add `--mode arcilator` to `examples/apple2/bin/apple2` CLI.
2. Add `arcilator_available?` check to HeadlessRunner (graceful skip if not installed).
3. Add `rake native:check` output for arcilator/firtool availability.
4. Write `docs/arcilator.md` covering:
   - Installation (CIRCT pre-built binaries or build instructions).
   - How the pipeline works (RHDL -> FIRRTL -> firtool -> arcilator -> .so).
   - Performance characteristics vs Verilator and IR Compiler.
   - Known limitations.
5. Add spec for arcilator runner: `spec/examples/apple2/runners/arcilator_runner_spec.rb`.

**Exit Criteria:**
- `rhdl examples apple2 --mode arcilator --demo` works end-to-end (when CIRCT tools are available).
- Documentation is complete and accurate.
- Tests pass (with graceful skip when CIRCT is not installed).

## Acceptance Criteria

All of the following must be true for the work to be considered complete:

1. RHDL-generated FIRRTL for Apple II compiles cleanly through firtool + arcilator.
2. ArcilatorRunner passes the same correctness tests as VerilogRunner (demo program screen output, Karateka boot parity).
3. Benchmark data for all three backends is documented in `docs/performance.md`.
4. The arcilator backend is accessible via CLI (`--mode arcilator`) with graceful degradation when CIRCT tools are absent.
5. All new code has corresponding specs that pass (with conditional skips for missing dependencies).

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| FIRRTL export has unsupported constructs (memories, multi-clock) | Medium | Blocks Phase 0 | Fall back to Verilog path via `circt-verilog`; fix FIRRTL generator incrementally |
| Arcilator doesn't support RHDL's memory modeling (48KB RAM, 12KB ROM) | Medium | Blocks Phase 1 | Arcilator supports FIRRTL memories; may need to split large memories or use external memory bridging in the C++ harness |
| CIRCT pre-built binaries not available for target platform | Low | Delays setup | Document build-from-source with CMake; provide a Dockerfile |
| Arcilator state buffer layout is hard to map to RHDL signal names | Medium | Complicates Phase 2 | Use `--state-file` JSON output to auto-generate signal offset mappings in the harness |
| Cycle-level divergence between arcilator and Verilator | Medium | Complicates Phase 3 | Expected for X-value handling and reset; use VCD comparison to isolate root cause; document acceptable divergences |
| Arcilator slower than expected on Apple II (large combinational logic) | Low | Reduces value | Still valuable as a CIRCT-native path; may benefit from future arcilator optimizations (function splitting, vectorization) |
| Arcilator compilation produces very large LLVM functions | Medium | Slow compile | Known CIRCT issue (#6298); use `-O1` instead of `-O3` for LLVM; accept longer compile times |

## Implementation Checklist

- [ ] **Phase 0: Toolchain Setup & FIRRTL Validation**
  - [ ] Install/verify CIRCT toolchain (firtool, arcilator)
  - [ ] Export Apple II to FIRRTL
  - [ ] Compile FIRRTL through firtool to HW+Comb+Seq MLIR
  - [ ] Fix any FIRRTL generator issues
  - [ ] Document alternative Verilog path if needed
- [ ] **Phase 1: Arcilator Compilation & C++ Harness**
  - [ ] Compile MLIR through arcilator to object/library
  - [ ] Write C++ simulation harness (sim_wrapper pattern)
  - [ ] Build shared library (.so)
  - [ ] Verify library loads and sim_create() works
- [ ] **Phase 2: Ruby FFI Bridge (ArcilatorRunner)**
  - [ ] Create arcilator_runner.rb with standard runner interface
  - [ ] Wire into HeadlessRunner factory
  - [ ] Test basic simulation (demo program)
  - [ ] Verify screen output matches other backends
- [ ] **Phase 3: Correctness Validation**
  - [ ] Snapshot parity test (100K cycles, 3 backends)
  - [ ] Karateka boot parity test (1M cycles)
  - [ ] VCD trace comparison (optional)
  - [ ] Document any acceptable divergences
- [ ] **Phase 4: Benchmark Comparison**
  - [ ] Add arcilator to benchmark_apple2 task
  - [ ] Run benchmarks at 1M and 5M cycles
  - [ ] Add rake bench:arcilator task
  - [ ] Update docs/performance.md
- [ ] **Phase 5: Integration & Documentation**
  - [ ] Add --mode arcilator to Apple II CLI
  - [ ] Add arcilator_available? check
  - [ ] Write docs/arcilator.md
  - [ ] Add arcilator_runner_spec.rb
  - [ ] Update CLAUDE.md if needed

## References

- [Arcilator: Fast and Cycle-Accurate Hardware Simulation in CIRCT](https://llvm.org/devmtg/2023-10/slides/techtalks/Erhart-Arcilator-FastAndCycleAccurateHardwareSimulationInCIRCT.pdf) -- LLVM Dev Meeting 2023 talk by Martin Erhart
- [Arc Dialect Documentation](https://circt.llvm.org/docs/Dialects/Arc/) -- CIRCT official docs
- [circt/arc-tests](https://github.com/circt/arc-tests) -- End-to-end tests and benchmarks for arcilator, including Verilator comparison utilities
- [arcilator-experiments](https://github.com/CircuitCoder/arcilator-experiments) -- Example arcilator usage with FIRRTL inputs and C++ harnesses
- [CIRCT Getting Started](https://circt.llvm.org/docs/GettingStarted/) -- Building CIRCT from source
- [GSIM: Accelerating RTL Simulation](https://arxiv.org/html/2508.02236v1) -- 2025 paper benchmarking arcilator, Verilator, and GSIM on large designs
- [arcilator-runtime.h discussion](https://discourse.llvm.org/t/proper-way-to-obtain-arcilator-runtime-h-for-c-integration/84553) -- LLVM forum thread on C++ integration
