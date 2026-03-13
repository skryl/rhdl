# Game Boy Import Per-Component Unit Suite PRD

## Status

Completed - 2026-03-06

## Context

The Game Boy mixed import flow already has:

- importer coverage through `SystemImporter`
- whole-design integration and roundtrip coverage
- runtime parity coverage on the imported design

What it does not have is per-component unit validation across the two critical imported outputs:

1. staged pure Verilog
2. raised RHDL

The current importer output also still has real quality issues that this suite should close rather than tolerate, including mangled raised file/class naming for modules such as `eReg_SavestateV__vhdl_*`.

## Goals

1. Add a unit suite under `spec/examples/gameboy/import/unit`.
2. Cover every imported Game Boy component reported by a fresh strict mixed import.
3. Phase 1 must validate staged Verilog is semantically close to the original source.
4. Phase 2 must validate the raised RHDL uses the highest available DSL surface.
5. Fix importer and raise issues exposed by the new suite as part of the same work.
6. Keep existing Game Boy import, roundtrip, and touched runtime parity coverage green.

## Non-Goals

1. Limiting coverage to only top-level source RTL files.
2. Accepting filename heuristics in specs when importer-owned provenance can be emitted instead.
3. Relaxing the suite to match current importer/raise bugs without fixing them.
4. Replacing existing roundtrip or runtime parity specs.

## Public Interface / API Additions

1. New unit spec tree:
   - `spec/examples/gameboy/import/unit/`
2. Import report/provenance additions as needed to drive one test per imported component:
   - module name
   - original source kind/path
   - staged Verilog path
   - raised Ruby path
   - VHDL synth provenance when applicable

## Phased Plan (Red/Green)

### Phase 1: Staged Verilog Is Semantically Close To The Original

#### Red

1. Add a shared import fixture that runs a fresh strict `SystemImporter` in a temp workspace and exposes the imported module inventory from `import_report.json`.
2. Add a failing staged-Verilog unit spec under `spec/examples/gameboy/import/unit` with one example per imported module.
3. Make the spec fail when any module:
   - lacks deterministic provenance,
   - has a mismatched staged-module name,
   - or has staged Verilog that is not semantically close to the original source.

#### Green

1. Extend importer/report provenance as needed so each imported module maps deterministically to:
   - its original source,
   - its staged Verilog module,
   - and its raised Ruby file.
2. For original Verilog/SystemVerilog modules:
   - compare original normalized source and staged Verilog by importing both to CIRCT IR and matching the target-module semantic signature.
3. For original VHDL modules:
   - re-synthesize the original entity with the recorded specialization args,
   - run the same postprocess path used by the importer,
   - compare the resulting module semantic signature to the staged generated Verilog module.
4. Assert exact module-name continuity across original source, staged Verilog, and imported module inventory.
5. Fix any importer-stage issues the suite exposes, including provenance gaps, bad renames, or incorrect staging rewrites.

#### Exit Criteria

1. Every imported Game Boy module has a green staged-Verilog example.
2. The suite no longer relies on filename guesses to locate staged modules.

### Phase 2: Raised RHDL Uses The Highest Available DSL

#### Red

1. Add a failing raised-RHDL unit spec under `spec/examples/gameboy/import/unit` with one example per imported module.
2. Make the spec fail when any raised module:
   - is missing or misnamed,
   - emits degrade diagnostics,
   - or drops below the highest available DSL for its shape.

#### Green

1. Raise the cleaned imported package once to in-memory sources/components and validate each imported module individually.
2. Require zero degrade diagnostics for:
   - `raise.behavior`
   - `raise.expr`
   - `raise.memory_read`
   - `raise.case`
   - `raise.sequential`
   - `raise.sequential_if`
3. Validate the highest available DSL surface by module shape:
   - clocked modules use `SequentialComponent`, `include RHDL::DSL::Sequential`, and `sequential clock:`
   - hierarchical modules use structural DSL such as `instance :` and `port`
   - combinational logic modules use `behavior do`
   - structure-only modules do not degrade into placeholder logic
4. Re-emit each raised component and compare its target-module semantic signature against the imported module signature.
5. Fix raise/import issues exposed by the suite, including naming mangling and under-raised output.

#### Exit Criteria

1. Every imported Game Boy module has a green raised-RHDL example.
2. Raised file basenames and class names are stable and human-readable.
3. The raised output uses the strongest DSL surface currently representable for each module.

## Acceptance Criteria

1. `spec/examples/gameboy/import/unit` exists and is green.
2. The suite covers every imported Game Boy component from a fresh strict import.
3. Phase 1 proves staged Verilog is semantically close to the original source for every component.
4. Phase 2 proves raised RHDL uses the highest available DSL and preserves component semantics.
5. Importer-owned provenance is sufficient to drive the suite without ad hoc filename heuristics.
6. Known naming bugs such as `_1__2eg...rb` are fixed rather than allowlisted.
7. Existing Game Boy import, roundtrip, and touched parity gates remain green.

## Execution Notes

1. Phase 1 landed as `spec/examples/gameboy/import/unit/staged_verilog_spec.rb` with a shared fresh-import fixture in `spec/examples/gameboy/import/unit/support.rb`.
2. Phase 1 compares each imported component inside its mixed-source dependency closure instead of as a standalone file.
3. For source-backed roots, the expected closure now applies the same mixed-import specialization rewrites as the real importer by reconstructing the rewrite plan from the importer manifest through `ImportTask` private helpers.
4. For large source-backed closures, already-validated generated-VHDL dependencies are reused from staged Verilog inside the expected closure to avoid redundant per-example GHDL re-synthesis while preserving per-component validation of generated modules.
5. Phase 2 landed as `spec/examples/gameboy/import/unit/raised_rhdl_spec.rb` and is green on the full imported module inventory.
6. The mangled-name bug was fixed in the raiser so mixed-case imported modules now emit stable readable file basenames and Ruby class names.
7. Shared supporting fixes already required by the suite are part of this work:
   - importer-owned per-module provenance in the mixed-import report
   - preserved VHDL synth provenance needed to replay generated modules
   - MLIR emitter recursion guard for self-referential assign graphs

## Validation Performed

1. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/gameboy/import/unit/staged_verilog_spec.rb --format documentation`
2. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/gameboy/import/unit/raised_rhdl_spec.rb --format documentation`
3. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/cli/tasks/import_task_spec.rb spec/rhdl/codegen/circt/mlir_spec.rb spec/examples/gameboy/import/system_importer_spec.rb --format documentation`
4. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/gameboy/import/integration_spec.rb spec/examples/gameboy/import/roundtrip_spec.rb --format documentation`

## Validation Not Re-Run

1. `spec/examples/gameboy/import/runtime_parity_3way_spec.rb` was not re-run in this final pass because the unit-suite change set did not touch the runtime parity harness or backend code paths.

## Risks And Mitigations

1. Risk: importer provenance is not rich enough to drive per-module checks.
   - Mitigation: extend the report once and reuse it in both phases.
2. Risk: VHDL-derived modules are expensive to validate one-by-one.
   - Mitigation: cache the fresh import fixture per suite and only re-synthesize the module currently under test when needed.
3. Risk: current raise naming bugs make per-module path assertions noisy.
   - Mitigation: fix naming at the raiser (`underscore` / `camelize`) before stabilizing the phase-2 expectations.
4. Risk: highest-available DSL checks become subjective.
   - Mitigation: tie expectations directly to imported module shape plus the existing strict-degrade diagnostic contract.

## Implementation Checklist

- [x] Phase 1 red: add shared fresh-import fixture and failing staged-Verilog per-component spec
- [x] Phase 1 green: emit deterministic per-module provenance from the importer/report
- [x] Phase 1 green: staged-Verilog semantic-closeness checks pass for every imported module
- [x] Phase 1 green: importer-stage mapping and naming issues are fixed
- [x] Phase 2 red: add failing raised-RHDL per-component spec
- [x] Phase 2 green: fix raise naming mangling and other raise-path regressions
- [x] Phase 2 green: highest-available DSL checks pass for every imported module
- [x] Phase 2 green: per-component raised-RHDL semantic checks pass
- [x] Regression: touched Game Boy import and roundtrip gates are green; runtime parity remains unchanged and was not re-run in this final pass
- [x] PRD status and checklist updated to match the final state
