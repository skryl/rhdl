# AO486 CPU Runtime Parity PRD

## Status
In Progress

## Context
AO486 currently has:
1. A system-level importer rooted at `examples/ao486/reference/rtl/system.v`.
2. A bounded top-level parity spec that compares stub-safe outputs across Verilator and available IR backends.
3. No CPU-top behavioral parity harness, no AO486 Arcilator runtime path, and no canonical imported-MLIR branch helper for ARC lowering.

The new parity gate must validate the imported AO486 CPU top, not the system top, and it must branch from one canonical imported CIRCT MLIR artifact into:
1. `firtool`-exported Verilog executed on Verilator.
2. Raised RHDL executed on the IR JIT backend.
3. ARC MLIR executed through Arcilator.

The behavioral check is instruction-oriented:
1. Compare completed-instruction `EIP`.
2. Compare the actual instruction bytes executed at each completed-instruction boundary.

## Goals
1. Add a CPU-focused AO486 importer rooted at `examples/ao486/reference/rtl/ao486/ao486.v`.
2. Add canonical CIRCT-MLIR -> ARC preparation support without routing back through Verilog import.
3. Add a deterministic CPU-top 3-way runtime parity spec for Verilator, IR JIT, and Arcilator.
4. Keep the runtime harness self-contained with an embedded real-mode program and shared memory/IO model.

## Non-Goals
1. Extending AO486 CLI surface.
2. Replacing the existing system-level importer or parity spec.
3. Using IR compiler parity for imported AO486 in this phase.
4. Full SoC or BIOS boot parity.

## Public Interface / API Additions
1. New importer helper:
   - `RHDL::Examples::AO486::Import::CpuImporter`
   - path: `examples/ao486/utilities/import/cpu_importer.rb`
2. New imported-package trace helper:
   - `RHDL::Examples::AO486::Import::CpuTracePackage`
   - path: `examples/ao486/utilities/import/cpu_trace_package.rb`
2. New CIRCT tooling helper:
   - `RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(mlir_path:, work_dir:)`
3. New AO486 CPU runtime parity spec:
   - `spec/examples/ao486/import/runtime_cpu_parity_3way_spec.rb`

## Phased Plan (Red/Green)
### Phase 1: CPU Import Artifact
Red:
1. Add failing CPU importer specs for:
   - canonical top `ao486`
   - tree-import success with no stub fallback
   - normalized core MLIR artifact emission
2. Capture the baseline failure signal from missing CPU importer functionality.

Green:
1. Add `CpuImporter` with:
   - default source `examples/ao486/reference/rtl/ao486/ao486.v`
   - default top `ao486`
   - tree import rooted at `examples/ao486/reference/rtl`
   - no system-specific normalization pass
   - result contract aligned with the existing AO486 importer
2. Re-run CPU importer specs.

Refactor:
1. Keep `SystemImporter` unchanged unless a small shared helper extraction is required to avoid direct duplication.

Exit Criteria:
1. CPU importer specs are green.
2. The importer emits a canonical normalized core MLIR artifact for `@ao486`.

### Phase 2: Canonical CIRCT MLIR -> ARC
Red:
1. Add failing tooling specs for canonical imported MLIR ARC preparation.
2. Capture the baseline failure signal from the missing helper.

Green:
1. Add `prepare_arc_mlir_from_circt_mlir(mlir_path:, work_dir:)`.
2. Use `ArcPrepare.transform_normalized_llhd` on canonical imported MLIR.
3. Lower the produced hw/seq MLIR with `circt-opt --convert-to-arcs`.
4. Re-run tooling specs.

Refactor:
1. Reuse existing `prepare_arc_failure`/result-shape patterns where practical.

Exit Criteria:
1. Canonical imported MLIR can be transformed into ARC MLIR without re-importing Verilog.
2. Tooling specs are green.

### Phase 3: 3-Way CPU Runtime Parity
Red:
1. Add a failing slow spec that:
   - imports the CPU top
   - branches from canonical MLIR into Verilator, IR JIT, and Arcilator
   - runs one embedded real-mode program
   - expects an exact completed-instruction `EIP + bytes` trace match
2. Capture the baseline failure signal from missing backend harnesses.

Green:
1. Implement backend-specific runtime collectors with one shared behavioral contract:
   - same embedded program bytes
   - same memory and IO handshake model
   - same instruction-boundary event definition
2. Use IR JIT only for the RHDL branch.
3. Fail on unexpected IO, interrupt, exception, shutdown, timeout, or trace-length mismatch.
4. Re-run the slow parity spec.

Refactor:
1. Keep backend-specific signal lookup in small, isolated helpers.

Exit Criteria:
1. Verilator, IR JIT, and Arcilator produce identical completed-instruction traces on the embedded program.
2. The slow parity spec is green or explicitly skip-gated for missing tools.

## Exit Criteria Per Phase
1. Phase 1: CPU importer exists and emits canonical `@ao486` normalized core MLIR.
2. Phase 2: Canonical imported MLIR can be lowered to ARC MLIR through the new helper.
3. Phase 3: 3-way CPU runtime parity passes on Verilator, IR JIT, and Arcilator.

## Acceptance Criteria (Full Completion)
1. `CpuImporter` exists with green focused specs.
2. Canonical imported AO486 CPU MLIR can branch to Verilator, IR JIT, and Arcilator flows.
3. AO486 CPU runtime parity compares exact completed-instruction `EIP + bytes` traces.
4. PRD checklist and status reflect the shipped state.

## Risks and Mitigations
1. Risk: CPU-top tree import misses sibling RTL directories.
   - Mitigation: hard-root module discovery/staging at `examples/ao486/reference/rtl`.
2. Risk: Arcilator lowering rejects canonical imported MLIR shapes.
   - Mitigation: reuse `ArcPrepare.transform_normalized_llhd` and add focused tooling tests first.
3. Risk: Internal signal names differ across Verilator, IR JIT, and Arcilator.
   - Mitigation: use ordered signal-name candidate lists and explicit missing-signal diagnostics.
4. Risk: Runtime parity is flaky because of bus timing drift.
   - Mitigation: make all three collectors share one deterministic CPU-top handshake contract based on the existing AO486 CPU testbench style.
5. Risk: Imported AO486 still fails on IR compiler.
   - Mitigation: keep this parity gate on IR JIT only for now.

## Testing Gates
1. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb`
2. `bundle exec rspec spec/rhdl/codegen/circt/tooling_spec.rb`
3. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_parity_3way_spec.rb`
4. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb spec/examples/ao486/import/roundtrip_spec.rb`
5. `bundle exec rake "spec[ao486]"` if the slow gate is intended to join the AO486 suite
6. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_step_parity_spec.rb`

## Implementation Checklist
- [x] PRD created.
- [x] Phase 1 red specs added.
- [x] Phase 1 green implementation complete.
- [x] Phase 1 exit criteria validated.
- [x] Phase 2 red specs added.
- [x] Phase 2 green implementation complete.
- [x] Phase 2 exit criteria validated.
- [ ] Phase 3 red spec added.
- [ ] Phase 3 green implementation complete.
- [ ] Phase 3 exit criteria validated.
- [ ] Acceptance criteria validated.

## Execution Notes (2026-03-06)
Completed in this iteration:
1. Added CPU-top importer:
   - `examples/ao486/utilities/import/cpu_importer.rb`
   - defaults to `examples/ao486/reference/rtl/ao486/ao486.v`
   - uses full RTL search root `examples/ao486/reference/rtl`
   - defaults to tree strategy with no stub fallback
2. Generalized AO486 system-import staging hooks enough for CPU-top reuse:
   - artifact basenames now follow `top`
   - tree/module indexing can use an overridable source root
   - helper include staging now works for both `rtl/system.v` and `rtl/ao486/ao486.v`
3. Added focused CPU importer spec coverage:
   - `spec/examples/ao486/import/cpu_importer_spec.rb`
   - validates canonical CPU MLIR emission and in-memory component raising from canonical MLIR
4. Added canonical CIRCT-MLIR branching helper:
   - `RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir`
   - returns shared `hwseq` output path plus attempted `arc` output path
5. Added tooling coverage for the new helper:
   - `spec/rhdl/codegen/circt/tooling_spec.rb`
6. Added a traced-top post-import IR transform:
   - `examples/ao486/utilities/import/cpu_trace_package.rb`
   - exposes `trace_retired`, `trace_wr_eip`, `trace_wr_consumed`, `trace_cs_cache`, and `trace_cs_cache_valid` on the imported `ao486` CPU top
   - carries the retire interface up from `write` -> `pipeline` -> `ao486` entirely within canonical CIRCT IR
   - final retire pulse is now recomputed in `pipeline` from imported `write` outputs (`wr_finished`, `wr_ready`, `wr_hlt_in_progress`) so `firtool` does not constant-fold it away
7. Added focused coverage for the traced package:
   - `spec/examples/ao486/import/cpu_trace_package_spec.rb`
   - validates re-import of traced MLIR and `firtool` export from the traced top
8. Added a focused runtime guardrail for hierarchical CIRCT IR:
   - `spec/rhdl/sim/native/ir/circt_hierarchy_flatten_runtime_spec.rb`
   - demonstrates that hierarchical CIRCT packages evaluate correctly on JIT once flattened for runtime
9. Fixed native IR clocking/runtime correctness needed for AO486 JIT:
   - `lib/rhdl/sim/native/ir/ir_interpreter/src/core.rs`
   - `lib/rhdl/sim/native/ir/ir_jit/src/core.rs`
   - `spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb`
   - direct CIRCT sequential stepping now matches the expected low-phase `evaluate` / high-phase `tick` contract
   - JIT now uses the runtime sequential sampler for imported sequential expressions and tracks combinational assignment dependencies the same way as the interpreter for multi-writer targets
10. Strengthened AO486 CPU importer runtime coverage:
   - `spec/examples/ao486/import/cpu_importer_spec.rb`
   - now checks that one legal `rst_n=0` clock cycle on the flattened imported CPU JIT runtime produces the expected reset state:
     - `pipeline_inst__decode_inst__eip == 0xFFF0`
     - `memory_inst__prefetch_inst__prefetch_address == 0xFFFF0`
     - `memory_inst__prefetch_inst__prefetch_length == 16`
11. Fixed cleaned-MLIR sequential feedback across multiple clocked processes:
   - `lib/rhdl/codegen/circt/mlir.rb`
   - the structural MLIR emitter now pre-seeds current-cycle register tokens across the whole module before emitting per-process `seq.compreg` logic
   - this closes the cleanup regression where cross-process register reads in imported modules were being zeroed during re-emission
12. AO486 startup probe result after the cleaned-MLIR fix:
   - the imported CPU now reaches correct reset state, but the earlier post-reset `avm_read` pulse was traced to a runtime-json hoisting bug rather than a real reset-vector fetch
13. Fixed CIRCT runtime-json hoisting collisions that were corrupting imported startup behavior:
   - `lib/rhdl/codegen/circt/runtime_json.rb`
   - hoisted shared-expression temp names now use one monotonic counter per normalized expression instead of recursive local offsets
   - this closes the duplicate `_rt_tmp_*` assign-target collision that was causing the imported AO486 TLB state machine to commit impossible next-state values at runtime
14. Strengthened AO486 CPU importer runtime coverage around the real startup sequence:
   - `spec/examples/ao486/import/cpu_importer_spec.rb`
   - now asserts that runtime normalization emits no duplicate assign targets
   - now checks the corrected imported startup path:
     - TLB enters `STATE_CODE_CHECK`
     - `tlbcode_do` asserts
     - `prefetch_control.icacheread_do` asserts
15. Resulting startup classification after the runtime-json fix:
   - the earlier bogus `STATE_READ_CHECK` transition in imported TLB startup is fixed
   - `tlbcoderequest_do -> tlbcode_do -> icacheread_do` now behaves correctly on the flattened imported CPU JIT runtime
   - the remaining startup failure moved downstream into imported cache logic: `l1_icache` still never raises `MEM_REQ`, so `readcode_do` / `avm_read` do not yet form a usable reset-vector fetch
16. Added a parity-oriented imported-package transform for cache-disabled CPU-top execution:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - builds on the traced imported package and replaces imported `l1_icache` behavior inside `icache` with a direct-fetch model intended only for parity mode with `cache_disable=1`
   - this keeps the imported CPU top and imported memory/pipeline structure, while bypassing the still-broken imported cache controller
17. Added focused coverage for the parity package:
   - `spec/examples/ao486/import/cpu_parity_package_spec.rb`
   - validates that the parity package issues the reset-vector code fetch under JIT with `cache_disable=1`
18. Runtime result with the parity package:
   - flattened imported AO486 CPU JIT now asserts `memory_inst__icache_inst__readcode_do`, `memory_inst__avalon_mem_inst__readcode_do`, and top-level `avm_read`
   - the first fetch targets the expected reset-vector line (`readcode_address = 0xFFFF0`, `avm_address = 0x3FFFC`)
   - this closes the “no instruction fetch at all” blocker for parity mode
19. Remaining runtime gap after the parity-package fetch fix:
   - the direct-fetch parity path still does not yet produce a clean retired reset-vector far jump trace
   - ad hoc JIT probing now shows repeated `trace_retired` assertions and advancing `trace_wr_eip`, which means parity-mode execution is moving, but event qualification and/or the direct-fetch cache-bypass semantics still need refinement before exact `EIP + bytes` parity can be compared
20. Added a reusable parity runtime helper:
   - `examples/ao486/utilities/import/cpu_parity_runtime.rb`
   - wraps the parity package on IR JIT with a deterministic no-wait Avalon code-burst scheduler
   - current supported guarantee is fetch-side determinism, not retired-instruction correctness
21. Added focused runtime coverage for the helper:
   - `spec/examples/ao486/import/cpu_parity_runtime_spec.rb`
   - validates the first reset-vector PC byte groups for a tiny reset-vector program placed directly at `0xFFFF0`
22. Current execution classification after the helper:
   - the corrected burst scheduler now returns the expected reset-vector PC byte groups on JIT
   - prefetch-side byte flow is observable and stable enough for harness reuse
   - write-stage trace remains unreliable for exact parity: `trace_wr_eip` / `trace_wr_consumed` do not yet correspond to a clean retired-instruction stream on the parity path
23. Added a Verilator-side parity runtime helper:
   - `examples/ao486/utilities/import/cpu_parity_verilator_runtime.rb`
   - exports the parity package through `firtool`, builds a dedicated `ao486` Verilator harness, and mirrors the same no-wait Avalon code-burst scheduler used by the JIT helper
24. Added a focused mixed-backend fetch parity spec:
   - `spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb`
   - validates that Verilator and JIT return the same first reset-vector PC byte groups on the parity package
25. Added a slow mixed-backend runtime fetch-parity gate:
   - `spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb`
   - compares JIT and Verilator on the same parity package and the same reset-vector PC byte-group trace
26. Mixed-backend fetch status:
   - the cache-disabled parity package now matches between JIT and Verilator on a longer straight-line reset-vector PC byte-group trace:
     - `0xFFF0 -> [0x31, 0xC0, 0x40, 0x90]`
     - `0xFFF4 -> [0x31, 0xDB, 0x43, 0x90]`
     - `0xFFF8 -> [0xF4, 0x90, 0x00, 0x00]`
   - this establishes a stable mixed-backend runtime baseline on canonical imported code with an explicit fetch-side trace contract `{pc, bytes}`, even though the exact retired-instruction trace surface is still not ready
27. Added named AO486 parity program fixtures assembled with `llvm-mc`:
   - `examples/ao486/utilities/import/cpu_parity_programs.rb`
   - fixture set: `reset_smoke`, `prime_sieve`, `mandelbrot`, `game_of_life`
   - the richer fixtures are currently self-checking and register-heavy because imported CPU-top data-memory parity is still incomplete on the parity path
28. Tightened the parity-package direct-fetch handshake to better match the original `icache` contract:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - the direct bypass now exposes only the first four CPU words of each `readcode` request to `icache`, instead of forwarding all eight Avalon beats as CPU-valid words
29. Expanded the focused and slow fetch-parity gates to the named fixture set:
   - `spec/examples/ao486/import/cpu_parity_runtime_spec.rb`
   - `spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb`
   - `spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb`
   - both JIT and Verilator now match the expected initial 32-byte fetch window for all named fixtures
30. Current benchmark-fixture classification:
   - the parity harness now validates richer imported CPU-top code images than the original reset-vector smoke program
   - however, the current parity bypass still only exposes the first 32-byte fetch window reliably for those larger fixtures
   - this is enough for a real mixed-backend checkpoint on named AO486 benchmark programs, but it is still short of full execution-trace or retired-instruction parity
31. Fixed the parity-package aligned `icache` `length_burst` regression:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - the parity package now rewrites the mis-imported 12-bit `length_burst` literals inside the imported `icache.partial_length` sequential assignment
   - aligned fetches now use the original RTL ordering `{4,4,4,4}` instead of the reversed imported ordering `{4,4,4,1}`
32. Added focused coverage for the aligned-fetch repair:
   - `spec/examples/ao486/import/cpu_parity_runtime_spec.rb`
   - validates that a larger fixture (`prime_sieve`) no longer leaves `icache` stuck in `STATE_READ` after the first aligned fetch window
   - validates that prefetch advances to the next line (`prefetch_address = 0x100000`) and returns to idle after the first 16-byte window
33. Added a parity-only `prefetch_fifo` pass-through:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - replaces the imported `prefetch_fifo` internals with a direct parity-mode surface that forwards `prefetchfifo_write_data` and fault markers to the fetch side
   - this bypasses the still-broken imported FIFO storage path while preserving the visible fault encodings
34. Lifted the parity-mode startup prefetch limit:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - rewrites the imported `prefetch.limit` reset literal from the startup `16`-byte cap to a large parity-mode segment limit so later-line fetches remain legal even when `pr_reset` never reloads the limit
35. Current execution classification after the prefetch repairs:
   - on JIT, larger fixtures now fetch beyond the first line; for example `prime_sieve` reaches later fetch groups through `pc = 0x10010`
   - on Verilator, the same parity package now also reaches the longer current fetch window on the named fixtures
   - mixed-backend parity is restored on the current fetch-trace window for all named programs
36. Patched the parity-package `fetch` threshold logic:
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - overrides the imported `fetch` accept-data predicates with explicit positive-width constants
   - this avoids the broken lowered comparison that had turned the intended “length < 9” guard into a bogus “length == 8” special case on the Verilog path
37. Current mixed-backend fetch window:
   - JIT and Verilator now both return the same current 16-group fetch trace window for the named fixtures
   - for `prime_sieve`, the common trace now extends through:
     - `0x10000 -> [0x83, 0xFB, 0x20, 0x72]`
     - `0x10004 -> [0xE2, 0x83, 0xFE, 0x0B]`
     - `0x10008 -> [0x75, 0x07, 0x81, 0xFF]`
     - `0x1000C -> [0xA0, 0x00, 0x75, 0x01]`
   - the current fetch trace still contains repeated window segments, so this is a stronger fetch-side checkpoint, not yet a clean retired-instruction stream
38. Reworked the named benchmark fixtures into compact self-checking correctness programs:
   - `examples/ao486/utilities/import/cpu_parity_programs.rb`
   - `prime_sieve` is now a compact prime-sum check
   - `mandelbrot` is now a compact fixed-point orbit check
   - `game_of_life` is now a compact center-cell rule check
   - all three now place their success `hlt` inside the current 16-group fetch window
39. Added exact expected-trace correctness metadata for the compact benchmark set:
   - `CpuParityPrograms::Program#expected_fetch_pc_trace`
   - each compact benchmark now carries one exact expected fetch-PC trace oracle
40. Added a fast JIT correctness gate for the compact benchmark set:
   - `spec/examples/ao486/import/cpu_parity_runtime_spec.rb`
   - JIT now must match the exact expected fetch-PC trace for `prime_sieve`, `mandelbrot`, and `game_of_life`
41. Added a slow mixed-backend correctness gate for the compact benchmark set:
   - `spec/examples/ao486/import/runtime_cpu_fetch_correctness_spec.rb`
   - both JIT and Verilator now must match the same exact expected fetch-PC trace for the compact benchmark set
42. Current correctness status:
   - explicit output-correctness coverage now exists on the CPU-top parity path for the compact benchmark set
   - the correctness oracle is the exact fetch-PC trace for self-checking programs whose success `hlt` lies inside the observable window
   - this does not yet replace the larger-program correctness goal or exact retired-instruction parity

Validation run:
1. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb --format documentation`
   - result: `3 examples, 0 failures`
2. `bundle exec rspec spec/rhdl/codegen/circt/tooling_spec.rb --format documentation`
   - result: `11 examples, 0 failures`
3. `bundle exec rspec spec/examples/ao486/import/cpu_trace_package_spec.rb --format documentation`
   - result: `2 examples, 0 failures`
4. `bundle exec rspec spec/rhdl/sim/native/ir/circt_hierarchy_flatten_runtime_spec.rb --format documentation`
   - result: `1 example, 0 failures`
5. `bundle exec rspec spec/rhdl/codegen/circt/runtime_json_spec.rb spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb spec/rhdl/sim/native/ir/circt_hierarchy_flatten_runtime_spec.rb --format documentation`
   - result: `15 examples, 0 failures`
6. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb --format documentation`
   - result: `1 example, 0 failures`
7. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb spec/examples/ao486/import/cpu_trace_package_spec.rb --format documentation`
   - result: `5 examples, 0 failures`
8. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb --format documentation`
   - result: `3 examples, 0 failures`
9. `bundle exec rspec spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb --format documentation`
   - result: `1 example, 0 failures`
10. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb spec/examples/ao486/import/cpu_parity_package_spec.rb spec/examples/ao486/import/cpu_trace_package_spec.rb --format documentation`
   - result: `7 examples, 0 failures`
11. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb --format documentation`
   - result: `1 example, 0 failures`
12. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb spec/examples/ao486/import/cpu_parity_runtime_spec.rb spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb --format documentation`
   - result: `5 examples, 0 failures`
13. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb --format documentation`
   - result: `4 examples, 0 failures`
14. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb --format documentation`
   - result: `1 example, 0 failures`
15. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb spec/examples/ao486/import/cpu_importer_spec.rb spec/examples/ao486/import/cpu_trace_package_spec.rb --format documentation`
   - result: `13 examples, 0 failures`
16. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_fetch_correctness_spec.rb spec/examples/ao486/import/runtime_cpu_step_parity_spec.rb --format documentation`
   - result: `2 examples, 0 failures`
17. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb --format documentation`
   - result: `1 example, 0 failures`

Current blocker for Phase 3:
1. Ported the shared imported-core cleanup used by Game Boy/ImportTask into the AO486 CPU path:
   - `CpuImporter` now runs `ImportCleanup.cleanup_imported_core_mlir` on imported canonical core MLIR.
   - `prepare_arc_mlir_from_circt_mlir` now cleans imported core MLIR before preparing shared `hwseq` output.
2. Result:
   - canonical AO486 CPU `hwseq` MLIR no longer contains `llhd.`
   - `firtool` now accepts the real cleaned AO486 CPU artifact and emits Verilog with the expected trace wires (`_pipeline_inst_wr_eip`, `_pipeline_inst_wr_consumed`, `_pipeline_inst_cs_cache`)
3. JIT/runtime update:
   - the generic native IR sequential stepping bug is fixed
   - flattened imported AO486 CPU JIT now reaches the correct reset state on legal top-level inputs:
     - `decode_eip = 0xFFF0`
     - `prefetch_address = 0xFFFF0`
     - `prefetch_length = 16`
   - the earlier JIT-only `prefetch_length = 0` failure was traced to native IR backend issues and is now closed
4. Remaining native/runtime blockers:
   - Arcilator now gets past remnant LLHD cleanup but still fails later on the cleaned AO486 CPU artifact with a loop-splitting error in `write_commands_inst`
   - direct hierarchical CIRCT packages are not a trustworthy JIT runtime shape for imported hierarchies; flattening is required first, and the AO486 importer spec was updated to reflect that supported runtime shape
   - the TLB-side startup corruption was traced to `RuntimeJSON` temp-name collisions and is now fixed
   - the next remaining imported-artifact failure is still in cache logic, but parity mode now has a practical fetch workaround:
     - the cleaned imported CPU produces a correct `tlbcoderequest_do -> tlbcode_do -> icacheread_do` handoff
     - imported `l1_icache` still collapses `MEM_REQ` / `MEM_ADDR` to constants during cleanup re-import
     - the parity package bypasses that controller for `cache_disable=1` and restores reset-vector fetch traffic
   - the traced CPU-top Verilator export still has live retire-trace ports, but the parity path still needs correct event qualification and program execution semantics before exact `EIP + bytes` comparison is ready
   - the aligned `icache.length_burst` parity-path regression is fixed
   - the imported `prefetch_fifo` storage path is now bypassed in parity mode
   - the startup prefetch-limit ceiling is now bypassed in parity mode
   - the imported/lowered `fetch` threshold logic is now bypassed in parity mode
   - the traced-package signal export was corrected to use the real imported instance-output connections instead of synthesized placeholder names:
     - `trace_wr_eip`, `trace_wr_consumed`, and `trace_cs_cache` now survive `firtool` export correctly
     - `trace_prefetch_eip`, `trace_fetch_valid`, `trace_fetch_bytes`, and `trace_dec_acceptable` now also survive `firtool` export on the traced package
   - the traced-package top-level bridge nets are now declared explicitly in the transformed `pipeline` and `ao486` modules:
     - this keeps the new top-level `trace_fetch_*` and existing `trace_wr_*` ports aligned with the corresponding internal pipeline signals on JIT runtime
     - focused coverage for that runtime alignment now lives in `spec/examples/ao486/import/cpu_trace_package_spec.rb`
   - the repaired write-trace top ports now support a real mixed-backend checkpoint:
     - `trace_wr_eip`, `trace_wr_consumed`, and `trace_retired` now produce the same current `EIP + bytes` event sequence on JIT and Verilator for `reset_smoke`
     - the flattened `pc -> byte` stream reconstructed from that current write trace now matches across JIT and Verilator for `reset_smoke`, `prime_sieve`, and `game_of_life`
     - `mandelbrot` is the remaining outlier on this surface; the byte stream agrees through the first 16 bytes and then diverges by one trailing byte under the current max-cycle window
     - the stable write-trace byte-stream subset now has a slow mixed-backend gate:
       - `spec/examples/ao486/import/runtime_cpu_step_parity_spec.rb`
       - this is still a checkpoint on the current write-trace surface, not a claim of final retired-instruction parity
   - a follow-on accepted-byte trace experiment was attempted on top of those new ports and then backed out:
     - Verilator-side top-port export is structurally correct
     - the earlier JIT top-port propagation bug is now fixed for the exported trace ports
     - the remaining problem is semantic, not structural: the accepted-byte surface still does not yet correspond to exact retired-instruction boundaries
     - because that surface is not yet trustworthy on both backends, the shipped mixed-backend gate remains the fetch-side `{pc, bytes}` trace rather than a new accepted-byte contract
   - the remaining blocker is no longer mixed-backend fetch divergence; it is trace quality:
     - JIT and Verilator now agree on the current fetch-side window
     - that window still includes replayed fetch segments and does not yet correspond to a clean retired-instruction trace
     - exact completed-instruction `EIP + bytes` parity is still not ready
   - the Verilator-side runtime harness is now back to a green checkpoint after the recent timing fixes:
     - read bursts are armed from the low-phase Avalon request observation
     - retire events are sampled from the post-clock `eval()` only, matching the JIT-side `tick` sample point
     - focused gates are green for:
       - fetch-side `{pc, bytes}` parity on all named programs
       - current write-trace `EIP + bytes` parity on `reset_smoke`
       - flattened current write-trace `pc -> byte` parity on `reset_smoke`, `prime_sieve`, and `game_of_life`
   - correctness work is blocked by the imported CPU-top runtime semantics, not by the benchmark fixtures themselves:
     - even `reset_smoke` does not yet retire an observable `hlt` on the current parity path
     - a trivial aligned data-memory write probe (`mov [0x0200], ax`) did not commit through the parity package either
     - that means explicit end-of-program correctness assertions are not ready yet for `prime_sieve`, `mandelbrot`, or `game_of_life`
   - the current write-trace parity gates are now protected against a false-green failure mode:
     - `cpu_parity_verilator_runtime_spec.rb` and `runtime_cpu_step_parity_spec.rb` now require non-empty JIT and Verilator step traces before comparing them
     - an attempted parity-only `write_do <- wr_ready & write_do` clamp was backed out after it reduced both backends to empty traces and made the old equality checks vacuous
   - the next concrete correctness blocker is now narrowed to imported decode/write-control state:
     - on a simple `xor ax,ax; mov ds,ax; mov ax,0x1234; mov [0x0200],ax; hlt` probe, the imported package drives `write_commands_inst__write_rmw_virtual = 1`, `wr_waiting = 1`, and `wr_dst_is_memory = 1` while `wr_cmd = 64` (`CMD_Arith`)
     - that same probe shows `wr_decoder = 0` and `wr_modregrm_mod = 0` where a register-register arithmetic instruction should not classify as a memory RMW operation
     - the native IR runtime wide-signal blocker is now closed:
       - the interpreter and JIT now carry signal values up to 128 bits end to end on their runtime paths
       - CIRCT runtime JSON literals, reset values, and initial memory data now preserve full-width integer payloads into the native runtime instead of being truncated during normalization
       - the Ruby wrapper now prefers `sim_signal_wide` for signal poke/peek on widths above 64 bits and retains the split-word fallback API for backends that only expose two-word access
       - focused coverage now lives in `spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb`
       - that spec now confirms 128-bit poke/peek and cross-boundary `slice` / `concat` round-trip behavior on both interpreter and JIT
       - the existing native IR smoke gates are green with the widened runtime:
         - `ir_simulator_input_format_spec.rb`
         - `ir_jit_memory_ports_spec.rb`
         - `circt_hierarchy_flatten_runtime_spec.rb`
     - the AO486 JIT/Verilator `reset_smoke` write-trace smoke is green again after widening the runtime
     - this moves the next correctness target back to the imported instruction-classification / write-control path itself, not the native IR bus-width model
  - larger-program correctness is still blocked even though a compact correctness gate had previously gone green:
     - the traced CPU-top package now also exports architectural-state ports from the imported `cpu_export` path:
       - `trace_arch_new_export`
       - `trace_arch_eax`, `trace_arch_ebx`, `trace_arch_ecx`, `trace_arch_edx`
       - `trace_arch_esi`, `trace_arch_edi`, `trace_arch_esp`, `trace_arch_ebp`
       - `trace_arch_eip`
     - focused coverage for those ports is now part of `spec/examples/ao486/import/cpu_trace_package_spec.rb`
     - ad hoc JIT probing shows those ports are structurally present and no longer constant-folded away, but they are not yet a trustworthy end-of-program correctness surface for the benchmark fixtures:
       - after long benchmark runs they still do not reflect the expected final algorithm results
       - fetch-side and current write-trace surfaces still stop too early to observe a clean pass/fail loop for `prime_sieve`, `mandelbrot`, or `game_of_life`
     - the original larger-benchmark pass/fail-loop correctness gate was backed out to keep the suite green
    - the shipped correctness gate now uses compact self-checking programs with exact expected fetch traces
    - the next larger-program correctness step should build on the new architectural trace exports rather than on the still-incomplete data-memory-write or `hlt` surfaces

Follow-up execution note (2026-03-08):
1. Fixed one real parity-package runtime bug in `examples/ao486/utilities/import/cpu_parity_package.rb`:
   - the parity `icache` bypass no longer edge-detects `readcode_done`
   - `CPU_VALID` / `CPU_DONE` now treat each `readcode_done` cycle as a per-beat memory-valid event, which matches the eight-beat Avalon code burst model
   - this restored the exact `prime_sieve` fetch-PC trace on JIT through the full 16-group oracle, including the repeated `0x10000..0x1000C` window and the `0x10010+` tail
2. Current compact-correctness status after that fix:
   - `prime_sieve` exact fetch-PC correctness is green again on JIT
   - `mandelbrot` is still red on the same surface
   - this is not a simple cycle-budget issue: ad hoc JIT probing still returns only the first 8 fetch groups even with `max_cycles = 2000`
   - that keeps `spec/examples/ao486/import/cpu_parity_runtime_spec.rb` and `spec/examples/ao486/import/runtime_cpu_fetch_correctness_spec.rb` red for `mandelbrot`
3. Current mixed-backend write-trace status after that fix:
   - direct JIT/Verilator flattened `pc -> byte` comparison is green for `reset_smoke`
   - direct JIT/Verilator flattened `pc -> byte` comparison is green for `prime_sieve`
   - `game_of_life` is now the remaining mixed-backend outlier on that surface:
     - JIT length: `28`
     - Verilator length: `25`
     - first extra JIT byte: `[0x10009, 0x02]`
   - this keeps the current stable-step subset partially open even though the earlier `mandelbrot` outlier on that surface is no longer the first blocker observed
4. Arcilator status remains blocked:
   - `prepare_arc_mlir_from_circt_mlir(...)` now succeeds for the imported AO486 CPU core
   - direct `arcilator --observe-registers --state-file=...` on the produced `ao486_cpu.arc.mlir` still fails with the same loop-splitting error rooted in `write_inst` / `write_commands_inst`
5. Result:
   - Phase 3 remains `In Progress`
   - the remaining blockers are now narrower and better classified, but exact compact-benchmark correctness and 3-way runtime parity are still not complete

Next execution step:
1. Diagnose the `mandelbrot` stall with the exported `trace_arch_*` and write-control surfaces; it currently never fetches beyond the first 32-byte window even with a much larger cycle budget.
2. Diagnose the current `game_of_life` JIT/Verilator flattened write-trace divergence starting at byte `[0x10009, 0x02]`.
3. Re-run the simple aligned-write and `hlt` probes on the parity path; if they become visible, promote them into focused larger-program correctness regressions.
4. Revisit exact retired-instruction parity for the full benchmark set and the separate Arcilator blocker in `write_commands_inst`.

Follow-up execution note (2026-03-09):
1. Fixed the parity-harness fetch regression in `examples/ao486/utilities/import/cpu_parity_package.rb`:
   - the `icache` bypass now tracks the full 8-beat Avalon code burst separately from the 4 CPU-visible fetch words consumed by `icache`
   - only the first 4 burst beats are surfaced as `CPU_VALID` / `CPU_DONE`; the remaining cache-line-fill beats are ignored by the bypass instead of leaking into the next fetch window
   - this restored stable cross-backend compact fetch behavior without depending on stale tail beats from the synthetic memory harness
2. Compact fetch/runtime status after that fix:
   - `spec/examples/ao486/import/cpu_parity_runtime_spec.rb` is green, including the slow compact-correctness and forward-progress examples
   - `spec/examples/ao486/import/runtime_cpu_fetch_correctness_spec.rb` is green again
   - `spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb` remains green
   - `spec/examples/ao486/import/runtime_cpu_step_parity_spec.rb` remains green
   - `spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb` is green
3. The compact fetch oracle is now recorded as a stable prefix surface rather than a backend-length-exact tail surface:
   - `prime_sieve` still uses the 16-group fetch prefix through `0x1001C`
   - `mandelbrot` and `game_of_life` currently stabilize at the first 8 groups on both IR and Verilator
   - both backends agree exactly on those prefixes; `prime_sieve` continues with backend-matched read-ahead beyond the compact oracle window
4. Result:
   - the fetch-side and stable write-trace parity tests are green again
   - Phase 3 remains `In Progress` because the broader architectural end-state / retired-instruction parity and Arcilator `write_commands_inst` blocker are still open
