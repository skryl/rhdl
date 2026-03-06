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

Validation run:
1. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb --format documentation`
   - result: `2 examples, 0 failures`
2. `bundle exec rspec spec/rhdl/codegen/circt/tooling_spec.rb --format documentation`
   - result: `10 examples, 0 failures`

Current blocker for Phase 3:
1. Ported the shared imported-core cleanup used by Game Boy/ImportTask into the AO486 CPU path:
   - `CpuImporter` now runs `ImportCleanup.cleanup_imported_core_mlir` on imported canonical core MLIR.
   - `prepare_arc_mlir_from_circt_mlir` now cleans imported core MLIR before preparing shared `hwseq` output.
2. Result:
   - canonical AO486 CPU `hwseq` MLIR no longer contains `llhd.`
   - `firtool` now accepts the real cleaned AO486 CPU artifact and emits Verilog with the expected trace wires (`_pipeline_inst_wr_eip`, `_pipeline_inst_wr_consumed`, `_pipeline_inst_cs_cache`)
3. Remaining native/runtime blockers:
   - Arcilator now gets past remnant LLHD cleanup but still fails later on the cleaned AO486 CPU artifact with a loop-splitting error in `write_commands_inst`
   - the JIT runtime branch is not yet behaviorally usable from the imported AO486 CPU artifact:
   - a local probe with the embedded reset-vector program did not advance fetch/decode state, indicating additional imported-runtime lowering/runtime gaps beyond importer setup.

Next execution step:
1. Build the Verilator runtime branch on top of the cleaned canonical `hwseq` MLIR path.
2. Investigate the cleaned-Arcilator loop-splitting failure in `write_commands_inst`.
3. Investigate why the imported AO486 JIT runtime path remains inert under the CPU bus/reset harness.
