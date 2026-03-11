# Full scoped suite remediation PRD

## Status
- Proposed: 2026-03-11
- In Progress: 2026-03-11
- Completed: -

## Context
- Scope executed: full scoped suite excluding `ao486`, `gameboy`, and `sparc64` examples.
- Command run:
  - `INCLUDE_SLOW_TESTS=1 bundle exec rake spec:lib spec:hdl spec:apple2 spec:mos6502 spec:riscv`
- Scope intentionally skips `ao486`, `gameboy`, and `sparc64` example suites.
- Baseline result (latest run): `2708 examples, 42 failures, 12 pending`.

## Goals
- Produce an auditable PRD of all currently failing tests.
- Fix all non-environment failures where feasible.
- Keep code changes minimal and localized.

## Non-goals
- Do not scope in `ao486`, `gameboy`, or `sparc64` tests for this pass.
- Do not add new features unrelated to the failing test clusters.
- Do not introduce new test infrastructure unrelated to this remediation.

## Phased plan

### Phase 1 (Red)
- Capture and normalize the baseline failure list.
- Classify failures by root-cause cluster.
- Confirm blockers that are environment/runtime unavailable versus source defects.

### Phase 2 (Green)
- Fix import/task configuration shape regressions:
  - `lib/rhdl/cli/tasks/import_task.rb`
  - `lib/rhdl/cli/tasks/import_task_spec.rb` adjustments if needed
- Fix source schematic export regression:
  - `lib/rhdl/codegen/source_schematic.rb`
  - `lib/rhdl/codegen/source_schematic_spec.rb`

### Phase 3 (Green)
- Fix CIRCT import/assign preservation pipeline regressions:
  - `lib/rhdl/sim/context.rb` (`LocalProxy` concat behavior)
  - `lib/rhdl/codegen/circt/import.rb`
  - `lib/rhdl/codegen/circt/raise.rb`
  - `lib/rhdl/hdl/arithmetic/alu.rb`
  - `lib/rhdl/hdl/combinational/barrel_shifter.rb`
  - Relevant CIRCT/RHDL parser/render specs

### Phase 4 (Green)
- Fix IR compiler extension ABI mismatch in generated extension code:
  - `lib/rhdl/sim/native/ir/ir_compiler/src/extensions/apple2/mod.rs`
  - `lib/rhdl/sim/native/ir/ir_compiler/src/extensions/mos6502/mod.rs`
  - `lib/rhdl/sim/native/ir/ir_compiler/src/bin/aot_codegen.rs`

### Phase 5 (Green)
- Re-run the same scoped command and close remaining failures that are actual code regressions.

## Exit criteria
- Phase 1: all 42 failing examples enumerated in this document with status + category.
- Phase 2-4: cluster-specific changes landed with local test slices green.
- Phase 5: rerun `INCLUDE_SLOW_TESTS=1 bundle exec rake spec:lib spec:hdl spec:apple2 spec:mos6502 spec:riscv`.
- Final green condition: only environment-related Netlist backend skips remain; all code defects fixed.

## Acceptance criteria
- Full scoped command rerun completes with zero code-related failures.
- Netlist-backed failures are either fixed by rebuilding native backends or documented as environment blockers when unavailable.
- PRD checklist reflects actual completion state with evidence from rerun.

## Risks and mitigations
- **Risk:** Native Netlist extensions are missing locally and can mask otherwise green code paths.
  - Mitigation: keep those failures marked as environment blockers unless code change is confirmed needed.
- **Risk:** CIRCT/ALU and barrel shifter failures may be coupled to simulator/export parser behavior.
  - Mitigation: fix parser/rendering primitives first, then rerun the impacted specs.
- **Risk:** IR compiler failures are ABI mismatches in generated extensions and could reappear if templates drift.
  - Mitigation: align emitted Rust signatures with actual simulator core type usage.

## Implementation checklist
- [x] Create/update PRD with exact command and failing counts.
- [x] [Phase 1] Enumerate all 42 failing tests and classify by root cause.
- [ ] [Phase 2] Align import task mixed config normalization and staged entrypoint generation.
- [ ] [Phase 2] Fix source_schematic export regression.
- [ ] [Phase 3] Address CIRCT API/assign preservation regressions (array_get/concat/import roundtrip).
- [ ] [Phase 3] Resolve ALU and barrel shifter codegen compatibility with Verilog backends.
- [ ] [Phase 4] Correct IR extension generated ABI in Apple2/MOS6502 Rust outputs.
- [ ] [Phase 5] Re-run scoped test command and record final outcome.

## Latest scoped rerun summary (2026-03-11)
- Command re-run:
  - `INCLUDE_SLOW_TESTS=1 bundle exec rake spec:lib spec:hdl spec:apple2 spec:mos6502 spec:riscv`
- Current rerun still aborts inside `spec:rhdl`, so `spec:hdl`, `spec:apple2`, `spec:mos6502`, and `spec:riscv` never start.
- The progress formatter showed multiple ordinary failures before the abort, but the native crash prevented a complete named failure summary for this rerun.
- Latest hard crash signature:
  - crashing example: `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:353`
  - Ruby entrypoint: `lib/rhdl/sim/native/ir/simulator.rb:879`
  - failing native path: `generated_code` -> `core_blob`
  - Rust panic site: `src/core.rs:2455:69`
  - panic text: `index out of bounds: the len is 0 but the index is 0`
- Current Phase 5 status:
  - still red
  - blocked by the IR compiler native crash during `spec:rhdl`
  - not yet a valid completion rerun for this PRD

## Failing tests to fix (42)
1. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[1:4:1]` `RHDL::CLI::Tasks::BenchmarkTask` environment variables respects `RHDL_BENCH_LANES`
2. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[1:4:2]` `RHDL::CLI::Tasks::BenchmarkTask` environment variables respects `RHDL_BENCH_CYCLES`
3. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[1:3:1]` `BenchmarkTask#benchmark_gates` runs gate benchmark and reports results
4. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[1:2:1:1]` `BenchmarkTask#run` with type: `:gates` starts gate benchmark without error
5. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[1:2:1:2]` `BenchmarkTask#run` with type: `:gates` respects lanes and cycles parameters
6. `spec/rhdl/cli/headless_runner_spec.rb:207` `RHDL::Examples::Apple2::HeadlessRunner` Netlist mode creates netlist mode runner
7. `spec/rhdl/cli/headless_runner_spec.rb:189` `RHDL::Examples::Apple2::HeadlessRunner` IR mode with compile backend creates IR mode runner
8. `spec/rhdl/cli/headless_runner_spec.rb:195` `RHDL::Examples::Apple2::HeadlessRunner` IR mode with compile backend respects sub-cycles option
9. `spec/rhdl/codegen/source_schematic_spec.rb:42` `RHDL source/schematic exports` exports a schematic bundle for a component hierarchy
10. `spec/rhdl/hdl/arithmetic/alu_spec.rb[1:2:5:1]` `RHDL::HDL::ALU` synthesis CIRCT firtool validation parity
11. `spec/rhdl/hdl/arithmetic/alu_spec.rb[1:2:6:1]` `RHDL::HDL::ALU` synthesis iverilog behavior simulation parity
12. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[2:2:1:2]` `BenchmarkTask#run` with type: `:gates` respects lanes and cycles parameters
13. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[2:2:1:1]` `BenchmarkTask#run` with type: `:gates` starts gate benchmark without error
14. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[2:3:1]` `BenchmarkTask#benchmark_gates` runs gate benchmark and reports results
15. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[2:4:2]` `BenchmarkTask` environment variables respects `RHDL_BENCH_CYCLES`
16. `spec/rhdl/cli/tasks/benchmark_task_spec.rb[2:4:1]` `BenchmarkTask` environment variables respects `RHDL_BENCH_LANES`
17. `spec/rhdl/codegen/gate_level_equivalence_spec.rb:53` Gate-level backend equivalence matches ripple adder outputs
18. `spec/rhdl/codegen/gate_level_equivalence_spec.rb:87` Gate-level backend equivalence matches register outputs over cycles
19. `spec/rhdl/codegen/gate_level_equivalence_spec.rb:25` Gate-level backend equivalence matches full adder outputs
20. `spec/rhdl/codegen/gate_level_equivalence_spec.rb:147` Gate-level backend equivalence matches muxed datapath outputs over cycles
21. `spec/rhdl/codegen/circt/api_spec.rb:187` CIRCT `.import_circt_mlir` rewrites `llhd.sig.array_get` drive targets
22. `spec/rhdl/codegen/circt/api_spec.rb:277` CIRCT `.import_circt_mlir` preserves loop backedge state
23. `spec/rhdl/codegen/circt/assign_preservation_spec.rb:161` CIRCT assign-preservation roundtrip for multi-drive outputs
24. `spec/rhdl/codegen/circt/assign_preservation_spec.rb:167` CIRCT assign-preservation roundtrip for input-target `llhd.drv`
25. `spec/rhdl/codegen/circt/assign_preservation_spec.rb[1:4]` CIRCT assign-preservation roundtrip for `l1_icache`
26. `spec/rhdl/codegen/circt/assign_preservation_spec.rb[1:2]` CIRCT assign-preservation roundtrip for `decode`
27. `spec/rhdl/codegen/circt/assign_preservation_spec.rb[1:6]` CIRCT assign-preservation roundtrip for `memory`
28. `spec/rhdl/codegen/circt/assign_preservation_spec.rb[1:5]` CIRCT assign-preservation roundtrip for `execute_divide`
29. `spec/rhdl/codegen/circt/assign_preservation_spec.rb[1:3]` CIRCT assign-preservation roundtrip for `execute`
30. `spec/rhdl/hdl/arithmetic/alu_spec.rb[2:2:5:1]` `RHDL::HDL::ALU` synthesis CIRCT firtool validation parity
31. `spec/rhdl/hdl/arithmetic/alu_spec.rb[2:2:6:1]` `RHDL::HDL::ALU` synthesis iverilog behavior simulation parity
32. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:124` IrCompiler vs IrInterpreter PC progression comparison produces consistent PC sequence after boot
33. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:177` IrCompiler vs IrInterpreter PC progression comparison produces identical transitions for 500 cycles
34. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:234` IrCompiler vs IrInterpreter PC progression compiled mode register state comparison
35. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:85` IrCompiler vs IrInterpreter PC progression basic functionality resets to same state
36. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:104` IrCompiler vs IrInterpreter PC progression batched-step parity with single-cycle path
37. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:69` IrCompiler vs IrInterpreter PC progression load and initialize correctly
38. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:347` IrCompiler vs IrInterpreter PC progression code generation generates valid Rust code
39. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:291` IrCompiler vs IrInterpreter PC progression compiled mode performance can compile code
40. `spec/rhdl/sim/native/ir/ir_compiler_spec.rb:309` IrCompiler vs IrInterpreter PC progression compiled mode performance parity
41. `spec/rhdl/cli/tasks/import_task_mixed_spec.rb:62` ImportTask mixed config resolution retains `vhdl.synth_targets` normalization
42. `spec/rhdl/cli/tasks/import_task_mixed_spec.rb:196` ImportTask mixed staging orchestration writes staged Verilog entrypoint
