# AO486 Binary + BIOS + DOS Image Boot PRD

## Status
In Progress (updated 2026-03-03, phase 6d now in progress; phase 7 blocked on 6d)

## Context
AO486 currently has importer and backend-parity infrastructure, but no first-class executable runner binary in `examples/ao486/bin` matching the RISC-V UX surface. The next delivery is a runnable AO486 binary with:

1. Interactive display adapter and debug output.
2. Program loading for non-BIOS binaries.
3. BIOS-enabled mode for BIOS-required boot flows.
4. Standard backend controls (`--mode`, `--sim`).
5. A new DOS image phase: place a DOS 4-compatible boot image directly in `examples/ao486/software/images` and boot it successfully after BIOS support is working.

## Goals
1. Add `examples/ao486/bin/ao486` with CLI behavior aligned to `examples/riscv/bin/riscv`.
2. Add AO486 run-task/runtime wiring under `examples/ao486/utilities/tasks`.
3. Support interactive operation with display and debug across `ir`, `verilator`, and `arcilator` backends.
4. Support non-BIOS program execution and BIOS-enabled execution paths.
5. Add deterministic DOS image acquisition and BIOS boot validation.

## Non-Goals
1. Full motherboard chipset emulation for all legacy peripherals in this tranche.
2. Replacing importer parity profiles (`ao486_trace`, `ao486_program_parity`, etc.).
3. Manual edits to generated AO486 component files.
4. Adding custom component-level `to_verilog` overrides.

## Constraints and Decisions
1. `rhdl examples ao486` must dispatch to the new AO486 binary.
2. Display default is VGA text decode from memory (with I/O text fallback).
3. BIOS defaults use bundled ROM assets under `examples/ao486/reference/releases` unless explicitly overridden.
4. Runtime specs outside `import` must not re-import vendor Verilog on each run.
5. DOS-image phase uses a checked-in local artifact under `examples/ao486/software/images` (no runtime fetch script).
6. Initial DOS boot enablement may use an `INT 13h` RAM-disk shim before full storage-controller emulation.

## Public Interface Changes
1. New binary: `examples/ao486/bin/ao486`.
2. New AO486 run task: `examples/ao486/utilities/tasks/run_task.rb`.
3. New CLI options (AO486 binary):
   - `--mode ir|verilator|arcilator`
   - `--sim interpret|jit|compile` (IR mode)
   - `--debug`
   - `--headless`
   - `--cycles`
   - `--speed`
   - `--io vga|uart`
   - `--address`
   - `--bios`
   - `--bios-system FILE`
   - `--bios-video FILE`
   - `--boot-addr`
   - `--disk FILE`
   - `--dos` (BIOS + default ROM/disk shortcut)
4. `exe/rhdl` examples help/dispatch adds `ao486`.

## Phased Plan (Red/Green/Refactor)

### Phase 0: Baseline + PRD Lock
Red:
1. Add failing specs for AO486 binary CLI entrypoint, options, and missing runtime task.
2. Capture baseline AO486 runtime/import gates relevant to this tranche.

Green:
1. New PRD committed and linked from active AO486 workstream.
2. Baseline command outputs and failure modes captured in PRD notes.

Refactor:
1. None.

Exit Criteria:
1. PRD is decision-complete and actionable.
2. Baseline failures are reproducible.

### Phase 1: AO486 Runtime Contract for Interactive/Batched Execution
Red:
1. Add failing runner-contract specs requiring `reset!`, `run_cycles`, memory read/write, event draining, and `state`.
2. Add failing headless delegation specs for backend selection and shared API.

Green:
1. Implement runtime contract in:
   - `examples/ao486/utilities/runners/headless_runner.rb`
   - `examples/ao486/utilities/runners/ir_runner.rb`
   - `examples/ao486/utilities/runners/verilator_runner.rb`
   - `examples/ao486/utilities/runners/arcilator_runner.rb`
2. Ensure all three backends support persistent batched cycle stepping.

Refactor:
1. Normalize AO486 event schema adapters without introducing a common base runner.

Exit Criteria:
1. Runner contract specs are green for all AO486 backends.
2. No fallback to one-shot-only execution paths in this CLI flow.

### Phase 2: AO486 Run Task + Display + Debug
Red:
1. Add failing run-task specs for:
   - VGA text-frame decoding from memory.
   - I/O text fallback rendering.
   - debug panel content and formatting.

Green:
1. Add `examples/ao486/utilities/tasks/run_task.rb` with:
   - interactive loop
   - headless mode
   - batched cycle scheduling
   - keyboard controls
2. Add AO486 debug output including PC/instruction/cycles/backend/mode/speed.

Refactor:
1. Separate render logic from cycle-control logic for testability.

Exit Criteria:
1. Render/debug specs pass in headless and interactive contexts.
2. Task operates with each backend through the same user-facing commands.

### Phase 3: AO486 Binary + Top-Level CLI Integration
Red:
1. Add failing specs for new binary option parsing and error handling.
2. Add failing `exe/rhdl` examples dispatch/help tests for `ao486`.

Green:
1. Create `examples/ao486/bin/ao486`.
2. Wire `rhdl examples ao486` in `exe/rhdl`.
3. Implement mode/backend defaults and validation consistent with existing examples.

Refactor:
1. Deduplicate option-default helpers where safe.

Exit Criteria:
1. AO486 binary runs and prints correct help/validation errors.
2. `rhdl examples ao486` dispatch works end-to-end.

### Phase 4: Non-BIOS and BIOS Program Loading
Red:
1. Add failing loader specs for:
   - non-BIOS binary loading path
   - BIOS ROM placement
   - boot-address control and reset behavior

Green:
1. Implement non-BIOS loading (direct program load path).
2. Implement BIOS loading path:
   - system BIOS ROM map
   - video BIOS ROM map
   - optional override flags
3. Verify deterministic boot milestones in targeted runtime specs.

Refactor:
1. Centralize AO486 memory map constants.

Exit Criteria:
1. Loader specs pass for both paths.
2. BIOS flow reaches expected execution milestones across backends.

### Phase 5: DOS 4-Compatible Image Placement
Red:
1. Add failing specs for missing local DOS image artifact in `examples/ao486/software/images`.

Green:
1. Download DOS image artifact from a pinned upstream source.
2. Store it in `examples/ao486/software/images` as:
   - `fdboot.img`
   - `dos4.img` (compatibility alias used by tests/options).

Refactor:
1. None.

Exit Criteria:
1. DOS image artifact exists locally in `examples/ao486/software/images`.
2. Runtime specs can resolve DOS image path without external fetch logic.

### Phase 6: Compiler-First Execution Unblock (Importer Semantics)
Red:
1. Add/refresh a failing compiler-only runtime check proving AO486 fetches but does not retire:
   - reset-vector fetch loop repeats (`0x000ffff0..0x000ffffc`)
   - no instruction retirement progress
   - no architectural side effects (memory writes / IO writes)
2. Capture failing evidence for cache-path modules in converted RHDL (unpacked-array/index lowering defects).

Green:
1. Fix importer lowering for unpacked-array declarations/indexing used in AO486 cache path (compiler target first).
2. Re-import AO486 runtime artifacts with real converted cache behavior (no manual component edits).
3. Verify compiler backend leaves reset-vector loop and executes beyond boot fetch-only state.

Refactor:
1. Keep interpreter/JIT follow-up explicitly out of scope until compiler path is green.

Exit Criteria:
1. Compiler backend demonstrates real execution progress (not just repeated reset-vector fetches).
2. Compiler DOS/runtime path no longer trips the "core-only top does not progress" guard due fetch-only stalls.

### Phase 6b: Compiler Startup Throughput (IR Build/Load)
Red:
1. Add a reproducible timing check showing AO486 IR runner startup exceeds practical CLI latency budgets.
2. Capture the slow stage breakdown (flatten/lower/json/simulator init) under controlled timing output.

Green:
1. Add AO486 IR JSON cache support keyed to converted HDL/import artifacts so repeated runs skip expensive rebuild.
2. Add opt-in timing diagnostics for AO486 IR runner startup to localize regressions quickly.
3. Reduce DOS live-session warmup cost while preserving real-progress guardrails.

Refactor:
1. Keep cache invalidation deterministic and local to `examples/ao486/hdl/tmp`.

Exit Criteria:
1. Second-run startup uses cache path and avoids full IR regeneration.
2. AO486 interactive/headless runner startup no longer requires repeated full IR conversion per invocation.

### Phase 6c: Importer/Runtime Semantic Alignment (Clocked Process + Platform Inputs)
Red:
1. Add a failing lowering regression where mixed-edge clocked process sensitivity picks reset edge (`posedge aclr`) instead of real clock edge (`posedge inclock`).
2. Capture AO486 runtime mismatch where compiler extension platform defaults diverge from Verilator harness defaults (`cache_disable` mismatch).

Green:
1. Fix `IR::Lower` clock-selection logic for clocked imported processes with mixed sensitivity edges:
   - prefer non-reset signals
   - prefer clock-like names (`clk`/`clock`)
   - retain fallback to first sensitivity when no better candidate exists
2. Add lowering regression spec for mixed reset+clock sensitivity.
3. Align AO486 compiler extension platform input defaults with reference harness (`cache_disable=1`) and rebuild native extensions.

Refactor:
1. Keep selection heuristics local to lowering and avoid changing public DSL behavior.

Exit Criteria:
1. New lowering regression spec is green.
2. AO486 compiler extension uses the same cache-disable default as Verilator reference harness.
3. AO486 IR trace parity against vendor reference remains green after native rebuild.

### Phase 6d: Vendor Verilator Functional Program Gate (Pre-DOS)
Red:
1. Add a failing integration spec that runs vendor Verilator (`source_mode: :vendor`) against the three complex programs:
   - `04_cellular_automaton.bin`
   - `05_mandelbrot_fixedpoint.bin`
   - `06_prime_sieve.bin`
2. Assert exact output words in tracked memory:
   - automaton: `0x0240=0xF5E2`, `0x0242=0x0010`
   - mandelbrot: `0x0250=0x8EEE`, `0x0252=0x0003`
   - prime sieve: `0x0260=0x06B8`, `0x0262=0x001F`
3. Assert non-stall execution signals:
   - PC sequence must leave reset-vector fetch window (`0x000fffe0..0x000ffffc`)
   - at least one memory write is observed

Green:
1. Fix vendor Verilator runner/testbench runtime behavior until all three programs produce expected outputs.
2. Keep runtime specs outside `import` non-reimporting and backend-batched.
3. Use phase 6d as hard prerequisite for DOS work (phase 7).

Refactor:
1. Consolidate output oracle helpers for reuse in later DOS preflight checks.

Exit Criteria:
1. Vendor Verilator passes exact-output checks for all three complex programs.
2. Vendor Verilator shows real execution progress (not reset-loop fetch-only behavior).
3. Phase 7 DOS boot work starts only after phase 6d is green.

#### Phase 6d Diagnostic Notes (2026-03-03)
1. Functional gate remains red: vendor Verilator repeatedly fetches reset-window words and never produces memory writes/output words.
2. Instrumented runner traces show `decode.eip` pinned at `0x0000fff0`, `dec_ready=0`, and prefetch FIFO staying empty while L1 icache remains in `FILLCACHE`.
3. Runner testbench had a burst-response skew path (`read_addr - 4` plus synthetic extra beat) that can misalign returned words; this was removed as incorrect.
4. After removing skew, behavior still does not reach green: requests collapse to the reset window with no architectural side effects, indicating remaining handshake/model issues in the memory/cache path.
5. Green-path follow-up: finish correcting `avm_read`/`avm_readdatavalid` timing to satisfy `avalon_mem`/`l1_icache` expectations, then verify cache-tag/data primitive model behavior under fill+read-hit transitions.

### Phase 7: BIOS Boot of DOS Image
Red:
1. Add failing integration specs that load BIOS + DOS image and assert boot progress to DOS prompt marker.
2. Add failing cross-backend parity checks for boot-sequence milestones.
3. Add failing execution-progress check proving the minimal ao486-only runtime harness still loops at reset-vector fetches for DOS shim in both vendor and generated paths.

Green:
1. Preserve deterministic DOS boot shim path after BIOS asset validation.
2. Implement platform-level runtime bridge changes needed for real instruction progression (not fetch-only loop) in the ao486 runners:
   - align bus/handshake behavior with reference ao486 simulation flow
   - keep native-memory attachment and batched cycle execution
3. Validate prompt-level success signal in vendor-reference and generated backend runs.

Refactor:
1. Normalize boot milestone extraction/reporting helpers.

Exit Criteria:
1. DOS shim leaves reset-vector fetch-only loop and executes program-side effects (PC progression beyond `0x000ffff0..0x000ffffc`, memory/IO side effects observable).
2. DOS shim reaches DOS prompt marker after BIOS/DOS asset loading checks.
3. Prompt milestone assertions pass in AO486 runtime integration suite.

### Phase 8: Regression Gates and Cleanup
Red:
1. Run AO486-targeted runtime/import gates and capture failures.

Green:
1. Fix regressions in touched areas.
2. Ensure runtime specs outside `import` do not trigger re-import.
3. Keep temporary outputs in `examples/ao486/tmp`.

Refactor:
1. Remove dead paths introduced during bring-up.

Exit Criteria:
1. Touched AO486 suites are green.
2. No stray scratch artifacts outside designated tmp directories.

## Acceptance Criteria
1. `examples/ao486/bin/ao486` exists and is usable for interactive and headless runs.
2. AO486 binary supports `--mode`, `--sim`, `--bios`, and related runtime controls.
3. Display adapter and debug output work across IR, Verilator, and Arcilator flows.
4. `rhdl examples ao486` is fully wired and documented in help text.
5. DOS image is present in `examples/ao486/software/images` (`fdboot.img` + `dos4.img` alias).
6. DOS boot shim reaches DOS prompt marker across vendor/generated backends, with passing integration assertions.
7. `bin/ao486 --dos` runs a real interactive shell session (no synthetic output path).

## Risks and Mitigations
1. Risk: BIOS + DOS boot requires more device behavior than initially scoped.
   Mitigation: stage with deterministic `INT 13h` RAM-disk shim and defer full controller emulation.
2. Risk: Cross-backend boot timing divergence causes flaky prompt checks.
   Mitigation: compare milestone sequences and bounded windows, not wall-clock timing.
3. Risk: DOS image source URL changes over time.
   Mitigation: keep the downloaded image artifact in-repo under `examples/ao486/software/images`.
4. Risk: Runtime suite performance regressions.
   Mitigation: enforce batched `run_cycles` usage in all backends and cap cycle budgets per phase.

## Implementation Checklist
- [x] Phase 0: Baseline + PRD lock
- [x] Phase 1: AO486 runtime contract
- [x] Phase 2: AO486 run task + display + debug
- [x] Phase 3: AO486 binary + top-level CLI integration
- [x] Phase 4: Non-BIOS and BIOS program loading
- [x] Phase 5: DOS 4-compatible image placement
- [x] Phase 6: Compiler-first importer execution unblock
- [x] Phase 6b: Compiler startup throughput (IR build/load)
- [x] Phase 6c: Importer/runtime semantic alignment (clock selection + cache_disable parity)
- [ ] Phase 6d: Vendor Verilator functional program gate (pre-DOS)
- [ ] Phase 7: BIOS boot of DOS image
- [ ] Phase 8: Regression gates and cleanup
- [ ] Phase 9: Full-system runtime path for real DOS shell (non-synthetic)

## Current Remaining Work
1. Complete phase 6d by getting vendor Verilator to run the complex programs functionally (exact output checks + non-stall execution).
2. Replace current fetch-only minimal-harness behavior with platform-level runtime behavior that allows real instruction progression from reset vector in DOS shim path (phase 7 red->green).
3. Implement real BIOS+DOS boot execution path to prompt milestone across backends (phase 7), replacing current non-implemented backend stubs.
4. Complete regression cleanup/gates for the updated importer and runner behavior (phase 8).
5. Deliver full real-shell `--dos` path (phase 9), including platform-level shims/peripherals needed by DOS runtime.

## Agent Tranches (Kickoff 2026-03-03)
1. Tranche A: Runtime Contract
   - Scope:
     - `examples/ao486/utilities/runners/headless_runner.rb`
     - `examples/ao486/utilities/runners/ir_runner.rb`
     - `examples/ao486/utilities/runners/verilator_runner.rb`
     - `examples/ao486/utilities/runners/arcilator_runner.rb`
     - `spec/examples/ao486/runners/*`
   - Target phases: Phase 1
   - Status: Complete
2. Tranche B: Run Task + Binary + CLI Wiring
   - Scope:
     - `examples/ao486/utilities/tasks/run_task.rb`
     - `examples/ao486/bin/ao486`
     - `exe/rhdl` (`examples ao486` dispatch/help)
     - `spec/examples/ao486/utilities/*`
   - Target phases: Phase 2, Phase 3
   - Status: Complete
3. Tranche C: BIOS/Loader Bring-up
   - Scope:
     - AO486 runner/task loader integration for BIOS and non-BIOS paths
     - loader-focused runtime specs under `spec/examples/ao486/integration`
   - Target phases: Phase 4
   - Status: Complete
4. Tranche D: DOS Image Placement + Boot Validation
   - Scope:
     - `examples/ao486/software/images/*` image artifacts + DOS boot integration
     - DOS boot integration specs under `spec/examples/ao486/integration`
   - Target phases: Phase 5, Phase 6
   - Status: Complete
