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
   - validates the first reset-vector fetch words for a tiny reset-vector program placed directly at `0xFFFF0`
22. Current execution classification after the helper:
   - the corrected burst scheduler now returns the expected reset-vector fetch words on JIT
   - prefetch-side byte flow is observable and stable enough for harness reuse
   - write-stage trace remains unreliable for exact parity: `trace_wr_eip` / `trace_wr_consumed` do not yet correspond to a clean retired-instruction stream on the parity path

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

Next execution step:
1. Mirror the parity runtime helper on the `firtool -> Verilator` branch and compare the first reset-vector fetch words / byte groups across JIT and Verilator on the same parity package artifact.
2. Either repair the write-stage event surface or formally switch the runtime parity contract to a fetch-side `PC + byte-group` trace if that proves to be the stable imported-code boundary.
3. Once the parity package has a stable mixed-backend trace contract on JIT and Verilator, wire it into the slow mixed-backend spec and revisit the Arcilator branch separately if `write_commands_inst` loop-splitting is still blocking.
