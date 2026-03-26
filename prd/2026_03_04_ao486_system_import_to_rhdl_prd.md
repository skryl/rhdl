# AO486 System Import To RHDL PRD

## Status
Completed (2026-03-04)

## Context
We need an AO486 import flow under the new CIRCT-first architecture that produces RHDL DSL output in the repository at:

- `examples/ao486/hdl`

Constraints:

1. Verilog -> CIRCT import and CIRCT -> Verilog export must stay delegated to LLVM/CIRCT tooling.
2. RHDL scope is CIRCT -> RHDL raise and RHDL -> CIRCT emission.
3. AO486 full-chip source is large; initial delivery can use a deterministic blackbox stub strategy to get a valid import/raise baseline for `rtl/system.v`.

## Goals
1. Add an AO486 importer utility that ingests `examples/ao486/reference/rtl/system.v` through CIRCT tooling.
2. Implement deterministic blackbox stub generation for unresolved submodules.
3. Raise resulting CIRCT core MLIR to RHDL DSL.
4. Export raised DSL files to `examples/ao486/hdl`.
5. Add AO486 import specs under `spec/examples/ao486/import`.

## Non-Goals
1. Full behavioral parity against original AO486 in this phase.
2. Importing every AO486 submodule body (stubs are acceptable in phase 1).
3. Rewriting CIRCT import/export tooling in Ruby.

## Phased Plan (Red/Green)
### Phase 1: AO486 Importer Skeleton + Red Spec
Red:
- Add AO486 importer spec that expects a CIRCT-tool-backed `system.v` import path and RHDL output generation.

Green:
- Add `SystemImporter` utility with:
  - deterministic `system.v` normalization for known parse blockers
  - deterministic blackbox stub generation from instance ports
  - Verilog->Moore (`circt-translate`) and Moore->core (`circt-opt`) pipeline
  - CIRCT->RHDL raise hook

Exit criteria:
- AO486 importer spec passes and writes `system.rb` in a test output directory.

### Phase 2: Repository Export Target + Artifacts
Red:
- Add failing integration check for final export target location.

Green:
- Wire importer defaults so production output lands in `examples/ao486/hdl`.
- Execute importer once to populate/update `examples/ao486/hdl` artifacts.

Exit criteria:
- `examples/ao486/hdl/system.rb` exists from importer output.

### Phase 3: Import Path Coverage + Round-Trip Hooks
Red:
- Add failing AO486 import path specs that validate generated CIRCT artifacts and raise diagnostics budget.

Green:
- Expand test coverage for:
  - Verilog (`system.v` + stubs) -> CIRCT core MLIR
  - CIRCT core MLIR -> RHDL DSL
  - RHDL DSL -> CIRCT MLIR (round-trip smoke)

Exit criteria:
- AO486 import path suite is stable and tool-gated.

### Phase 4: Behavioral Parity Harness (Follow-on)
Red:
- Add failing parity harness scaffolding for source Verilog vs raised RHDL on selected AO486 signals.

Green:
- Add bounded parity checks (non-full-chip exhaustive) using Verilator for source and IR backend for raised target on deterministic stub-safe outputs.

Exit criteria:
- At least one deterministic parity scenario is passing.

## Exit Criteria Per Phase
1. Phase 1: Importer utility and first AO486 import spec are green.
2. Phase 2: Final output target (`examples/ao486/hdl`) is populated by importer.
3. Phase 3: AO486 path tests cover import/raise/round-trip smoke.
4. Phase 4: Initial parity harness passes.

## Acceptance Criteria
1. AO486 importer exists and uses CIRCT tooling for Verilog->CIRCT.
2. Raised DSL output is written to `examples/ao486/hdl` by default.
3. Specs exist under `spec/examples/ao486/import` and validate importer behavior.
4. The flow remains compatible with CIRCT-only RHDL runtime direction.

## Risks And Mitigations
- Risk: CIRCT import rejects AO486 syntax patterns.
  - Mitigation: normalize known blockers and use deterministic blackbox stubs.
- Risk: CIRCT core output contains forms current raise parser cannot ingest.
  - Mitigation: normalize known header variants (`hw.module private`) before raise and track unsupported op warnings.
- Risk: Parity harness is expensive/flaky.
  - Mitigation: keep parity tests bounded and deterministic; gate heavier runs.

## Testing Gates
1. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb`
2. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb`

## Implementation Checklist
- [x] PRD created.
- [x] Phase 1: Add AO486 importer utility.
- [x] Phase 1: Add AO486 importer spec.
- [x] Phase 1: Run AO486 importer spec gate.
- [x] Phase 2: Export generated DSL to `examples/ao486/hdl`.
- [x] Phase 3: Add AO486 import path round-trip coverage.
- [x] Phase 4: Add bounded behavioral parity harness.

## Execution Update (2026-03-04)
- Confirmed a deterministic bootstrap pipeline works locally:
  - `system.v` + generated blackbox stubs imports via `circt-translate`.
  - Moore lowers to core with `circt-opt --moore-lower-concatref --convert-moore-to-core --llhd-sig2reg --canonicalize`.
  - Raised DSL generation works when normalizing `hw.module private` headers.
- Proceeding to land this flow as `examples/ao486` importer code + specs.

## Execution Update (2026-03-04, current)
- Landed importer utility:
  - `examples/ao486/utilities/import/system_importer.rb`
  - Defaults output to `examples/ao486/hdl`.
  - Implements:
    - deterministic `system.v` normalization for known declaration-order blockers
    - deterministic blackbox stub generation from `system.v` instance ports
    - Verilog->Moore import via `circt-translate`
    - Moore->core lowering via `circt-opt` pass pipeline
    - core MLIR normalization (`hw.module private` -> `hw.module`) before raise
    - CIRCT->RHDL raise via `RHDL::Codegen.raise_circt`
- Added AO486 importer spec:
  - `spec/examples/ao486/import/system_importer_spec.rb`
  - Covers default final output location and end-to-end import/raise.
- Exported AO486 raised DSL artifacts to final target:
  - `examples/ao486/hdl/*.rb` (16 files including `system.rb`).
- Validation:
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> `2 examples, 0 failures`
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `7 examples, 0 failures`

## Execution Update (2026-03-04, phase 3)
- Expanded AO486 spec coverage in `spec/examples/ao486/import/system_importer_spec.rb`:
  - Verilog (`system.v` + generated stubs) -> CIRCT artifact checks (`moore`, `core`, normalized core MLIR paths).
  - CIRCT normalized core MLIR -> RHDL DSL checks.
  - CIRCT -> RHDL -> CIRCT smoke on imported top module (`system`) with re-import validation.
- Hardened CIRCT raise emitter for uppercase port/signal names:
  - behavior/sequential emissions now use `self.send(:name)` when needed for non-lowercase identifiers.
  - added regression coverage in `spec/rhdl/codegen/circt/raise_spec.rb`.
- Validation:
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> `4 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb` -> `12 examples, 0 failures`
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `9 examples, 0 failures`

## Execution Update (2026-03-04, phase 4)
- Added bounded AO486 parity harness:
  - `spec/examples/ao486/import/parity_spec.rb`
  - Flow:
    - source path: `system.v` + deterministic generated stubs via importer workspace
    - source execution: Verilator compile/run over deterministic vectors
    - target execution: CIRCT->RHDL raised top (`system`) via all available IR backends (`interpreter`, `jit`, `compiler`)
    - comparison: sampled trace equality for bounded stub-safe outputs
- Scope note:
  - This parity is intentionally scoped to stub-safe outputs in the blackbox-stub baseline.
  - Known non-stub-safe signals (for example direct/complex source-only behavior under current raise limits) are excluded from this phase.
- Validation:
  - `bundle exec rspec spec/examples/ao486/import/parity_spec.rb` -> `1 example, 0 failures`
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `10 examples, 0 failures`

## Execution Update (2026-03-04, automation)
- Added reusable AO486 automation task class:
  - `lib/rhdl/cli/tasks/ao486_task.rb`
  - Supports actions:
    - `:import` (run importer and raise flow)
    - `:parity` (run bounded parity spec)
    - `:verify` (run importer + parity + import-path verification specs)
- Added first-class CLI command surface:
  - `rhdl ao486 import --out <dir>`
  - `rhdl ao486 parity`
  - `rhdl ao486 verify`
  - documented in `docs/cli.md`
- Added rake entrypoints:
  - `ao486:import[output_dir,workspace_dir]`
  - `ao486:parity`
  - `ao486:verify`
- Added AO486 as a first-class test scope in generic spec tasks:
  - `bundle exec rake spec[ao486]`
  - `bundle exec rake pspec[ao486]`
  - `bundle exec rake spec:bench[ao486,20]`
- Added task coverage:
  - `spec/rhdl/cli/tasks/ao486_task_spec.rb`
  - `spec/rhdl/cli/ao486_spec.rb`
  - `spec/rhdl/cli/rakefile_interface_spec.rb` extended with `ao486:*` task assertions
- Validation:
  - `bundle exec rspec spec/rhdl/cli/tasks/ao486_task_spec.rb` -> `5 examples, 0 failures`
  - `bundle exec rake "spec[ao486]"` -> `5 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/rhdl/cli/rakefile_interface_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `76 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb` -> `58 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `77 examples, 0 failures`
  - `bundle exec rake ao486:parity` -> `1 example, 0 failures`
  - `bundle exec rake ao486:verify` -> `10 examples, 0 failures`
  - `bundle exec rake "ao486:import[tmp/ao486_task_out,tmp/ao486_task_ws]"` -> `success=true files=16`

## Execution Update (2026-03-04, alias task polish)
- Added explicit convenience aliases in `Rakefile`:
  - `spec:lib`, `spec:hdl`, `spec:ao486`, `spec:mos6502`, `spec:apple2`, `spec:riscv`
  - `pspec:lib`, `pspec:hdl`, `pspec:ao486`, `pspec:mos6502`, `pspec:apple2`, `pspec:riscv`
  - each alias delegates to the parameterized `spec[scope]` / `pspec[scope]` path.
- Expanded task interface coverage in `spec/rhdl/cli/rakefile_interface_spec.rb`:
  - validates alias task existence and delegation for `spec:ao486` and `pspec:ao486`.
- Validation:
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb` -> `72 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `91 examples, 0 failures`
  - `bundle exec rake ao486:verify` -> `10 examples, 0 failures`
  - `bundle exec rake spec` -> `4986 examples, 0 failures, 109 pending`

## Execution Update (2026-03-04, strategy hardening)
- Added explicit AO486 importer strategies:
  - `stubbed` (existing deterministic baseline, now explicit default)
  - `tree` (attempt include of module-bearing RTL files under `reference/rtl`)
- Added controlled fallback path:
  - when `tree` fails CIRCT import, importer retries with `stubbed` when fallback is enabled.
  - result metadata now reports `strategy_requested`, `strategy_used`, `fallback_used`, `attempted_strategies`, and `stub_modules`.
- Hardened `tree` attempt staging:
  - stages module-bearing RTL files under a workspace-local tree with deterministic ordering.
  - stages AO486 include-helper files (`defines.v`, `startup_default.v`, `autogen/*`) and runs tooling from the workspace.
  - normalizes missing ``timescale`` directives on staged `tree` sources to reduce parse skew.
- Added CLI/rake surface for strategy control:
  - `rhdl ao486 import --out <dir> --strategy stubbed|tree --[no-]fallback`
  - `rake "ao486:import[output_dir,workspace_dir,strategy,fallback]"`
- Added/updated coverage:
  - importer rejects unknown strategies
  - importer validates tree-attempt path and fallback behavior
  - CLI help/spec coverage includes strategy/fallback flags
  - parity spec updated for strategy-suffixed wrapper artifact names
- Validation:
  - `bundle exec rspec spec/rhdl/cli/tasks/ao486_task_spec.rb` -> `5 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/ao486_spec.rb` -> `4 examples, 0 failures`
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> `6 examples, 0 failures`
  - `bundle exec rspec spec/examples/ao486/import/parity_spec.rb` -> `1 example, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `93 examples, 0 failures`
  - `bundle exec rake ao486:verify` -> `12 examples, 0 failures`

## Execution Update (2026-03-04, tree-no-fallback green)
- Extended `tree` strategy with auto-stub retries driven by CIRCT parser diagnostics:
  - on Verilog import failure, importer extracts error file paths, maps to module definitions, and retries with those modules forced to blackbox stubs.
  - keeps strategy as `tree` (no fallback to `stubbed` required) unless explicitly configured.
- Added an explicit retry budget for tree auto-stubbing:
  - `TREE_MAX_AUTO_STUB_RETRIES = 16`.
- Hardened tree module closure:
  - forced-stub modules are pruned during tree closure traversal to avoid unnecessary parser-hostile descendants.
- Updated Moore->core lowering pipeline for AO486 tree output:
  - `--moore-lower-concatref --canonicalize --moore-lower-concatref --convert-moore-to-core --llhd-sig2reg --canonicalize`
  - fixes legalization failures from residual `moore.concat_ref`.
- Tightened importer coverage:
  - `spec/examples/ao486/import/system_importer_spec.rb` now requires `tree` + `--no-fallback` path to succeed.
- Validation:
  - `bundle exec ruby exe/rhdl ao486 import --strategy tree --no-fallback --workspace tmp/ao486_tree_ws --out tmp/ao486_tree_out --keep-workspace` -> `success=true`
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> `7 examples, 0 failures`
  - `bundle exec rake ao486:verify` -> `13 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/examples/ao486/import/parity_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `94 examples, 0 failures`

## Execution Update (2026-03-04, required output_dir cutover)
- Removed AO486 output-directory defaults from runtime/importer entrypoints:
  - `SystemImporter` now requires `output_dir:` keyword input.
  - `AO486Task` import action now raises when `output_dir` is missing.
- Enforced explicit output directory in interfaces:
  - CLI `rhdl ao486 import` now requires `--out DIR` and exits early if omitted.
  - rake `ao486:import` now requires first arg `output_dir` and aborts with usage guidance if omitted.
- Updated docs/examples to use explicit output dir on AO486 import commands.
- Updated tests:
  - importer spec now checks missing output_dir behavior.
  - CLI spec now checks `--out DIR` is present in help and required at runtime.
  - task spec now checks import action requires output_dir.
  - rake interface spec now invokes `ao486:import` with explicit output path.
- Validation:
  - `bundle exec rspec spec/rhdl/cli/tasks/ao486_task_spec.rb spec/rhdl/cli/ao486_spec.rb spec/examples/ao486/import/system_importer_spec.rb spec/rhdl/cli/rakefile_interface_spec.rb` -> `90 examples, 0 failures`
  - `bundle exec ruby exe/rhdl ao486 import` -> exits non-zero with `Missing required option: --out DIR`
  - `bundle exec ruby exe/rhdl ao486 import --out examples/ao486/hdl --strategy tree --no-fallback --workspace tmp/ao486_reqout_ws --keep-workspace` -> `success=true`
  - `bundle exec rake ao486:import` -> exits non-zero with required `output_dir` usage message
  - `bundle exec rake "ao486:import[tmp/ao486_reqout_rake,,tree,false]"` -> `success=true`

## Execution Update (2026-03-04, ao486 command relocation)
- Moved AO486 orchestration task class out of top-level CLI tasks:
  - from `lib/rhdl/cli/tasks/ao486_task.rb`
  - to `examples/ao486/utilities/tasks/ao486_task.rb`
  - namespace is now `RHDL::Examples::AO486::Tasks::AO486Task`
- Added dedicated AO486 example binary:
  - `examples/ao486/bin/ao486`
  - provides `import`, `parity`, and `verify` subcommands.
- Updated top-level CLI routing:
  - `rhdl examples ao486 ...` now delegates via `exec` to `examples/ao486/bin/ao486`, matching existing riscv/gameboy delegation pattern.
  - top-level `rhdl ao486 ...` is no longer exposed.
- Updated rake wiring:
  - `ao486:*` rake tasks now instantiate `RHDL::Examples::AO486::Tasks::AO486Task`.
- Updated docs/examples to use nested command path:
  - `rhdl examples ao486 ...`
- Validation:
  - `bundle exec rspec spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/rhdl/cli/rakefile_interface_spec.rb spec/examples/ao486/import/system_importer_spec.rb` -> `92 examples, 0 failures`
  - `bundle exec ruby exe/rhdl examples ao486 import --out tmp/ao486_bin_out --strategy tree --no-fallback --workspace tmp/ao486_bin_ws --keep-workspace` -> `success=true`
  - `bundle exec ruby exe/rhdl ao486 --help` -> exits non-zero as unknown top-level command

## Execution Update (2026-03-04, tree directory layout option)
- Added tree-import output layout option:
  - `maintain_directory_structure` (default: `true`).
  - when enabled and strategy is `tree`, raised DSL files are moved under output subdirectories mirroring source Verilog directory structure.
  - when disabled, tree output remains flat (legacy behavior).
- Surface wiring:
  - CLI: `rhdl examples ao486 import --[no-]maintain-directory-structure`
  - rake: `ao486:import[output_dir,workspace_dir,strategy,fallback,maintain_directory_structure]`
  - task/importer plumbing updated accordingly.
- Added coverage:
  - `spec/examples/ao486/import/system_importer_spec.rb`
    - default tree path now asserts mirrored file location (`ao486/pipeline/pipeline.rb`)
    - added explicit `maintain_directory_structure: false` flat-layout check.
  - CLI help spec asserts the new flag is documented.
- Validation:
  - `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb spec/rhdl/cli/rakefile_interface_spec.rb` -> `93 examples, 0 failures`
  - `bundle exec ruby exe/rhdl examples ao486 import --out tmp/ao486_layout_on --strategy tree --no-fallback ...` -> mirrored layout present, flat path absent
  - `bundle exec ruby exe/rhdl examples ao486 import --out tmp/ao486_layout_off --strategy tree --no-fallback --no-maintain-directory-structure ...` -> flat layout present, mirrored path absent
  - `bundle exec rake ao486:verify` -> `14 examples, 0 failures`
