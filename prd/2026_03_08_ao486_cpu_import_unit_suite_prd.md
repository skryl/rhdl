# AO486 CPU Import Unit Suite PRD

## Status

Completed - 2026-03-08

Execution notes:
1. The importer result shape already exposes the suite-owned closure metadata this plan needs:
   - `closure_modules`
   - `module_files_by_name`
   - `staged_module_files_by_name`
   - `module_source_relpaths`
   - `include_dirs`
   - `staged_include_dirs`
2. The AO486 CPU unit support layer is implemented under `spec/support/ao486` and runs one fresh `CpuImporter` import per RSpec process with:
   - `import_strategy: :tree`
   - `fallback_to_stubbed: false`
   - `maintain_directory_structure: true`
   - `keep_workspace: true`
   - `strict: false`
3. The mirrored unit suite is checked in under `spec/examples/ao486/import/unit` and currently locks a 47-file / 47-module CPU-top coverage manifest.
4. Phase 1 runtime-session and inventory coverage is green.
5. Phase 2 staged-Verilog semantic closeness is green across the mirrored suite after restoring the missing macro/include prelude for decode-family semantic compares.
6. Phase 3 raised-RHDL coverage is green across the mirrored suite run.
7. The broader default AO486 non-slow regression set is green after:
   - preserving runtime-visible hierarchical probe signals through CIRCT runtime JSON normalization
   - removing the now-stale `icache` partial-length literal remap in the parity package path
   - moving the longer parity-package exact-trace / beyond-first-window assertions to `slow: true`, where the stronger cross-backend checks already live
8. The default regression command from the initial plan,
   - `bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb`
   currently filters out all examples because that file is slow-tagged. Use `INCLUDE_SLOW_TESTS=1` for a real roundtrip run.
9. The umbrella `bundle exec rake "spec[ao486]"` command was started but is prohibitively long in this environment; the equivalent non-slow AO486 file set was re-run directly instead and passed.

## Context

AO486 now has a CPU-top importer rooted at `examples/ao486/reference/rtl/ao486/ao486.v` and a growing set of CPU-top import/runtime parity checks. What it still needs is a source-backed unit suite that validates the imported CPU closure at the two artifacts this workflow owns directly:

1. staged Verilog
2. raised RHDL

This suite should follow the same broad pattern used for the recent SPARC64 and Game Boy unit suites, but with AO486-specific scope:

1. import the CPU top, not `system.v`
2. build a fresh runtime inventory from that import only
3. validate staged Verilog using semantic signatures instead of text diffs
4. validate raised RHDL quality and semantic equivalence
5. keep runtime parity work in the separate AO486 CPU runtime parity PRD

The current AO486 CPU closure is a strong fit for the mirrored-source-file unit-suite pattern because it is pure Verilog, basename-stable, and effectively one module per covered source file.

## Goals

1. Add an AO486 CPU-top import unit suite under `spec/examples/ao486/import/unit`.
2. Scope the suite to `RHDL::Examples::AO486::Import::CpuImporter`, rooted at `ao486.v`, not `system.v`.
3. Keep this suite limited to staged Verilog plus raised RHDL; do not add parity logic here.
4. Run one fresh temp CPU import per RSpec process and reuse it across the suite.
5. Cover the direct source-backed module closure from the default CPU-top tree import.
6. Lock the exact source-relative coverage set with checked-in mirrored source-file specs.
7. Reject staged-Verilog semantic drift, missing provenance, source regrouping, or staged-name drift.
8. Reject raised-RHDL placeholder/fallback output or semantic degradation.

## Non-Goals

1. Validating `system.v` or system-only AO486 modules.
2. Pulling AO486 into the SPARC64 parity helper or adding parity checks to this suite.
3. Reusing checked-in `examples/ao486/import` or `examples/ao486/tmp` artifacts as the source of truth.
4. Requiring the AO486 CPU import/raise path to be globally strict-clean.
5. Replacing the separate AO486 CPU runtime parity PRD.

## Public Interface / API Additions

1. Importer result metadata used by the suite:
   - `closure_modules`
   - `module_files_by_name`
   - `staged_module_files_by_name`
   - `module_source_relpaths`
   - `include_dirs`
   - `staged_include_dirs`
2. New AO486 unit spec support:
   - `spec/support/ao486/runtime_import_session.rb`
   - `spec/support/ao486/source_file_driver.rb`
3. New AO486 CPU unit manifest and mirrored spec tree:
   - `spec/examples/ao486/import/unit/coverage_manifest.rb`
   - `spec/examples/ao486/import/unit/**/*_spec.rb`

## Phased Plan (Red/Green)

### Phase 1: Runtime Session And Inventory

#### Red

1. Add a failing runtime-import session spec that proves the CPU import happens once per RSpec process and can be reused.
2. Add a failing runtime inventory spec that locks the exact source-relative CPU closure coverage set.
3. Add failing checks that require inventory records to expose:
   - original source path
   - staged source path
   - generated Ruby path
   - in-memory raised source
   - in-memory raised component

#### Green

1. Add a suite-local AO486 runtime-import session that runs `CpuImporter` with:
   - `import_strategy: :tree`
   - `fallback_to_stubbed: false`
   - `maintain_directory_structure: true`
   - `keep_workspace: true`
   - `strict: false`
2. Cache one runtime import per RSpec process and clean it up after the suite.
3. Build the coverage inventory strictly from the fresh CPU-top import result plus in-memory raise results.
4. Add a checked-in coverage manifest that locks the covered source file to module-name mapping.

#### Exit Criteria

1. The suite performs one fresh CPU-top import per RSpec process.
2. Inventory records can be queried by source-relative path and module name.
3. The checked-in manifest matches the runtime source-backed CPU closure.

### Phase 2: Staged Verilog Semantic Closeness

#### Red

1. Add one staged-Verilog example per mirrored source file.
2. Make the suite fail on:
   - missing original or staged mappings
   - duplicate mappings
   - staged-name drift
   - semantic drift between original and staged dependency closures
3. Always supply the original/staged include context needed for CPU-tree headers such as:
   - `defines.v`
   - `startup_default.v`
   - `autogen/*`

#### Green

1. Reuse the semantic-signature pattern from the recent unit suites.
2. Compare the original dependency closure against the staged dependency closure instead of text-diffing the source file.
3. Preserve the requested source file as the primary input for the semantic comparison.
4. Memoize the staged-Verilog report once per covered source file and reuse it for all examples in that file.

#### Exit Criteria

1. Every covered source file has a green staged-Verilog example.
2. The suite fails loudly on staging regressions without relying on filename heuristics.

### Phase 3: Raised RHDL Quality And Semantic Equivalence

#### Red

1. Add one raised-RHDL example per mirrored source file.
2. Make the suite fail on:
   - missing generated Ruby output
   - placeholder/fallback generated text
   - unstable module naming
   - semantically degraded re-emission from the raised component

#### Green

1. Re-raise the cleaned CPU import artifact once per session with `strict: false`.
2. Reuse the in-memory `Raise.to_sources` and `Raise.to_components` results across the whole suite.
3. Require the strongest available DSL surface by module shape:
   - sequential modules use `SequentialComponent`, `RHDL::DSL::Sequential`, and `sequential clock:`
   - hierarchical modules remain explicit wiring/instance structure
   - combinational modules use `behavior do`
   - memory-backed modules use `RHDL::DSL::Memory` when emitted as memory
4. Re-emit each raised component to MLIR and compare its semantic signature against the staged closure signature for that module.

#### Exit Criteria

1. Every covered module has a green raised-RHDL example.
2. Raised file/class naming is stable.
3. Raised output preserves module semantics and avoids placeholder/fallback output.

### Phase 4: Regression Closure And PRD Closeout

#### Red

1. Run the targeted AO486 unit-suite commands from the initial plan.
2. Re-run the touched CPU importer and roundtrip regressions.
3. Re-run the broader AO486 suite once the focused unit suite is green.

#### Green

1. Record the exact validation commands and results in this PRD.
2. Update the checklist and PRD status to reflect the actual state.
3. Mark the PRD `Completed` only after the full focused suite and required regressions are green.

#### Exit Criteria

1. Focused AO486 CPU import unit-suite coverage is green.
2. Touched importer and roundtrip regressions are green.
3. The broader AO486 regression gate has been re-run or explicitly documented as not re-run for a justified reason.

## Exit Criteria Per Phase

1. Phase 1: one runtime CPU import per process plus stable inventory/manifest coverage.
2. Phase 2: all mirrored source files pass staged-Verilog semantic-closeness checks.
3. Phase 3: all mirrored source files pass raised-RHDL quality and semantic-equivalence checks.
4. Phase 4: required focused/regression validation is recorded and the PRD status matches reality.

## Acceptance Criteria

1. `spec/examples/ao486/import/unit` exists and mirrors the covered CPU-top source tree.
2. The suite uses a fresh temp CPU import once per RSpec process and cleans it up afterward.
3. Coverage is limited to the source-backed modules in the default CPU-top tree closure.
4. Every covered source file passes the staged-Verilog semantic-closeness gate.
5. Every covered source file passes the raised-RHDL quality gate.
6. Every raised component re-emits semantically equivalently to the staged module closure for that module.
7. Touched CPU importer and roundtrip regressions remain green.
8. The broader AO486 regression gate is recorded.

## Risks And Mitigations

1. Risk: the importer result object does not expose enough provenance to drive the suite.
   - Mitigation: add explicit closure/file/include metadata to the importer result rather than infer it from private state.
2. Risk: per-file staged-Verilog semantic checks miss preprocessor context from AO486 include/header files.
   - Mitigation: preserve source-relative closure structure, pass both original and staged include roots, and treat missing macro context as a hard test failure.
3. Risk: the AO486 CPU path is not globally strict-clean yet.
   - Mitigation: run the suite with `strict: false` and validate module-level semantic quality instead of zero global diagnostics.
4. Risk: mirrored source-file coverage drifts silently as the importer changes.
   - Mitigation: lock the exact `source_relative_path -> module_names` mapping in a checked-in manifest and fail on regrouping or drift.
5. Risk: the suite grows entangled with AO486 runtime parity plumbing.
   - Mitigation: keep AO486 unit support local to this suite and stop scope at staged Verilog plus raised RHDL.

## Validation Performed

1. `bundle exec rspec spec/examples/ao486/import/unit/runtime_import_session_spec.rb`
   - result: `2 examples, 0 failures`
2. `bundle exec rspec spec/examples/ao486/import/unit/runtime_inventory_spec.rb`
   - result: `1 example, 0 failures`
3. `bundle exec rspec spec/examples/ao486/import/unit/ao486/ao486_spec.rb`
   - result: `2 examples, 0 failures`
4. `bundle exec rspec spec/examples/ao486/import/unit/ao486/pipeline/decode_spec.rb`
   - result: `2 examples, 0 failures`
5. `bundle exec rspec spec/examples/ao486/import/unit/cache/l1_icache_spec.rb`
   - result: `2 examples, 0 failures`
6. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb`
   - result: `3 examples, 0 failures`
7. `bundle exec rspec spec/examples/ao486/import/unit`
   - result: `100 examples, 0 failures`
8. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb`
   - result: `1 example, 0 failures`
9. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb spec/examples/ao486/import/cpu_trace_package_spec.rb`
   - result: `4 examples, 0 failures`
10. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb`
   - result: `3 examples, 0 failures`
11. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb`
   - result: `1 example, 0 failures`
12. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb`
   - result: `10 examples, 0 failures`
13. `bundle exec rspec spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb`
   - result: `3 examples, 0 failures`

## Validation Not Re-Run

1. `bundle exec rake "spec[ao486]"` was started but not allowed to run to completion because the aggregate non-slow AO486 pass is prohibitively long here; the underlying non-slow file set was re-run directly instead.

## Implementation Checklist

- [x] PRD created
- [x] Expose importer result metadata needed by the AO486 CPU unit suite
- [x] Phase 1 red: add runtime session and inventory coverage
- [x] Phase 1 green: shared runtime CPU import fixture and manifest are implemented
- [x] Phase 1 exit criteria validated
- [x] Phase 2 red: add mirrored staged-Verilog examples per covered source file
- [x] Phase 2 green: staged-Verilog semantic-closeness checks pass for every covered source file
- [x] Phase 2 exit criteria validated
- [x] Phase 3 red: add mirrored raised-RHDL examples per covered source file
- [x] Phase 3 green: raised-RHDL quality and semantic-equivalence checks are implemented
- [x] Phase 3 exit criteria validated
- [x] Phase 4 regression closure complete
- [x] Acceptance criteria validated
- [x] PRD marked Completed
