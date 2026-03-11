# Status

Completed - 2026-03-10

# Context

The Game Boy import flow now emits runnable mixed-import Verilog artifacts into both the output tree and the import workspace:

- staged mixed-source entry Verilog (`pure_verilog_entry_path`)
- normalized imported Verilog (`normalized_verilog_path`)

The current Game Boy CLI/runtime flow for `--mode verilog` is still centered on Ruby HDL trees and `to_verilog` export through `VerilogRunner`. That is the wrong boundary for import-validation work when the goal is to run the imported Verilog artifacts directly, matching the integration/parity flow.

We need a direct-Verilog runner path so the CLI can:

1. perform a clean import into a workspace
2. point Verilator at the staged or normalized imported Verilog artifact/tree
3. run the same generated import wrapper top used by the current import parity tests

# Goals

1. Add a direct-Verilog input mode for Game Boy `--mode verilog` runs.
2. Allow the CLI to accept `--verilog-dir` alongside `--top` for direct imported-Verilog execution.
3. Keep the existing Ruby HDL export path working for `--hdl-dir`.
4. Reuse the same imported-wrapper topology the import tests use instead of falling back to handwritten HDL.
5. Provide a clean CLI command sequence that matches the import integration flow.

# Non-Goals

1. General-purpose arbitrary Verilog project ingestion for all examples/systems.
2. Replacing the existing `--hdl-dir` Ruby HDL workflow.
3. Reworking the import artifact layout.
4. Implementing generic Verilog dependency discovery beyond what the Game Boy import flow needs.

# Phased Plan

## Phase 1: Direct-Verilog interface and runner plumbing

### Red

1. Add failing CLI/task/runner expectations for:
   - `--verilog-dir`
   - pass-through to `RunTask`
   - pass-through to `HeadlessRunner`
   - pass-through to `VerilogRunner`

### Green

1. Plumb `verilog_dir` through:
   - `examples/gameboy/utilities/cli.rb`
   - `examples/gameboy/utilities/tasks/run_task.rb`
   - `examples/gameboy/utilities/runners/headless_runner.rb`
   - `examples/gameboy/utilities/runners/verilator_runner.rb`
2. Keep `--hdl-dir` behavior unchanged.

### Exit Criteria

1. New interface tests are green.
2. Existing `--hdl-dir` pass-through tests still pass.

## Phase 2: Direct imported-Verilog compile path

### Red

1. Add failing `VerilogRunner` specs showing:
   - direct-Verilog mode does not require Ruby component export
   - staged/normalized artifact selection can come from import report artifacts in the supplied directory/workspace
   - generated wrapper top can be compiled from direct imported Verilog input

### Green

1. Extend the shared Verilog simulator backend to compile one or more Verilog input files.
2. Add a direct-Verilog code path in `VerilogRunner` that:
   - skips `to_verilog`
   - uses the imported Verilog artifact(s) directly
   - builds/uses the generated import wrapper top
3. Reuse import report metadata where available.

### Exit Criteria

1. `VerilogRunner` direct-Verilog tests are green.
2. Existing generated-RHDL Verilator runner behavior still passes its targeted regressions.

## Phase 3: Integration validation and user workflow

### Red

1. Add or extend a targeted smoke/integration check for the CLI sequence:
   - clean import with workspace
   - direct Verilator run from imported Verilog artifacts

### Green

1. Run targeted sequential specs for CLI/task/runner coverage.
2. Run at least one direct imported-Verilog smoke command locally.
3. Document the exact commands for:
   - clean import
   - staged imported-Verilog run
   - normalized imported-Verilog run

### Exit Criteria

1. Targeted validation is green.
2. User-facing command sequence is confirmed against the actual implementation.

# Acceptance Criteria

1. `bin/gb --mode verilog` accepts `--verilog-dir`.
2. The direct-Verilog path skips Ruby HDL export.
3. The direct-Verilog path can use imported staged and normalized Verilog artifacts from a clean import workspace/output.
4. The CLI can run the generated imported wrapper top used by the import tests.
5. Existing `--hdl-dir` workflows remain intact.

# Risks and Mitigations

1. Risk: direct-Verilog runs lose the port metadata currently inferred from Ruby component classes.
   Mitigation: derive the needed port set from the imported wrapper/gameboy topology already used by tests, and keep the first cut scoped to Game Boy imported tops.

2. Risk: staged versus normalized artifacts require different compile inputs.
   Mitigation: use import report metadata explicitly and keep artifact-selection logic deterministic.

3. Risk: expanding the shared Verilog simulator compile surface regresses existing users.
   Mitigation: keep backward-compatible `verilog_file:` support and add targeted regression coverage.

# Implementation Checklist

- [x] Phase 1 red: add failing interface coverage for `--verilog-dir`
- [x] Phase 1 green: plumb `verilog_dir` through CLI/task/headless runner/Verilog runner
- [x] Phase 2 red: add failing direct-Verilog `VerilogRunner` coverage
- [x] Phase 2 green: implement direct imported-Verilog compile path
- [x] Phase 3 red: add/extend targeted direct imported-Verilog smoke coverage
- [x] Phase 3 green: run sequential validation and confirm user commands
