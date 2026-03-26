## Status
Completed (2026-03-04)

## Context
RHDL import currently supports:
1. Verilog/SystemVerilog input via `circt-translate --import-verilog`.
2. CIRCT MLIR input via direct CIRCT import+raise.

It does not support mixed-language projects containing both Verilog and VHDL. In this repo/toolchain, `circt-translate` does not expose direct VHDL import, so mixed import must convert VHDL to Verilog first.

Locked decisions for this PRD:
1. RHDL only handles `RHDL <-> CIRCT` transformations; Verilog/VHDL frontend and Verilog emission remain external tooling.
2. Mixed-language import uses GHDL synth conversion (`ghdl`) for VHDL in this phase.
3. Scope is generic CLI import path (`rhdl import`), not AO486-specific importer.
4. Failure mode is fail-fast (no conversion-stage fallback/rescue continuation).
5. Add new CLI mode `--mode mixed`.
6. Input UX supports manifest-first with autoscan fallback when manifest is omitted.
7. When manifest is omitted, mixed mode requires `--input` to be a top source file path.
8. Mixed import reports must include full conversion provenance.
9. Dependency checks include GHDL capability checks.

## Goals
1. Add mixed-language import mode (`verilog + vhdl`) to `rhdl import`.
2. Support YAML/JSON manifests with extended schema (files/top/include/defines/vhdl settings).
3. Support autoscan fallback from top-file input when manifest is absent.
4. Convert VHDL to staged Verilog with GHDL synth and feed existing Verilog->CIRCT flow.
5. Preserve existing CIRCT->RHDL raise flow and strict diagnostics behavior.
6. Emit detailed import report provenance for mixed conversion stages.
7. Add comprehensive specs for config resolution, orchestration, and integration behaviors.

## Non-Goals
1. Adding Yosys or alternate VHDL conversion backend in this phase.
2. Full project import upgrades for AO486 custom task in this phase.
3. Native VHDL parsing/elaboration in RHDL.
4. Best-effort continuation after VHDL conversion failures.

## Public Interface / API Changes
1. `rhdl import --mode mixed`.
2. `rhdl import --manifest <file.{yml,yaml,json}>` (mixed mode).
3. Existing options continue to apply (`--out`, `--top`, `--strict`, `--extern`, `--report`, `--[no-]raise`, `--tool`, `--tool-arg`).
4. Manifest omitted contract:
   - `--input` is required and must be a file path (top source file).
   - Autoscan root is `dirname(--input)`.

Manifest schema (v1):
```yaml
version: 1
top:
  name: system_top
  language: verilog # verilog|vhdl
  file: rtl/system_top.sv
  library: work # optional, vhdl only
files:
  - path: rtl/system_top.sv
    language: verilog
  - path: rtl/ip/math_pkg.vhd
    language: vhdl
    library: work
include_dirs:
  - rtl/include
defines:
  WIDTH: "32"
vhdl:
  standard: "08" # default: "08"
  workdir: tmp/ghdl_work # default: <out>/.mixed_import/ghdl_work
```

## Phased Plan (Red/Green)

### Phase 1: CLI + Task Surface
Red:
1. Add failing specs for `ImportTask` mixed mode acceptance/rejection contract.
2. Add failing checks for manifest option plumbing and autoscan fallback validation.

Green:
1. Extend CLI parser to accept `--mode mixed` and `--manifest`.
2. Add `ImportTask#import_mixed` entrypoint with strict option validation.

Refactor:
1. Keep mode dispatch and validation helpers isolated from conversion internals.

Exit Criteria:
1. Mixed mode reaches a dedicated code path.
2. Invalid mixed option combinations fail with actionable errors.

### Phase 2: Config Resolution (Manifest + Autoscan)
Red:
1. Add failing specs for YAML/JSON manifest parse + schema validation.
2. Add failing specs for autoscan classification and top-language resolution from top file.

Green:
1. Implement normalized mixed import config resolver.
2. Resolve file set/language partition deterministically.

Refactor:
1. Encapsulate resolver structures to simplify orchestrator inputs.

Exit Criteria:
1. Mixed mode obtains a validated config object from either manifest or autoscan.

### Phase 3: VHDL Conversion Orchestrator
Red:
1. Add failing specs for GHDL analyze/synth command construction and fail-fast propagation.
2. Add failing specs for staged Verilog assembly.

Green:
1. Implement GHDL analyze + synth flow for VHDL files/entities.
2. Write staged Verilog entrypoint combining native Verilog and generated Verilog.

Refactor:
1. Move command helpers into reusable tooling functions.

Exit Criteria:
1. Mixed config produces deterministic staged Verilog or fails with explicit diagnostics.

### Phase 4: Mixed -> CIRCT -> RHDL Integration + Report
Red:
1. Add failing integration specs for mixed import success/failure in both manifest/autoscan modes.
2. Add failing report schema specs for provenance fields.

Green:
1. Feed staged Verilog into existing Verilog->CIRCT path.
2. Reuse existing CIRCT->RHDL raise flow.
3. Extend report JSON with `mixed_import` provenance section.

Refactor:
1. Keep report serialization centralized.

Exit Criteria:
1. Mixed mode completes end-to-end with provenance report and strict failure semantics.

### Phase 5: Dependency Checks + Docs + Regression
Red:
1. Add failing dependency task specs for `ghdl` visibility/capability reporting.
2. Add failing docs/help text expectations where currently covered.

Green:
1. Extend `deps` checks with GHDL requirement for mixed path.
2. Update CLI help/docs for mixed mode usage.
3. Run targeted and broader import regression suites.

Refactor:
1. Consolidate dependency health-check helper tables.

Exit Criteria:
1. Mixed-mode dependency checks and documentation are aligned with implementation.

## Exit Criteria Per Phase
1. Phase 1: mixed mode parser/task contract implemented and tested.
2. Phase 2: deterministic validated config resolver for manifest/autoscan.
3. Phase 3: VHDL conversion/staging implemented with fail-fast diagnostics.
4. Phase 4: end-to-end mixed import works with provenance reporting.
5. Phase 5: deps/docs/regressions updated and green.

## Acceptance Criteria (Full Completion)
1. `rhdl import --mode mixed` supports mixed Verilog/VHDL import via manifest and autoscan modes.
2. VHDL conversion uses GHDL synth-to-Verilog and integrates with existing CIRCT import flow.
3. Report includes complete mixed conversion provenance (commands, staged files, mapping).
4. Import remains fail-fast under strict mode with actionable diagnostics.
5. Existing `--mode verilog` and `--mode circt` paths remain green.

## Risks and Mitigations
1. Risk: GHDL version/capability mismatch for synth flow.
   - Mitigation: explicit dependency capability checks and early failure messaging.
2. Risk: Ambiguity in autoscan top resolution.
   - Mitigation: require top file path in autoscan mode; infer language by extension.
3. Risk: VHDL package/library ordering issues.
   - Mitigation: manifest ordering is authoritative; autoscan ordering is deterministic and reported.
4. Risk: Regression in existing import paths.
   - Mitigation: preserve existing flow and add mode-specific tests.

## Implementation Checklist
- [x] Phase 1 red tests added.
- [x] Phase 1 green implementation complete.
- [x] Phase 2 red tests added.
- [x] Phase 2 green implementation complete.
- [x] Phase 3 red tests added.
- [x] Phase 3 green implementation complete.
- [x] Phase 4 red tests added.
- [x] Phase 4 green implementation complete.
- [x] Phase 5 red tests added.
- [x] Phase 5 green implementation complete.
- [x] Acceptance criteria validated.

## Execution Notes (2026-03-04)
Completed:
1. Added `--mode mixed` and `--manifest` to `rhdl import` CLI surface.
2. Added mixed mode dispatch and validation to `ImportTask`.
3. Implemented mixed config resolution from manifest (YAML/JSON) and autoscan (top file input).
4. Implemented VHDL staging orchestration:
   - GHDL analysis (`ghdl -a`) per VHDL file.
   - GHDL synth-to-Verilog (`ghdl --synth --out=verilog`) for VHDL targets.
   - Staged Verilog include entry file generation.
5. Wired staged mixed input into existing Verilog->CIRCT path.
6. Added report support for `mixed_import` provenance when raise flow is enabled.
7. Extended CIRCT tooling with GHDL command helpers.
8. Added targeted specs:
   - `spec/rhdl/cli/tasks/import_task_spec.rb` mixed mode contract tests.
   - `spec/rhdl/cli/tasks/import_task_spec.rb` mixed raise/report provenance test.
   - `spec/rhdl/cli/tasks/import_task_mixed_spec.rb` resolver/staging tests.
   - `spec/rhdl/cli/tasks/deps_task_spec.rb` ghdl dependency visibility checks.
9. Extended dependency status/install output with `ghdl` visibility.

Completed follow-up:
1. Added mixed-mode end-to-end task integration tests for autoscan + raise/report path.
2. Added mixed-mode fail-fast task test for synth failure propagation during full run.
3. Added CIRCT tooling tests for `ghdl_analyze` and `ghdl_synth_to_verilog`.
4. Added CLI help coverage for `rhdl import --help` mixed option surface.
5. Updated docs (`README.md`, `docs/cli.md`) with mixed import usage and manifest schema.
6. Extended deps checks with `ghdl-synth` capability probe and coverage.
7. Ran broader import path regression (`spec/rhdl/import/import_paths_spec.rb`).

Validation commands:
1. `bundle exec rspec spec/rhdl/cli/import_spec.rb spec/rhdl/cli/tasks/import_task_spec.rb spec/rhdl/cli/tasks/import_task_mixed_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb spec/rhdl/cli/tasks/deps_task_spec.rb spec/rhdl/import/import_paths_spec.rb` (76 examples, 0 failures).
