# SPARC64 `s1_top` Integration Runtime Parity PRD

## Status

In Progress - 2026-03-09

## Context

The SPARC64 import/unit suite is now broad enough to validate individual imported modules, but it does not yet prove that an imported SPARC64 system behaves correctly at runtime on real programs.

The next gate is higher-level parity on the imported `s1_top` system:

1. staged Verilog executed with Verilator
2. imported RHDL executed on the native IR compiler backend

Unlike the AO486 fetch-only parity harness, this suite must run memory-resident SPARC64 programs through the backend memory ABI rather than a ROM-only stub. The current native runner ABI already supports this pattern for other systems, but `s1_top` does not yet have a SPARC64-specific native extension or runner stack.

The integration suite should follow the repository's existing benchmark pattern and run three compact but non-trivial programs:

1. `prime_sieve`
2. `mandelbrot`
3. `game_of_life`

Each program must live in DRAM, execute through the real `s1_top` Wishbone master interface, and report completion through a stable mailbox contract. The boot path may use a flash-resident shim, but the benchmark itself must be memory-backed and runtime-loaded through the runner ABI.

## Current Execution Notes

1. Phase 1 is implemented and validated locally:
   - native compiler `:sparc64` runner detection is in place
   - sparse flash/DRAM load/read/write APIs are wired through the normalized runner ABI
   - acknowledged Wishbone trace and unmapped-access probes are exposed through the compiler backend
2. Phase 2 is largely implemented and validated locally:
   - `HeadlessRunner`, `IrRunner`, `VerilogRunner`/`VerilatorRunner`, the benchmark registry, and the split boot/program image builder all exist
   - focused runner specs are green
   - the staged Verilator wrapper now mirrors the boot image to low DRAM again and exposes flash bytes through `read_memory`
   - the staged `s1_top` fast-boot source edits now flow through the SPARC64 importer `patches_dir:` path instead of ad hoc staged-tree text rewriting, and the focused importer/bundle specs are green
3. The importer-managed fast-boot import path now stages `os2wb/s1_top.v` correctly without duplicating a basename-level `s1_top.v` copy:
   - the duplicate-top regression is covered in the SPARC64 importer spec
   - the patched import tree now gets through Verilog->CIRCT->RHDL generation cleanly
4. The current staged-Verilog Phase 3 blocker is still the boot shim itself:
   - the importer-managed fast-boot patch series was tightened so the synthetic WAKEUP CPX packet is no longer suppressed in the staged bundle
   - the staged-bundle regression is green with the current patch-set shape, but the real sequential Verilator smoke spec is still red
   - the low-address boot line now reaches the staged wrapper with the expected instruction words, and the current fast-boot tree no longer fails on patch application, importer staging, or malformed runtime export
   - the remaining red is specific to IFU startup control: the shim line is re-fetched from low alias `0x0/0x8/0x10/0x18`, but control-transfer out of that line still does not redirect fetch into the DRAM benchmark image
   - focused code review of the IFU path points to two structural issues still open:
     - the `0001` startup patch was originally stretching `start_on_rst` into a long mode rather than a one-shot pulse, which risks violating the normal `load_bpc`/`load_pcp4` exclusivity around branch redirection
     - even after narrowing that pulse, the boot-shim line is still not handing off, which leaves the uncached fast-boot IFILL semantics themselves as the likely remaining control-path blocker
   - a competing debug mode that mirrors the full program at low alias `0` does fetch the real program bytes, but it still stores to address `0` instead of `MAILBOX_STATUS`; focused code review suggests that mode is fighting the hardcoded fast-boot PC rewrite patches rather than exposing a generic LSU effective-address bug
5. The staged fast-boot path has now been simplified away from executing uncached boot-PROM code:
   - the fast-boot reset vector now targets DRAM directly at `PROGRAM_BASE`
   - the benchmark image builder now prefixes four `nop` instructions so the first useful `_start` instruction lands where the current reset path actually begins decoding
   - the always-on thread-0 next-thread override was narrowed to the startup pulse only
   - focused staged-bundle and image-builder specs are green with this shape
6. The current staged-Verilog blocker is no longer control-transfer into DRAM:
   - direct probes now show the core executing real DRAM program instructions, including the benchmark `sethi` prologue
   - the remaining red is early architectural state after reset: address-building still collapses into a store at address `0`, so mailbox completion never occurs
   - focused code review and explorer traces point at remaining thread / AGP / current-thread canonicalization around `sparc_ifu_fcl`, `sparc_ifu_swl`, and `tlu_tcl`, not at the memory ABI or runtime export path
6a. Current unblocker work-in-progress:
   - hard thread-selection and AGP forcing in fast-boot patches `0011` (`sparc_ifu_fcl`), `0012` (`tlu_tcl`), and `0013` (`sparc.v`) has been relaxed to remove forced `thread0` defaults
7. The current IR-side blocker is no longer just cold compile latency:
   - compiler-backed `S1Top` currently fails before simulation starts because the imported design still contains real over-`128`-bit state, starting with `145`-bit CPX literals in `os2wb` and reaching widths of `1440` bits in LSU paths
   - `IrRunner` now raises that blocker explicitly instead of surfacing a later compact-JSON parse failure
8. Cold compile latency remains a secondary IR-side issue for imported `S1Top`:
   - compiler codegen was reduced from roughly `70 MB / 1.13M` lines to roughly `48 MB / 840k` lines by removing dead generic tick-helper emission and chunked evaluate duplication for large plain cores
   - a cold `rustc` compile for that generated unit still runs for multiple minutes, so the compiler-backed integration path is not yet practical for the slow suite without further work

## Goals

1. Add a new native `:sparc64` runner extension for imported `s1_top`.
2. Add SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner` support under `examples/sparc64/utilities/runners`.
3. Add a real SPARC64 integration benchmark loader that builds separate flash boot and DRAM program images.
4. Add a new integration suite under `spec/examples/sparc64/integration`.
5. Compare staged Verilog and imported RHDL on exact acknowledged Wishbone transaction traces and final program outcomes.
6. Keep all development and verification sequential rather than parallel to avoid overwhelming the local machine.

## Non-Goals

1. Board-level `W1` parity.
2. Full DDR3, flash, UART, or ethernet peripheral emulation.
3. OS boot or firmware boot validation.
4. CLI/task surface expansion for SPARC64 in this phase.
5. Weak parity that ignores timing or transaction ordering.

## Public Interface / API Additions

1. New native runner kind:
   - `:sparc64`
2. New SPARC64 runner stack:
   - `examples/sparc64/utilities/runners/headless_runner.rb`
   - `examples/sparc64/utilities/runners/ir_runner.rb`
   - `examples/sparc64/utilities/runners/verilator_runner.rb`
3. New SPARC64 integration support:
   - benchmark/image builder utilities
   - shared mailbox/result contract
   - shared acknowledged Wishbone event trace type
4. New integration spec tree:
   - `spec/examples/sparc64/integration`

## Runtime Contract

1. Top under test is `s1_top`.
2. IR backend for parity is compiler-only.
3. Verilator backend uses the staged importer-emitted `s1_top` closure, not the raw reference tree directly.
4. The runner memory model exposes:
   - sparse byte-addressable DRAM
   - sparse read-only flash
   - exact byte-lane reads/writes using Wishbone `sel`
   - deterministic one-cycle registered ACK timing
   - unmapped-access detection as a hard failure
5. Benchmarks use:
   - flash boot image at the reset-fetch region
   - DRAM benchmark image at a fixed program base
   - mailbox success/failure reporting in DRAM
6. Core policy:
   - park core 1
   - run the benchmark on core 0 only
7. Standard mailbox ABI:
   - `MAILBOX_STATUS = 0x0000_1000`
   - `MAILBOX_VALUE = 0x0000_1008`
   - success writes `1` to status
   - failure writes `0xFFFF_FFFF_FFFF_FFFF` to status

## Phased Plan (Red/Green)

### Phase 1: Native `:sparc64` Runner Extension

#### Red

1. Add failing native runner-extension specs for imported `s1_top`.
2. Capture the baseline failure that `runner_kind` is not `:sparc64` and that runner memory APIs are unavailable.
3. Add failing support checks for:
   - flash load
   - DRAM load
   - DRAM read/write
   - unmapped access reporting
   - one-cycle acknowledged Wishbone service

#### Green

1. Add `:sparc64` runner-kind detection to the interpreter, JIT, and compiler native backends.
2. Implement a SPARC64 native extension that drives `s1_top` through the existing normalized runner ABI.
3. Back the runner with:
   - sparse flash bytes
   - sparse DRAM bytes
   - Wishbone byte-lane masking
   - deterministic one-cycle ACK behavior
4. Surface unmapped accesses and runner-state failures through the normalized runner result/probe path.

#### Exit Criteria

1. Imported `s1_top` reports `runner_kind == :sparc64`.
2. Flash and DRAM can be loaded and observed through the runner ABI.
3. A simple memory transaction on `s1_top` completes through the native runner path with deterministic ACK timing.

### Phase 2: SPARC64 Runner Stack And Program/Image Builder

#### Red

1. Add failing runner specs for new SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner`.
2. Add failing builder specs for separate flash boot and DRAM benchmark images.
3. Add failing checks for the shared mailbox ABI and benchmark registry.

#### Green

1. Add `HeadlessRunner` with a shared operational contract:
   - load benchmark
   - reset
   - run until completion or timeout
   - read/write memory
   - expose acknowledged Wishbone trace
   - expose mailbox status/value
2. Add `IrRunner` around imported `S1Top` on the compiler backend.
3. Add `VerilatorRunner` around the staged `s1_top` closure with the same operational contract.
4. Add a SPARC64 benchmark/image builder that:
   - assembles SPARC V9 source with `llvm-mc`
   - links boot and DRAM images separately with `ld.lld --image-base=0`
   - extracts binary payloads with `llvm-objcopy`
5. Add shared benchmark definitions for:
   - `prime_sieve`
   - `mandelbrot`
   - `game_of_life`

#### Exit Criteria

1. Both IR and Verilator SPARC64 runners expose the same benchmark-loading and execution contract.
2. The benchmark builder emits separate flash and DRAM images.
3. The benchmark registry is stable and loadable from specs.

### Phase 3: Boot Handoff And Memory-Resident Benchmark Execution

#### Red

1. Add a failing startup smoke spec that proves the flash boot shim transfers control into DRAM.
2. Add a failing multicore policy spec that requires core 1 to remain parked while core 0 runs the benchmark.
3. Add failing mailbox completion specs for one minimal smoke program.

#### Green

1. Implement a shared flash-resident SPARC64 boot shim.
2. Make the shim hand off to the DRAM-resident benchmark entrypoint.
3. Enforce the parked-secondary-core policy before benchmark execution proceeds.
4. Add one minimal benchmark smoke path that reaches mailbox success through real DRAM execution.

#### Exit Criteria

1. `s1_top` can boot from flash, jump into DRAM, and complete a minimal program.
2. Core 1 remains parked according to the suite policy.
3. Mailbox completion works end to end through both backends.

### Phase 4: Integration Parity And Correctness Benchmarks

#### Red

1. Add failing integration parity specs for:
   - `prime_sieve`
   - `mandelbrot`
   - `game_of_life`
2. Add failing correctness specs that require:
   - expected mailbox result
   - no unmapped accesses
   - minimum transaction count
   - exact acknowledged Wishbone event equality between Verilator and compiler

#### Green

1. Implement a shared acknowledged Wishbone event trace:
   - `cycle`
   - `op`
   - `addr`
   - `sel`
   - `write_data`
   - `read_data`
2. Run each benchmark on staged Verilog and imported RHDL with identical images and timeout/cycle budgets.
3. Require exact ordered event-trace equality, including cycle numbers.
4. Require benchmark-specific mailbox values:
   - `prime_sieve => 0xA0`
   - `mandelbrot => 0xFFF0`
   - `game_of_life => 0x2`

#### Exit Criteria

1. All three benchmarks pass exact Verilator-vs-compiler parity.
2. All three benchmarks pass mailbox correctness checks.
3. No benchmark performs an unmapped access.

### Phase 5: Sequential Regression Closure

#### Red

1. Add failing regression/task-level checks that capture the intended SPARC64 integration scope in the normal suite.

#### Green

1. Run the focused sequential integration suite.
2. Run the broader sequential SPARC64 suite.
3. Update the PRD and checklists to reflect the actual shipped state.

#### Exit Criteria

1. `spec/examples/sparc64/integration` is green sequentially.
2. `bundle exec rake spec:sparc64` is green sequentially.
3. PRD status and checklist match reality.

## Acceptance Criteria

1. A new native `:sparc64` runner extension exists and is covered.
2. SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner` exist and share one runtime contract.
3. The benchmark builder emits separate flash boot and DRAM program images.
4. The new `spec/examples/sparc64/integration` suite runs `prime_sieve`, `mandelbrot`, and `game_of_life`.
5. Each benchmark is DRAM-resident and completes through the mailbox ABI.
6. Staged Verilog and imported RHDL match on exact acknowledged Wishbone transaction traces for all three programs.
7. Sequential SPARC64 regression gates are green.

## Risks And Mitigations

1. Risk: `s1_top` startup behavior is more complex than the current parked-core assumption.
   - Mitigation: lock startup behavior first with Phase 3 smoke specs before building all three benchmarks.
2. Risk: SPARC toolchain/image layout becomes brittle.
   - Mitigation: keep the builder minimal, deterministic, and covered with focused specs for separate boot/DRAM images.
3. Risk: Verilator and compiler diverge because of memory-service timing rather than core behavior.
   - Mitigation: share one explicit one-cycle ACK memory model and require exact event-trace parity.
4. Risk: Runtime execution is too slow for the full benchmark set.
   - Mitigation: keep benchmark workloads compact, cache builds where appropriate, and develop only with sequential focused commands.

## Testing Gates

1. `bundle exec rspec spec/examples/sparc64/integration --order defined`
2. `bundle exec rspec spec/examples/sparc64/import/unit/parity_helper_spec.rb --order defined`
3. `bundle exec rake spec:sparc64`

## Implementation Checklist

- [x] PRD created
- [x] Phase 1 red: native SPARC64 runner-extension specs added
- [x] Phase 1 green: native `:sparc64` runner extension implemented
- [x] Phase 1 exit criteria validated
- [x] Phase 2 red: SPARC64 runner and builder specs added
- [x] Phase 2 green: `HeadlessRunner`, `IrRunner`, `VerilatorRunner`, and benchmark builder implemented
- [x] Phase 2 exit criteria validated
- [x] Phase 3 red: boot handoff, parked-core, and mailbox smoke specs added
- [ ] Phase 3 green: boot shim and minimal DRAM benchmark flow implemented
- [ ] Phase 3 exit criteria validated
- [x] Phase 4 red: benchmark parity/correctness specs added
- [ ] Phase 4 green: `prime_sieve`, `mandelbrot`, and `game_of_life` parity is green
- [ ] Phase 4 exit criteria validated
- [ ] Phase 5 red: regression/task-level checks added
- [ ] Phase 5 green: sequential SPARC64 regression closure complete
- [ ] Acceptance criteria validated
