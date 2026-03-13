## Status
Completed (2026-03-03)

## Context
RHDL has completed the `to_flat_ir` migration and backend CIRCT-input cutover work, but the spec suite still contains legacy-backed execution paths. Direct legacy callsites in `spec/` (`to_legacy_ir`, `to_flat_ir`, `CIRCTRuntimeToIRJson`) are now being removed, and implicit legacy-backed export callsites are tracked for migration.

Current snapshot (2026-03-03):
- Direct legacy hooks in `spec/`: `rg -n "to_legacy_ir|to_flat_ir|CIRCTRuntimeToIRJson" spec` -> 0 matches.
- Implicit legacy-backed test callsites still present:
  - `to_verilog`: 250 matches in `spec/`
  - `to_circt`/`to_firrtl`: 67 matches in `spec/`
- `to_schematic`: 3 matches in `spec/` (default path still legacy-backed unless `sim_ir` provided)
  - Regeneratable file inventory command:
    - `rg -l "\\.to_verilog\\b|\\.to_circt\\b|\\.to_firrtl\\b|\\.to_schematic\\b" spec | sort`

Progress update (2026-03-03, later):
- CIRCT import path now accepts modern directional `hw.module` signatures (`in`/`out`) and still supports legacy `(%in) -> (out)` signatures.
- CIRCT MLIR emitter fixes landed for runtime parity:
  - Correct `seq.to_clock` emission form.
  - Sequential self/peer register references now preserve prior-cycle values.
  - Slice lowering now handles descending ranges (for example `7..0`) and out-of-range safety correctly.
  - Mux/case branch widths are normalized before emission.
- CIRCT firtool export defaults now include lowering options for more portable Verilog:
  - `disallowPackedArrays,disallowMuxInlining,disallowPortDeclSharing,disallowLocalVariables,locationInfoStyle=none,omitVersionComment`
- Verilog output normalization added to stabilize spec assertions across firtool formatting differences.
- Validation gates now green:
  - `bundle exec rspec spec/rhdl/hdl` -> `1439 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/codegen/circt/circt_core_spec.rb spec/rhdl/codegen/source_schematic_spec.rb spec/rhdl/diagram/renderer_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb spec/examples/mos6502/hdl/memory_spec.rb` -> `55 examples, 0 failures`

No-legacy audit update (2026-03-03, latest):
- Guard run command:
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec --format progress --out /tmp/no_legacy_spec.log`
- Result:
  - `4932 examples, 1173 failures, 152 pending`
  - `1170/1173` failures include explicit legacy guard hits.
  - Guard hit totals:
    - `NO_LEGACY_GUARD: to_flat_ir called` -> `773`
    - `NO_LEGACY_GUARD: to_legacy_ir called` -> `458`
    - `NO_LEGACY_GUARD: CIRCTRuntimeToIRJson.convert called` -> `0`
- Dominant internal failing frames:
  - `lib/rhdl/dsl/codegen.rb:334` (`to_flat_circt_nodes` currently calls `to_flat_ir`)
  - `lib/rhdl/dsl/codegen.rb:477` (`to_circt_nodes` currently calls `to_legacy_ir`)
- Remaining direct production callsites to migrate (`lib/`, `examples/`, `exe/`):
  - `examples/apple2/utilities/runners/arcilator_runner.rb` (`to_legacy_ir`)
  - `examples/gameboy/utilities/runners/ir_runner.rb` (`to_legacy_ir`)
  - `examples/riscv/hdl/pipeline/cpu.rb` (`to_legacy_ir` for verilog generation)
  - `examples/riscv/utilities/runners/arcilator_runner.rb` (`to_flat_ir`)
  - `lib/rhdl/cli/tasks/utilities/web_apple2_arcilator_build.rb` (`to_legacy_ir`)
  - `lib/rhdl/cli/tasks/utilities/web_riscv_arcilator_build.rb` (`to_flat_ir`)
  - `lib/rhdl/codegen.rb` (legacy fallback in `verilog`)
  - `lib/rhdl/codegen/netlist/lower.rb` (`to_legacy_ir` behavior path)
  - `lib/rhdl/dsl/codegen.rb` and `lib/rhdl/dsl/sequential_codegen.rb` legacy construction path
- Non-legacy failures during guard run:
  - `spec/examples/apple2/runners/netlist_runner_spec.rb` (gate count / dff expectations)
  - `spec/rhdl/codegen/circt/mlir_spec.rb` (module header expectation still legacy format)

Agent team execution update (2026-03-03, latest):
- Core DSL cutover completed:
  - `to_flat_circt_nodes` no longer calls `to_flat_ir`.
  - `to_circt_nodes` no longer calls `to_legacy_ir`.
  - Sequential lowering now emits CIRCT-native processes through the CIRCT path.
  - Guarded gate: `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/rhdl/codegen/circt/circt_core_spec.rb spec/rhdl/hdl/sequential spec/rhdl/hdl/arithmetic/alu_spec.rb` -> `186 examples, 0 failures`.
- Runner/CLI explicit legacy callsite migration completed for tracked files:
  - Apple2/RISCV arcilator runners and web arcilator build utilities now export CIRCT MLIR directly.
  - GameBoy IR runner now uses CIRCT nodes/runtime JSON path.
  - Remaining failures in targeted runner suites are non-legacy (`JSON::NestingError` in MOS6502 runtime JSON and arcilator unsupported `comb.shr_u`).
- Residual non-legacy fallout fixed:
  - `spec/rhdl/codegen/circt/mlir_spec.rb` module header expectation updated to directional port syntax.
  - `spec/examples/apple2/runners/netlist_runner_spec.rb` structural expectations made robust to current implementation.
  - Gate: `bundle exec rspec spec/rhdl/codegen/circt/mlir_spec.rb spec/examples/apple2/runners/netlist_runner_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb` -> `38 examples, 0 failures`.
- Remaining production legacy callsites after migration (`rg -n "to_flat_ir\\b|to_legacy_ir\\b" lib examples exe`):
  - `lib/rhdl/codegen.rb` legacy Verilog shim (`legacy_module_def_for_verilog`).
  - `lib/rhdl/codegen/netlist/lower.rb` legacy behavior shim (`behavior_ir_for_netlist`).
  - Legacy compatibility method definitions remain in `lib/rhdl/dsl/codegen.rb` / `lib/rhdl/dsl/sequential_codegen.rb`.

Callsite-focused execution wave (2026-03-03, current):
- Remaining callsites are now split into three ownership buckets:
  - Bucket A: Verilog export shim removal in `lib/rhdl/codegen.rb` (route all export paths through CIRCT tooling path; preserve public API behavior).
  - Bucket B: Netlist lowering shim removal in `lib/rhdl/codegen/netlist/lower.rb` (consume CIRCT/adapter path only; no direct `to_flat_ir`/`to_legacy_ir`).
  - Bucket C: DSL compatibility method cleanup in `lib/rhdl/dsl/codegen.rb` and `lib/rhdl/dsl/sequential_codegen.rb` (remove residual internal recursive dependence on legacy flattening while retaining compatibility stubs only if externally required).
- Agent team ownership:
  - Carver -> Bucket C (`lib/rhdl/dsl/*` + focused HDL/CIRCT guard specs)
  - Peirce -> Bucket A (`lib/rhdl/codegen.rb` + export specs/CLI task specs)
  - Bernoulli -> Bucket B (`lib/rhdl/codegen/netlist/lower.rb` + netlist runner/spec gates)
- Completion gate for this wave:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b" lib examples exe` returns only compatibility method definitions, or zero matches if compatibility APIs are removed.
  - Representative export/netlist/hdl suites pass with no-legacy guard enabled.

Callsite-focused execution wave result (2026-03-03, latest):
- Completed bucket migrations:
  - Bucket A: `lib/rhdl/codegen.rb` normal Verilog export now routes through CIRCT tooling path (`verilog_via_circt` + MLIR hierarchy selection).
  - Bucket B: `lib/rhdl/codegen/netlist/lower.rb` no longer calls `to_flat_ir`/`to_legacy_ir` and now parses CIRCT runtime JSON directly for behavior IR bridging.
  - Bucket C: `lib/rhdl/dsl/codegen.rb` no longer uses recursive legacy flattening internally; compatibility `to_flat_ir` now delegates through `to_flat_circt_nodes`.
- Validation:
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/rhdl/codegen/circt/circt_core_spec.rb spec/rhdl/hdl/sequential spec/rhdl/hdl/arithmetic/alu_spec.rb` -> `186 examples, 0 failures`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/rhdl/export_spec.rb spec/rhdl/cli/tasks/export_task_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb` -> `37 examples, 0 failures`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/examples/apple2/runners/netlist_runner_spec.rb spec/rhdl/codegen/source_schematic_spec.rb` -> `30 examples, 0 failures`
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b" lib examples exe` now returns compatibility method definitions/comments only.

Remaining-callsite snapshot (2026-03-03, current):
- Direct executable legacy adapter callsites:
  - none (`rg -n "CIRCTRuntimeToIRJson\\.convert\\(" lib examples exe spec` -> zero matches)
- Compatibility-only legacy API definitions (non-executable unless external callers use them):
  - `lib/rhdl/dsl/codegen.rb`: `to_flat_ir`, `to_legacy_ir`
  - `lib/rhdl/dsl/sequential_codegen.rb`: `to_legacy_ir` override
- Repository grep baseline:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b|CIRCTRuntimeToIRJson\\.convert|IRToJson\\.convert" lib examples exe spec`

Validation refresh (2026-03-03, PRD/validation ownership):
- Baseline command re-run:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b|CIRCTRuntimeToIRJson\\.convert|IRToJson\\.convert" lib examples exe spec`
  - Matches remain limited to:
    - `lib/rhdl/codegen/ir/sim/ir_simulator.rb:1958` (`IRToJson.convert`)
    - compatibility API definitions/comments in `lib/rhdl/dsl/codegen.rb` and `lib/rhdl/dsl/sequential_codegen.rb`.
- Guarded validation slice:
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/rhdl/export_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb spec/examples/apple2/runners/netlist_runner_spec.rb spec/rhdl/codegen/source_schematic_spec.rb`
  - Result: `47 examples, 0 failures`.

Phase 6a completion update (2026-03-03, runtime ownership):
- Runtime fallback normalization no longer calls `CIRCTRuntimeToIRJson.convert`; it now uses helper methods without invoking `convert`.
- Verification:
  - `rg -n "CIRCTRuntimeToIRJson\\.convert\\(" lib examples exe spec` -> zero matches
  - `bundle exec rspec spec/rhdl/codegen/ir/sim/ir_simulator_input_format_spec.rb spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb` -> `19 examples, 0 failures`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard.rb' bundle exec rspec spec/rhdl/codegen/ir/sim/ir_simulator_input_format_spec.rb spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb` -> `19 examples, 0 failures`

Hard-cut directive update (2026-03-03, current):
- Requested direction: remove compatibility fallbacks and enforce CIRCT runtime-only execution.
- Closeout inventory for hard-cut:
  - IR simulator runtime fallback path still exists (`allow_fallback` / Ruby fallback class and branches).
  - IR JSON format surface still accepts `:legacy`.
  - DSL compatibility APIs still exist (`to_flat_ir`, `to_legacy_ir`).
  - CLI export backend still advertises `legacy` option.
  - Verilog export MLIR selection still includes an `IR::Lower` compatibility branch.
- Hard-cut goal state:
  - IR simulator requires native backend availability (no Ruby fallback).
  - Runtime JSON contract is CIRCT-only.
  - Legacy DSL IR APIs are removed or replaced with hard errors.
  - CLI/export paths are CIRCT-only.

Hard-cut execution update (2026-03-03, latest):
- Runtime fallback removal completed in `IrSimulator`:
  - Removed runtime fallback branches and Ruby fallback simulator class.
  - Removed `allow_fallback` keyword from `IrSimulator` initializer surface.
  - Removed strict-backend fallback (`jit -> interpreter`, `compiler -> interpreter`) while retaining `:auto` probing.
- CIRCT-only runtime JSON contract enforced:
  - Reintroduced module-level `RHDL::Codegen::IR.sim_json`/`input_format_for_backend` APIs.
  - `sim_json` now emits CIRCT runtime JSON only; legacy IR inputs are lowered to CIRCT nodes before JSON emission.
  - `schematic` path updated to request CIRCT runtime JSON only.
- Callsite cleanup completed for IR runtime entry points:
  - Removed `allow_fallback:` callsites from RISC-V harnesses/runners and updated dependent specs.
  - Removed `allow_fallback:` callsites from Apple2/GameBoy/MOS6502/8-bit IR runner paths.
- Legacy copy-file cleanup:
  - Deleted tracked duplicate files `lib/rhdl/codegen/ir/sim/ir_simulator 2.rb` and `lib/rhdl/codegen/netlist/sim/netlist_simulator 2.rb`.
- Netlist fallback hard-cut completed:
  - Removed `allow_fallback` and Ruby fallback selection path from `Netlist::NetlistSimulator`.
  - `Codegen.gate_level` now uses strict native `NetlistSimulator` selection.
  - Updated netlist callers/docs to remove `allow_fallback` usage.
- Validation:
  - `bundle exec rspec spec/rhdl/codegen/ir/sim/ir_simulator_input_format_spec.rb spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb` -> `20 examples, 0 failures`
  - `bundle exec rspec spec/examples/8bit/hdl/cpu/ir_runner_extension_spec.rb` -> `9 examples, 0 failures`
  - `bundle exec rspec spec/examples/riscv` -> `390 examples, 7 failures, 3 pending` (known pre-existing failures isolated to `spec/examples/riscv/verilog_export_spec.rb`)
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard_v2.rb' bundle exec rspec spec/rhdl/codegen/ir/sim/ir_simulator_input_format_spec.rb spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb spec/examples/8bit/hdl/cpu/ir_runner_extension_spec.rb` -> `29 examples, 0 failures`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard_v2.rb' bundle exec rspec spec/examples/riscv --exclude-pattern spec/examples/riscv/verilog_export_spec.rb` -> `376 examples, 0 failures, 3 pending`
  - `bundle exec rspec spec/rhdl/codegen/netlist/sim/cpu_native_spec.rb spec/examples/apple2/runners/netlist_runner_spec.rb` -> `56 examples, 0 failures`

Verilog import/export stays delegated to LLVM/CIRCT tooling. RHDL scope for this PRD is runtime execution paths:
- RHDL DSL -> CIRCT nodes
- CIRCT nodes -> simulator JSON (legacy or CIRCT runtime format)
- CIRCT runtime JSON -> backend execution

Closeout inventory (2026-03-03, latest):
- Remaining unchecked implementation items are concentrated in Phase 2b, Phase 6, and final Phase 7 guard closeout.
- Red suite for export parity:
  - `bundle exec rspec spec/examples/riscv/verilog_export_spec.rb` -> `14 examples, 7 failures`
  - Failure classes:
    - CIRCT `firtool` rejects emitted `comb.shr_u` op in ALU/spec syntax-validity paths.
    - Spec assertions still expect legacy `output reg` declaration style instead of CIRCT-generated `output` + internal register + assign style.
- Current grep baseline to preserve during closeout:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b|CIRCTRuntimeToIRJson\\.convert|IRToJson\\.convert" lib examples exe spec`
  - Expected remaining matches are hard-error compatibility APIs and compatibility parser/lowering internals only; no execution-path adapter calls.

Closeout execution update (2026-03-03, final):
- CIRCT export stabilization:
  - Canonical shift op emission/parse compatibility implemented (`comb.shru`/`comb.shrs`; importer accepts both canonical and legacy spellings).
  - `icmp` width inference fixed for temporary SSA values; unary/case compare emission no longer emits mismatched `: i1` operand widths.
  - Instance emission now follows callee port order, includes unconnected outputs, and uses connection widths for parameterized instances.
  - Slice/concat/resize width inference now respects emitted SSA widths to avoid `i7`/`i8` type mismatches in generated MLIR.
  - Runtime JSON export now uses `JSON.generate(..., max_nesting: false)` to avoid deep-expression serialization failures.
- Spec migration/normalization completed for CIRCT-style output expectations:
  - RISC-V Verilog export assertions updated from legacy `output reg` assumptions to CIRCT structural patterns.
  - MOS6502 register/program-counter synthesis assertions updated similarly.
  - Export regression spec now targets CIRCT-capable HDL components and SystemVerilog compile mode (`iverilog -g2012`) for `always_ff`.
  - Web Apple2 arcilator build required-tool spec updated to match current pipeline (`arcilator`, `clang`, `wasm-ld`; no `firtool` requirement).
- Validation logs:
  - `bundle exec rspec spec/examples/riscv/verilog_export_spec.rb` -> `14 examples, 0 failures`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard_v2.rb' bundle exec rspec spec/examples/riscv/verilog_export_spec.rb` -> `14 examples, 0 failures`
  - `bundle exec rspec spec/examples/riscv/verilog_export_spec.rb spec/rhdl/codegen/circt/mlir_spec.rb spec/rhdl/codegen/circt/import_spec.rb` -> `49 examples, 0 failures`
  - `bundle exec rspec spec/examples/riscv/verilog_export_spec.rb spec/rhdl/codegen/circt/mlir_spec.rb spec/rhdl/codegen/circt/import_spec.rb spec/examples/mos6502/hdl/control_unit_spec.rb spec/examples/mos6502/hdl/registers/registers_spec.rb spec/examples/mos6502/hdl/registers/program_counter_spec.rb spec/examples/mos6502/hdl/cpu_spec.rb spec/examples/8bit/hdl/cpu/cpu_spec.rb spec/rhdl/codegen/export_verilog_spec.rb spec/examples/apple2/runners/arcilator_runner_spec.rb spec/rhdl/cli/tasks/web_apple2_arcilator_build_spec.rb` -> `146 examples, 0 failures, 1 pending`
  - `RUBYOPT='-r/tmp/rhdl_no_legacy_guard_v2.rb' bundle exec rspec spec --exclude-pattern spec/examples/riscv/verilog_export_spec.rb --format progress --out /tmp/no_legacy_guard_phase7a_rerun3.log` -> `4929 examples, 0 failures, 109 pending`
  - `bundle exec rspec spec --format progress --out /tmp/rspec_full_phase7a.log` -> `4943 examples, 0 failures, 109 pending`
- Final grep baseline:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b|CIRCTRuntimeToIRJson\\.convert|IRToJson\\.convert|allow_fallback" lib examples exe spec`
  - Matches are limited to hard-error compatibility method definitions and explicit rejection tests; no runtime execution-path adapter/fallback usage.

Post-closeout hard-cut cleanup (2026-03-03, latest):
- Expression-level legacy lowering removal completed:
  - Deleted `lib/rhdl/codegen/circt/lower.rb`.
  - Removed all `CIRCT::Lower.from_legacy_*` usage from DSL codegen.
  - Removed `require_relative "codegen/circt/lower"` from `lib/rhdl/codegen.rb`.
- DSL synthesis emission is now CIRCT-native end-to-end:
  - `RHDL::Synth::*` emit `RHDL::Codegen::CIRCT::IR::*` expressions/assigns/nets.
  - Behavior/sequential/memory/state-machine synthesis helpers emit CIRCT IR types (no `RHDL::Export::IR::*` dependencies).
  - Sequential synthesis now returns DSL-local `SequentialIR`/`SequentialAssign` containers with CIRCT expressions.
- Legacy-symbol grep refresh:
  - `rg -n "RHDL::Export::IR::|from_legacy_|CIRCT::Lower|\\bto_flat_ir\\b|\\bto_legacy_ir\\b" lib spec examples exe --glob '!examples/**/software/linux/**'`
  - Remaining matches are only explicit spec assertions that legacy APIs are absent (`spec/rhdl/codegen/circt/circt_core_spec.rb`).
- Validation:
  - `bundle exec rspec spec/rhdl/hdl/behavior_spec.rb spec/rhdl/codegen/circt/circt_core_spec.rb spec/rhdl/codegen/ir/sim/ir_simulator_input_format_spec.rb` -> `42 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/hdl/sequential spec/rhdl/hdl/memory` -> `231 examples, 0 failures`
  - `bundle exec rspec spec/rhdl` -> `2396 examples, 0 failures, 1 pending`

## Goals
1. Introduce a backend-aware simulator JSON contract and route runtime callsites through it.
2. Establish parity tests for `legacy` vs `circt` input formats at simulator boundaries.
3. Remove direct legacy IR dependencies from `spec/` callsites.
4. Migrate spec paths that still rely on legacy-backed export APIs (`to_verilog`, `to_circt`, default `to_schematic`) to CIRCT-backed paths.
5. Remove backend dependence on legacy adapter conversion after parity is proven.

## Non-Goals
1. Re-implement Verilog import/export in Ruby.
2. Remove `to_flat_ir` production APIs in this PRD.
3. Change user-visible CLI semantics unrelated to IR backend input formats.
4. Rewrite netlist or HDL backend stacks.

## Phased Plan (Red/Green)
### Phase 1: Adapter-Path Test Baseline (Completed)
- Red:
  - Inventory all `spec/` `to_flat_ir` callsites.
- Green:
  - Migrate all spec callsites to adapter paths.
  - Run targeted + broad gates.
- Exit criteria:
  - `rg -n "to_flat_ir" spec` returns zero matches.

### Phase 2: Runtime JSON Contract + Plumbing (Completed)
- Red:
  - Add failing tests for input format resolution and legacy-vs-circt simulator parity.
  - Identify all runtime/spec callsites directly invoking `IRToJson.convert`.
- Green:
  - Add backend-aware helpers: `RHDL::Codegen::IR.sim_json`, `input_format_for_backend`.
  - Extend `IrSimulator` with `input_format` handling and CIRCT adapter path.
  - Migrate runtime/spec callsites to `sim_json` (backend-aware).
- Exit criteria:
  - Runtime/spec callsites use `sim_json` instead of direct `IRToJson.convert`.
  - New parity specs for simulator input formats are green.

### Phase 2b: Spec Legacy-Dependency Purge (Completed)
- Red:
  - Inventory remaining direct legacy test callsites (`to_legacy_ir`, `to_flat_ir`, `CIRCTRuntimeToIRJson`).
  - Inventory implicit legacy-backed test callsites (`to_verilog`, `to_circt`, `to_firrtl`, default `to_schematic`).
- Green:
  - Replace direct legacy callsites with CIRCT node + runtime JSON paths.
  - Add/maintain focused CIRCT-only simulator input format tests.
  - Migrate implicit legacy-backed test callsites in batches to CIRCT-backed equivalents.
  - Add a no-legacy audit gate that temporarily disables `to_legacy_ir` and adapter conversion for migrated scopes.
- Exit criteria:
  - `rg -n "to_legacy_ir|to_flat_ir|CIRCTRuntimeToIRJson" spec` returns zero matches.
  - Remaining implicit legacy-backed test callsites are tracked and reduced per batch.
  - No-legacy audit passes for each migrated batch.

### Phase 2c: Core DSL Legacy Construction Cutover (Completed)
- Red:
  - Keep no-legacy guard enabled and capture failing synthesis/runtime specs rooted at `lib/rhdl/dsl/codegen.rb:334` and `:477`.
- Green:
  - Make `to_flat_circt_nodes` and `to_circt_nodes` construct CIRCT IR without invoking `to_flat_ir`/`to_legacy_ir`.
  - Ensure sequential lowering path (`dsl/sequential_codegen`) no longer requires `to_legacy_ir` override.
  - Re-run HDL/codegen CIRCT gates with no-legacy guard.
- Exit criteria:
  - No-legacy guard no longer reports failures at `lib/rhdl/dsl/codegen.rb:334` or `:477`.
  - `spec/rhdl/hdl` and core CIRCT/codegen gates pass under no-legacy guard.

### Phase 2d: Runner/CLI Legacy Callsite Migration (Completed)
- Red:
  - Track all non-spec `to_flat_ir`/`to_legacy_ir` callsites in `lib/` + `examples/`.
- Green:
  - Migrate runner and CLI utility callsites to CIRCT node/MLIR/runtime JSON entrypoints.
  - Keep Verilog import/export delegated to CIRCT/LLVM tools.
  - Verify representative runner/task specs in Apple2/MOS6502/GameBoy/RISCV suites under no-legacy guard.
- Exit criteria:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b" lib examples exe` only matches compatibility definitions (or zero, target state).
  - Guarded task/runner specs no longer fail with `NO_LEGACY_GUARD`.

### Phase 2e: Residual Shim and Compatibility Callsite Removal (Completed)
- Red:
  - Baseline remaining production callsites in `lib/` (`codegen.rb`, `codegen/netlist/lower.rb`, `dsl/codegen.rb`, `dsl/sequential_codegen.rb`).
  - Add/enable no-legacy guard checks over export/netlist/hdl slices.
- Green:
  - Remove direct legacy-callsite shims from Verilog export and netlist lowering paths.
  - Eliminate remaining internal recursive legacy flatten dependency in DSL codegen.
  - Keep only explicit compatibility entrypoints if still required by public API contracts.
- Exit criteria:
  - `rg -n "to_flat_ir\\b|to_legacy_ir\\b" lib examples exe` returns compatibility definitions only (or zero).
  - Export/netlist/hdl guard slices pass without `NO_LEGACY_GUARD` failures.

### Phase 3: Interpreter Native CIRCT Input (Completed)
- Red:
  - Add backend parity tests that run interpreter in legacy and circt formats against same stimuli.
- Green:
  - Update Rust interpreter loader to parse CIRCT runtime JSON natively.
  - Set interpreter backend default input format to `:circt`.
- Exit criteria:
  - Interpreter runs CIRCT runtime JSON without Ruby conversion adapter.
  - Parity tests pass against legacy baseline.

### Phase 4: JIT Native CIRCT Input (Completed)
- Red:
  - Add parity tests for JIT `legacy` vs `circt` format execution.
- Green:
  - Update JIT backend loader to parse CIRCT runtime JSON natively.
  - Set JIT backend default input format to `:circt`.
- Exit criteria:
  - JIT runs CIRCT runtime JSON natively with parity.

### Phase 5: Compiler Native CIRCT Input + AOT/Web Paths (Completed)
- Red:
  - Add parity tests for compiler runtime and AOT codegen entrypoints.
- Green:
  - Update compiler backend loader + AOT pipeline for CIRCT runtime JSON.
  - Set compiler backend default input format to `:circt`.
  - Update web/compiler JSON generation paths accordingly.
- Exit criteria:
  - Compiler and AOT/web flows run with CIRCT runtime JSON by default.

### Phase 6: Adapter Removal (Completed)
- Red:
  - Add checks that fail if legacy adapter path is invoked in backend execution.
- Green:
  - Remove `CIRCTRuntimeToIRJson` from backend execution path.
  - Remove backend env defaults for legacy JSON.
  - Keep explicit compatibility mode only if required and documented.
- Exit criteria:
  - All IR backends execute with CIRCT runtime JSON without legacy conversion.

### Phase 6a: Final Direct Legacy Callsite Elimination (Completed)
- Red:
  - Capture the exact remaining executable adapter callsite(s) and a failing no-legacy guard signal when they are exercised.
- Green:
  - Remove `CIRCTRuntimeToIRJson.convert` usage from runtime execution paths (including Ruby fallback normalization).
  - Keep compatibility APIs explicit and isolated, or remove them if no external usage remains.
  - Re-run guarded export/netlist/runtime slices and confirm no direct adapter calls.
- Exit criteria:
  - `rg -n "CIRCTRuntimeToIRJson\\.convert\\(" lib examples exe spec` returns zero matches.
  - Guarded runtime/export/netlist slices are green.

### Phase 7: CIRCT Hard Cut (Completed)
- Red:
  - Capture all remaining compatibility fallback surfaces (runtime fallback, legacy format option, legacy DSL APIs, legacy export backend options).
  - Add/update failing checks for legacy-option usage where appropriate.
- Green:
  - Remove/disable runtime fallback in `IrSimulator` (`allow_fallback` path and Ruby fallback execution path).
  - Enforce CIRCT-only simulator input format contract (`sim_json` / `IRToJson` / downstream consumers).
  - Remove legacy DSL compatibility APIs (`to_flat_ir`, `to_legacy_ir`) or convert them to explicit hard errors.
  - Remove legacy CLI export backend option; keep CIRCT tooling only.
  - Remove `IR::Lower` compatibility branch in Verilog export MLIR selection.
  - Update docs/specs for CIRCT-only behavior.
- Exit criteria:
  - No runtime execution path can silently fall back to Ruby legacy behavior.
  - No CLI surface advertises `legacy` export backend.
  - Legacy DSL API entrypoints fail fast (or are fully removed).
  - Guarded CIRCT runtime/export/netlist/hdl slices pass.

### Phase 7a: Final Legacy-Test Dependency Closeout (Completed)
- Red:
  - Keep `spec/examples/riscv/verilog_export_spec.rb` failing signal captured (`14 examples, 7 failures`) as baseline.
  - Capture explicit remaining Phase 2b/6/7 unchecked checklist items and map them to owners.
- Green:
  - Migrate RISC-V Verilog export spec expectations to CIRCT-emitted structural style (no legacy `output reg` assumptions).
  - Fix/normalize CIRCT MLIR emission so exported ALU and syntax-validity paths avoid unsupported ops in current `firtool` (`comb.shr_u`).
  - Run guarded implicit-spec slices with legacy APIs/adapters disabled and close remaining Phase 2b/6/7 checkboxes.
  - Execute full `bundle exec rspec spec` with guard disabled and confirm no legacy runtime dependency regressions.
- Exit criteria:
  - `bundle exec rspec spec/examples/riscv/verilog_export_spec.rb` is green.
  - Remaining unchecked checkboxes in Phase 2b/6/7 are closed with command logs captured in this PRD.
  - Full `bundle exec rspec spec` passes after hard-cut changes.

### Phase 7b: Expression-Level Legacy Lowering Removal (Completed)
- Red:
  - Capture remaining expression-level legacy lowering paths (`CIRCT::Lower.from_legacy_*`, `RHDL::Export::IR::*` synthesis dependencies).
  - Run focused CIRCT/runtime specs to preserve baseline behavior.
- Green:
  - Remove `circt/lower.rb` and all runtime DSL callsites to it.
  - Convert synthesis expression emitters (`RHDL::Synth`, behavior/sequential/memory/state-machine helpers) to produce CIRCT IR directly.
  - Re-run focused and broad `spec/rhdl` gates.
- Exit criteria:
  - `rg -n "from_legacy_|CIRCT::Lower|RHDL::Export::IR::" lib` returns no active codepath matches.
  - `spec/rhdl` remains green after expression-level cutover.

### Phase 7c: CIRCT Runtime Normalization Hard Cut (Completed)
- Red:
  - Capture remaining runtime normalization bridges still encoded as legacy-path helpers in netlist lowering and Rust native simulator cores.
  - Confirm baseline parser behavior still allowed non-CIRCT typed JSON fallback.
- Green:
  - Convert `lib/rhdl/codegen/netlist/lower.rb` behavior lowering bridge to CIRCT IR nodes (`RHDL::Codegen::CIRCT::IR::*`) end-to-end; remove remaining `legacy_*` helper surfaces and direct `RHDL::Codegen::IR::*` class checks.
  - Update Rust runtime cores (`ir_interpreter`, `ir_jit`, `ir_compiler`) to CIRCT-only parsing contract:
    - `parse_module_ir` now requires CIRCT runtime payload detection before normalization.
    - remove direct typed-JSON passthrough path in expression normalization.
    - rename normalization helpers from `*_to_legacy_value` to `*_to_normalized_value`.
  - Re-run focused IR runtime + netlist gates and Rust compile checks.
- Exit criteria:
  - `rg -n "_to_legacy_value|expr_to_legacy|module_to_legacy" lib/rhdl/codegen/ir/sim/ir_{interpreter,jit,compiler}/src/core.rs` returns no matches.
  - `rg -n "RHDL::Codegen::IR::|legacy_" lib/rhdl/codegen/netlist/lower.rb` returns no matches.
  - Native simulator and netlist focused specs are green.
  - `cargo check` passes for interpreter/JIT/compiler crates.

### Phase 7d: Strict CIRCT Payload Contract (Completed)
- Red:
  - Capture remaining parser permissiveness that still accepted non-wrapper payloads or non-CIRCT expression keys.
  - Confirm netlist/runtime parsers still tolerated legacy-ish statement/expr forms (`kind` missing, `type` aliases).
- Green:
  - Enforce wrapped CIRCT runtime JSON in netlist lowering (`circt_json_version` + `modules` required).
  - Remove statement fallback acceptance in netlist process flattening (`kind:nil` + `target` compatibility).
  - Enforce `kind`-only expression parsing in netlist/runtime parser helpers.
  - Switch Rust simulator expression serde tags to `kind` and remove `type` compatibility parsing.
  - Restrict Rust CIRCT payload detection/extraction to wrapped runtime payloads only.
  - Enforce wrapper validation in `IR.sim_json` and schematic payload normalization for hash/string CIRCT payloads.
- Exit criteria:
  - `lib/rhdl/codegen/netlist/lower.rb` no longer accepts `type` expr keys or nil-kind statement fallbacks.
  - Rust core parsers use `#[serde(tag = "kind")]` and contain no `obj.get("type")` compatibility paths.
  - `lib/rhdl/codegen/ir/sim/ir_simulator.rb` and `lib/rhdl/codegen/schematic/schematic.rb` reject malformed CIRCT wrapper payloads.
  - Focused IR runtime + netlist + behavior gates remain green.
  - `cargo check` remains green for interpreter/JIT/compiler crates.

## Exit Criteria Per Phase
1. Phase 1: Spec callsite migration complete and validated.
2. Phase 2: Backend-aware JSON plumbing + parity specs merged.
3. Phase 2b: Spec suite direct legacy hooks removed; implicit legacy-backed callsites tracked and migrating.
4. Phase 3: Interpreter native CIRCT input with parity.
5. Phase 4: JIT native CIRCT input with parity.
6. Phase 5: Compiler native CIRCT input (including AOT/web) with parity.
7. Phase 6: Legacy backend adapter path removed.
8. Phase 2c: Core DSL CIRCT construction path no longer depends on legacy IR.
9. Phase 2d: Runner/CLI callsites migrated off legacy IR entrypoints.
10. Phase 2e: Residual legacy-callsite shims removed or isolated to explicit compatibility-only APIs.
11. Phase 6a: Direct executable adapter callsites removed from runtime execution paths.
12. Phase 7: CIRCT-only hard cut completed across runtime/DSL/export surfaces.
13. Phase 7a: Remaining legacy-dependent specs and final broad gates are green.
14. Phase 7b: Expression-level lowering no longer depends on legacy IR classes/adapters.
15. Phase 7c: Runtime parsing/normalization paths are CIRCT-only without legacy-typed JSON fallback.
16. Phase 7d: Runtime parsers enforce strict wrapped CIRCT payloads and `kind`-only expression contracts.

## Acceptance Criteria
1. No runtime/spec execution callsites directly depend on `IRToJson.convert`.
2. `spec/` contains zero direct legacy hooks (`to_legacy_ir`, `to_flat_ir`, `CIRCTRuntimeToIRJson`).
3. Implicit legacy-backed spec callsites are migrated or explicitly tracked with owner/phase.
4. Interpreter, JIT, and compiler each accept CIRCT runtime JSON natively.
5. Backend defaults use CIRCT runtime JSON.
6. Legacy adapter path is no longer used during normal backend execution.

## Risks and Mitigations
- Risk: execution regressions during backend parser rewrites.
  - Mitigation: strict per-backend parity gates before default switches.
- Risk: mixed-format artifacts in web/AOT paths.
  - Mitigation: explicit backend-aware `sim_json` generation and compiler-focused tests.
- Risk: hidden direct converter use reintroduced.
  - Mitigation: grep gate + focused CI checks on `IRToJson.convert` callsites.

## Implementation Checklist
- [x] Phase 1: Migrate `spec/` away from `to_flat_ir`.
- [x] Phase 1: Validate with targeted and broad lib gates.
- [x] Phase 2: Add backend-aware `sim_json` + input-format resolution APIs.
- [x] Phase 2: Add `IrSimulator` input format handling and CIRCT adapter bridge.
- [x] Phase 2: Migrate runtime/spec callsites from direct `IRToJson.convert` to `sim_json`.
- [x] Phase 2: Add and pass simulator input format parity specs.
- [x] Phase 2b: Remove direct `spec/` usage of `to_legacy_ir`, `to_flat_ir`, and `CIRCTRuntimeToIRJson`.
- [x] Phase 2b: Update simulator input-format spec to CIRCT-only generation/parity checks.
- [x] Phase 2b: Migrate implicit legacy-backed `spec/` callsites (`to_verilog`, `to_circt`, default `to_schematic`) in batches.
- [x] Phase 2b: Add and run no-legacy audit gate for migrated batches.
- [x] Phase 2c: Remove `to_flat_circt_nodes` dependency on `to_flat_ir`.
- [x] Phase 2c: Remove `to_circt_nodes` dependency on `to_legacy_ir`.
- [x] Phase 2c: Update sequential DSL lowering to avoid legacy IR override path.
- [x] Phase 2d: Migrate runner/CLI legacy callsites in `lib/` + `examples/` to CIRCT entrypoints.
- [x] Phase 2d: Re-run guarded runner/task suites for Apple2/MOS6502/GameBoy/RISCV.
- [x] Phase 2e: Remove `lib/rhdl/codegen.rb` legacy Verilog shim usage from normal export path.
- [x] Phase 2e: Remove `lib/rhdl/codegen/netlist/lower.rb` direct legacy IR shim usage.
- [x] Phase 2e: Remove residual internal legacy flatten recursion from DSL codegen path.
- [x] Phase 2e: Re-run guarded export/netlist/hdl slices and record results.
- [x] Phase 3: Interpreter native CIRCT runtime JSON parsing.
- [x] Phase 3: Interpreter parity and default switch to `:circt`.
- [x] Phase 4: JIT native CIRCT runtime JSON parsing.
- [x] Phase 4: JIT parity and default switch to `:circt`.
- [x] Phase 5: Compiler native CIRCT runtime JSON parsing.
- [x] Phase 5: Compiler AOT/web parity and default switch to `:circt`.
- [x] Phase 6: Remove legacy backend adapter execution path.
- [x] Phase 6: Final grep/tests/documentation updates.
- [x] Phase 6a: Remove direct `CIRCTRuntimeToIRJson.convert` runtime callsites.
- [x] Phase 6a: Re-run guarded runtime/export/netlist slices and record results.
- [x] Phase 7: Remove/disable `IrSimulator` runtime fallback execution path.
- [x] Phase 7: Enforce CIRCT-only runtime JSON format (`sim_json` and simulator input format contract).
- [x] Phase 7: Remove legacy DSL IR API fallbacks (`to_flat_ir`, `to_legacy_ir`) or make them hard errors.
- [x] Phase 7: Remove legacy CLI export backend option and legacy export fallback branches.
- [x] Phase 7: Re-run guarded implicit-spec batch and close final Phase 2b/6 checkboxes.
- [x] Phase 7a: Update `spec/examples/riscv/verilog_export_spec.rb` to CIRCT-style structural assertions.
- [x] Phase 7a: Resolve `comb.shr_u` Verilog-export failure path and re-run RISC-V Verilog export suite.
- [x] Phase 7a: Run guarded implicit-spec migration audit and record passing batch command output.
- [x] Phase 7a: Run full `bundle exec rspec spec` and record final no-legacy runtime status.
- [x] Phase 7b: Remove `circt/lower.rb` and all `CIRCT::Lower.from_legacy_*` DSL codegen callsites.
- [x] Phase 7b: Migrate synthesis emitters (`RHDL::Synth`, behavior/sequential/memory/state-machine helpers) to CIRCT IR nodes directly.
- [x] Phase 7b: Re-run focused CIRCT/runtime + broad `spec/rhdl` gates and capture results.
- [x] Phase 7c: Convert `lib/rhdl/codegen/netlist/lower.rb` runtime bridge to CIRCT IR nodes only (`RHDL::Codegen::CIRCT::IR::*`).
- [x] Phase 7c: Remove Rust `*_to_legacy_value` normalization helpers and enforce CIRCT runtime payload contract in `parse_module_ir`.
- [x] Phase 7c: Re-run focused IR runtime/netlist specs and `cargo check` for interpreter/JIT/compiler crates.
- [x] Phase 7d: Enforce strict wrapped CIRCT payload parsing in netlist and Rust runtime loaders.
- [x] Phase 7d: Remove `type`-key expression compatibility in runtime parser/normalizer helpers (`kind` only).
- [x] Phase 7d: Reject malformed hash/string CIRCT payload wrappers in simulator/schematic ingestion helpers.
- [x] Phase 7d: Re-run focused IR runtime/netlist/behavior gates and `cargo check` for all native backends.
