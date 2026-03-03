# Verilog Import Higher-Level DSL Recovery PRD

## Status
In Progress (2026-03-01, expanded for hint-driven DSL uplift)

## Context
The Verilog/SystemVerilog importer currently lowers or drops several higher-level procedural constructs before translation, which leads to generated RHDL that is less readable and less structurally faithful to source RTL. In particular:
- `CASE` nodes are lowered to nested `if` chains in the frontend normalizer.
- procedural loop forms are not preserved through mapping/emission.
- translator process emission currently handles assignment + `if` only.
- IR lowering for generated DSL statements only handles assignments and `IfStatement`.

The goal is to preserve and emit higher-level DSL forms in importer-generated components while keeping behavioral parity gates (`source Verilog` vs `generated Verilog` vs `generated IR`) intact.

Current gap after phases 1-7:
- Hint plumbing/reporting exists, but hints are not yet materially applied to raise generated RHDL structure.
- Surelog adapter currently provides availability/fallback integration; the next tranche focuses on semantic hint extraction + consumption to maximize high-level DSL recovery.

## Goals
1. Preserve recoverable control-flow constructs through normalize -> map -> translate:
   - `case_stmt` / `when_value` / `default`
   - `for_loop` (static ranges)
   - `elsif_block` where canonical
2. Keep generated RHDL human-readable (operator-style DSL, structured blocks).
3. Extend lowering path so generated IR simulation supports newly emitted statement forms.
4. Keep no-custom-export policy intact (no custom `self.to_verilog` in generated modules).
5. Keep importer parity checks green.
6. Apply parser/elaboration hints to maximize high-level DSL recovery before fallback lowering.
7. Establish objective uplift metrics that track how much generated output remains in high-level DSL form.

## Non-Goals
1. Automatic state-machine synthesis from arbitrary RTL.
2. Full vec/bundle/state_machine recovery in this tranche.
3. Manual post-editing of generated component files.
4. Relaxing parity requirements to improve readability.

## Public Interfaces and Output Contract
Implemented interface additions:
1. CLI/import options:
   - `--recovery-mode off|recoverable|strict` (default: `recoverable`)
   - `--hint-backend off|surelog` (default: `surelog`)
   - `--hint-min-confidence high|medium|low` (default: `medium`)
   - `--hint-conflict-policy prefer_ast|prefer_hint|strict` (default: `prefer_ast`)
2. Import report additions:
   - `recovery.summary` (`preserved_count`, `lowered_count`, `nonrecoverable_count`, `hint_applied_count`)
   - `recovery.events[]` (module/construct-level preservation/lowering events)
   - `hints` backend availability and diagnostics
3. Parser policy:
   - Surelog unavailable path warns and continues (non-fatal).

Planned interface additions for hint-driven uplift tranche:
1. Canonical hint payload (`normalized_payload[:hints]`) with deterministic schema:
   - `module`
   - `construct_family` (`process`, `expression`, `declaration`, `instance`)
   - `construct_kind` (for example `case_unique`, `fsm_state_reg`, `enum_decl`, `static_loop`, `always_ff`)
   - `confidence` (`high`, `medium`, `low`)
   - `span`
   - `data` (shape-specific normalized fields)
2. Import report enrichment:
   - `hints.summary` (`extracted_count`, `applied_count`, `discarded_count`, `conflict_count`)
   - `recovery.summary.dsl_uplift_score` (deterministic scalar derived from preserved-vs-lowered structure)
   - `recovery.events[].origin` (`ast`, `hint`, `fallback`)
3. CLI knobs:
   - `--hint-min-confidence high|medium|low` (default: `medium`)
   - `--hint-conflict-policy prefer_ast|prefer_hint|strict` (default: `prefer_ast`)

## Phased Plan (Red/Green/Refactor)

### Phase 1: Baseline Failures + PRD Lock
Red:
1. Add failing specs demonstrating current loss/lowering:
   - frontend `CASE` lowered to nested `if`
   - loop statements not preserved
   - mapper/emitter/lower missing `case`/`for` handling

Green:
1. PRD created and execution started.

Refactor:
1. Keep new tests scoped to importer/codegen paths touched in this tranche.

Exit criteria:
1. Baseline failures are deterministic and reproducible.

### Phase 2: Frontend Preservation (`CASE` and loop forms)
Red:
1. Failing normalizer specs that require:
   - `CASE` remains a `kind: "case"` statement with items/default.
   - loop node maps to `kind: "for"` with `var` and static range.

Green:
1. Implement normalization to preserve `case` instead of rewriting to nested `if`.
2. Implement loop normalization for recoverable static loops.
3. Emit explicit unsupported diagnostics where loops are not recoverable.

Refactor:
1. Keep case/loop helpers isolated in normalizer.

Exit criteria:
1. Normalizer outputs structured `case`/`for` nodes for supported input forms.

### Phase 3: Import IR + Mapper Support
Red:
1. Failing mapper/IR specs for `case` and `for` statement mapping.

Green:
1. Add `IR::CaseStatement`, `IR::CaseItem`, `IR::ForLoop`.
2. Extend statement mapper for `kind: "case"` and `kind: "for"`.

Refactor:
1. Keep mapper diagnostics uniform using shared helper methods.

Exit criteria:
1. Mapped program serializes with case/for statement nodes.

### Phase 4: Translator Emission of Higher-Level DSL Statements
Red:
1. Failing emitter specs requiring process output with:
   - `case_stmt(...) do`
   - `when_value(...)`
   - `default do`
   - `for_loop(:i, start..stop) do`

Green:
1. Extend process statement emission for mapped case/for nodes.
2. Preserve consistent spacing and readable layout through prettyfier.

Refactor:
1. Extract helper methods for case/for statement emission to keep emitter maintainable.

Exit criteria:
1. Generated component source contains high-level control-flow DSL blocks.

### Phase 5: Lower New DSL Statements to Existing IR Backend
Red:
1. Failing lowering specs for DSL `CaseStatement` and `ForLoop`.

Green:
1. Lower `CaseStatement` to nested `IR::If` chains preserving branch order/default.
2. Lower static `ForLoop` by deterministic unrolling.

Refactor:
1. Extract reusable lowering helpers for case/loop.

Exit criteria:
1. IR lowering supports generated statement constructs with deterministic behavior.

Phase 5 result (2026-03-01):
1. Complete for this tranche:
   - `RHDL::Codegen::IR::Lower` now handles `RHDL::DSL::CaseStatement` and `RHDL::DSL::ForLoop`.
   - statement-level `case_stmt` is lowered to nested `IR::If` chains.
   - static `for_loop` ranges are deterministically unrolled during lowering.
   - loop variable references are bound to iteration literals during lowering.

### Phase 6: Recovery Reporting + Strict Mode (follow-up tranche)
Red:
1. Failing report/pipeline specs for recovery metrics and strict-mode failure.

Green:
1. Implement recovery report sections and strict mode behavior.

Refactor:
1. Consolidate severity handling for recoverable/nonrecoverable constructs.

Exit criteria:
1. Report contains deterministic recovery accounting and strict mode semantics.

### Phase 7: Surelog Auto-Hints Integration (follow-up tranche)
Red:
1. Failing adapter specs for Surelog path and unavailable-tool fallback behavior.

Green:
1. Add Surelog/UHDM adapter and hint merge path.
2. Warn-and-continue when backend unavailable.

Refactor:
1. Keep hint ingestion separate from Verilator normalization core.

Exit criteria:
1. Auto-hint path is integrated and non-fatal when unavailable.

### Phase 8: Canonical Hint Extraction and Deterministic Normalization (new tranche)
Red:
1. Failing frontend hint-adapter specs requiring deterministic normalized hint records from Surelog/UHDM fixtures.
2. Failing importer project specs asserting hint counts and conflict counters in reports.

Green:
1. Implement normalized hint schema extraction (construct family/kind/confidence/span/data).
2. Deduplicate and deterministically sort hints by module/span/kind.
3. Persist extraction stats in `hints.summary`.

Refactor:
1. Isolate backend-specific parsing from normalized hint model.

Exit criteria:
1. Same hint input produces byte-stable normalized hint payloads and report counters.

### Phase 9: Hint-Aware Frontend Enrichment (AST + Hint Fusion)
Red:
1. Failing normalizer specs where AST alone cannot recover high-level forms, but hint fusion must recover them.
2. Failing conflict-policy specs for `prefer_ast`, `prefer_hint`, and `strict`.

Green:
1. Merge hints into normalized module/process/statement nodes before mapper stage.
2. Recover additional high-level structures from hints:
   - `unique/priority case`
   - canonical `if/elsif` chains
   - loop classes (`for`, `repeat`, `while`) when static/recoverable
   - process intent (`always_ff`, `always_comb`, `always_latch`) where safely inferable
3. Emit deterministic conflict diagnostics with origin tagging.

Refactor:
1. Consolidate AST/hint conflict resolution into a single merge policy module.

Exit criteria:
1. Normalizer emits enriched high-level nodes with origin metadata and deterministic conflict behavior.

### Phase 10: Hint-Aware Mapper/Import IR Uplift
Red:
1. Failing mapper/IR specs for new enriched construct families.
2. Failing unsupported-construct diagnostics specs requiring hint-origin and confidence annotations.

Green:
1. Extend import IR to represent enriched constructs used by translator:
   - process intent tags
   - case qualifiers
   - enriched loop metadata
   - resolved elsif chains
2. Preserve source/hint provenance on IR nodes.

Refactor:
1. Keep IR extensions minimal and serialization-stable.

Exit criteria:
1. Import IR round-trip remains deterministic and includes provenance for hint-applied nodes.

### Phase 11: Translator High-Level DSL Emission Maximization
Red:
1. Failing emitter specs requiring enriched DSL output when hints are available.
2. Failing readability fixtures requiring stable formatting and original-name alignment.

Green:
1. Emit highest-level available DSL forms, preferring:
   - `case_stmt` with qualifiers where represented
   - `if/elsif/else` over nested ternary/if fallback trees
   - explicit loop DSL forms when recoverable
   - domain-specific process forms for sequential/combinational intent
2. Keep fallback paths deterministic when hints are absent or low-confidence.

Refactor:
1. Extract emitter helpers by construct family to avoid deeply nested generation logic.

Exit criteria:
1. Generated components show measurable reduction in fallback AST-style constructs.

### Phase 12: DSL Surface and Lowering Coverage for Newly Emitted Forms
Red:
1. Failing DSL/lowering specs for any newly emitted high-level statements or expression qualifiers.
2. Failing export/sim equivalence specs for new forms.

Green:
1. Add missing DSL nodes/helpers required by importer output.
2. Extend lowering + Verilog export support without custom per-component exporters.
3. Ensure IR simulator handles all emitted high-level forms via lowering.

Refactor:
1. Keep lower/export behavior canonical and shared across importer and hand-written DSL.

Exit criteria:
1. Every importer-emitted high-level form is supported through lowering/export/simulation.

### Phase 13: Behavioral Parity Gates for Hint-Applied Output
Red:
1. Failing parity specs showing divergence between source vs generated Verilog vs generated IR for hint-applied modules.
2. Failing program-level parity harness checks for multi-cycle traces and memory side effects.

Green:
1. Extend component and program parity harnesses to explicitly cover hint-applied modules.
2. Require 3-way parity pass for promoted constructs before phase closure.

Refactor:
1. Consolidate parity fixtures to minimize duplication while preserving coverage.

Exit criteria:
1. Hint-applied output is behaviorally equivalent across all three simulation paths.

### Phase 14: Uplift Scoring, Regression Thresholds, and Strict Acceptance
Red:
1. Failing report/integration specs requiring uplift score and minimum thresholds.
2. Failing strict-mode specs when uplift conflicts/nonrecoverables exceed policy.

Green:
1. Implement deterministic uplift metrics:
   - preserved high-level constructs
   - lowered fallback constructs
   - hint extraction/applied/discarded/conflict counts
2. Enforce policy gates for CI/import runs (warning vs failure based on thresholds).

Refactor:
1. Keep scoring model transparent and reproducible from report artifacts.

Exit criteria:
1. Import report quantifies uplift quality and can gate regressions automatically.

## Phase Results (2026-03-01)
1. Phase 1 complete:
   - Added failing red tests for preserved `case`, recoverable static `for`, mapper IR classes, emitter case/for output, and lower case/for behavior.
   - Baseline captured with 7 deterministic failures before implementation.
2. Phase 2 complete:
   - Frontend normalizer now preserves `CASE` as structured `kind: "case"` nodes.
   - Added recoverable static loop normalization (`ASSIGN` init + `LOOPTEST` + update `ASSIGN` -> `kind: "for"`).
3. Phase 3 complete:
   - Added import IR statement nodes: `CaseStatement`, `CaseItem`, `ForLoop`.
   - Statement mapper now maps `case` and `for` into import IR.
4. Phase 4 complete:
   - Module emitter now emits process-level `case_stmt/when_value/default` and `for_loop`.
   - DSL context helpers were expanded to support these emitted constructs (`CaseContext`, `BlockCollector`, `IfContext`).
5. Phase 5 complete:
   - Lowering now supports statement-level case and static for unrolling.
6. Phase 6 complete:
   - Added import recovery reporting with deterministic `recovery.summary` and `recovery.events`.
   - Added strict recovery mode gate (`recovery_mode=strict`) that fails import when lowered/nonrecoverable constructs are present.
   - Threaded recovery payload through `RHDL::Import.project -> Pipeline -> Report`.
7. Phase 7 complete:
   - Added `Frontend::SurelogHintAdapter` with deterministic availability probing.
   - Added hint backend wiring (`hint_backend=off|surelog`) with warn-and-continue fallback when Surelog is unavailable.
   - Added top-level `hints` report section and CLI option plumbing for `--hint-backend`.
8. Phase 8 complete:
   - Surelog adapter now emits deterministic canonical hint records (`module`, `construct_family`, `construct_kind`, `confidence`, `span`, `data`) with invalid-entry discard diagnostics.
   - Added deterministic hint summary counters (`extracted_count`, `applied_count`, `discarded_count`, `conflict_count`) through adapter -> import runtime -> report.
   - Report skeleton helpers/fixtures updated to require `hints.summary` schema.
9. Phase 9 in progress (partial implementation complete):
   - Implemented hint min-confidence filtering and conflict-policy handling (`prefer_ast`, `prefer_hint`, `strict`) in import hint fusion.
   - Implemented payload enrichment from hints for:
     - statement promotion `if -> case` via `case_from_if` hints (`prefer_hint` path),
     - case qualifiers (`case_unique`, `case_priority`) on case statements,
     - process intent tagging from process hints.
   - Added deterministic conflict diagnostics (`hint_conflict`) and below-threshold diagnostics (`hint_below_min_confidence`).
   - Added real Surelog extraction path in `Frontend::SurelogHintAdapter`:
     - when explicit `surelog_hints` / `surelog_hints_path` are absent, adapter now runs Surelog parse and consumes UHDM dump output (`uhdm-dump`) to extract canonical hints.
     - extracted hints include process intent (`always_*`) and case qualifier (`case_unique`/`case_priority`) records with module/span metadata.
     - existing explicit hint inputs still take precedence and skip auto-extraction.
10. Phase 10 in progress (metadata uplift tranche):
   - Added import IR metadata fields for hint-enriched nodes:
     - `IR::Process`: `intent`, `origin`, `provenance`.
     - `IR::CaseStatement`: `qualifier`, `origin`, `provenance`.
   - Extended mapper preservation from normalized payload to import IR:
     - process-level `intent`/`origin`/`provenance`,
     - case-level `qualifier`/`origin`/`provenance`.
   - Extended hint fusion to attach deterministic provenance payloads on hint-applied nodes:
     - `source`, `construct_family`, `construct_kind`, `confidence`, `span`.
   - Added red/green coverage for mapper/IR/project provenance preservation and case qualifier propagation.
   - Added hint metadata forwarding on mapper unsupported diagnostics when source nodes carry hint origin/provenance.
11. Phase 11 in progress (readability uplift started):
   - Added red/green translator emission support for flattening nested `if` chains into `if_stmt + elsif_block + else_block` output.
   - Preserves fallback behavior when chain flattening is not possible.
   - Added red/green translator + DSL support for case qualifiers:
     - importer-emitted `case_stmt(..., qualifier: :unique|:priority)` when metadata is present,
     - DSL contexts accept `case_stmt(..., qualifier:)`,
     - `RHDL::DSL::CaseStatement#to_verilog` emits `unique case` / `priority case`.
   - Added red/green process intent uplift in translator emission:
     - `intent: always_ff` now promotes clocked process inference when edge sensitivity is missing,
     - auto process naming now reflects promoted sequential intent (`process :sequential...`).
   - Added red/green process naming uplift for `always_comb` intent when domain/kind do not already imply combinational.

## Validation Sweep (2026-03-01)
1. Targeted red/green set:
   - `bundle exec rspec spec/rhdl/import/frontend/normalizer_spec.rb spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/translator/module_emitter_spec.rb spec/rhdl/codegen/ir/lower_process_spec.rb`
   - red baseline: `57 examples, 7 failures`
   - green verification: `57 examples, 0 failures`
2. Broader regression:
   - `bundle exec rspec spec/rhdl/import spec/rhdl/codegen/ir/lower_process_spec.rb`
   - `203 examples, 0 failures`
3. Phase 6/7 targeted recovery + hint validation:
   - `bundle exec rspec spec/rhdl/import/report_spec.rb spec/rhdl/import/project_spec.rb spec/rhdl/import/pipeline_spec.rb spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb spec/rhdl/cli/import_spec.rb`
   - red baseline: adapter missing / schema expectations failing
   - green verification: `52 examples, 0 failures`
4. Phase 6/7 broader importer regression:
   - `bundle exec rspec spec/rhdl/import spec/rhdl/cli/import_spec.rb`
   - `199 examples, 0 failures`
5. Phase 8 targeted canonical hint extraction + summary accounting:
   - `bundle exec rspec spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb spec/rhdl/import/report_assertions_spec.rb spec/rhdl/import/report_spec.rb spec/rhdl/import/project_spec.rb`
   - red baseline: `20 examples, 4 failures`
   - green verification: `24 examples, 0 failures`
6. Phase 8 broader importer regression:
   - `bundle exec rspec spec/rhdl/import spec/rhdl/cli/import_spec.rb`
   - `201 examples, 0 failures`
7. Phase 9 targeted hint-fusion/conflict-policy validation:
   - `bundle exec rspec spec/rhdl/import/project_spec.rb spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb spec/rhdl/import/report_spec.rb spec/rhdl/cli/import_spec.rb`
   - red baseline: `30 examples, 1 failure`
   - green verification: `30 examples, 0 failures`
8. Phase 9 broader importer regression:
   - `bundle exec rspec spec/rhdl/import spec/rhdl/cli/import_spec.rb`
   - `204 examples, 0 failures`
9. Surelog auto-extraction adapter red/green + importer regression:
   - `bundle exec rspec spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb`
   - `bundle exec rspec spec/rhdl/import/project_spec.rb spec/rhdl/import/report_spec.rb spec/rhdl/import/pipeline_spec.rb spec/rhdl/cli/import_spec.rb`
   - green verification: `58 examples, 0 failures`
10. Phase 10 metadata provenance red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb -e "provenance" -e "preserves case qualifier and provenance metadata"`
     - `3 examples, 3 failures`
   - green verification:
     - same command after implementation
     - `3 examples, 0 failures`
   - broader phase gate:
     - `bundle exec rspec spec/rhdl/import/project_spec.rb spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb spec/rhdl/import/report_spec.rb spec/rhdl/cli/import_spec.rb`
     - `32 examples, 0 failures`
11. Phase 11 elsif emission red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb -e "elsif_block for nested if/else-if chains"`
     - `1 example, 1 failure`
   - green verification:
     - same command after implementation
     - `1 example, 0 failures`
   - broader translator + import regression:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb`
     - `30 examples, 0 failures`
     - `bundle exec rspec spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb spec/rhdl/import/translator/module_emitter_spec.rb`
     - `57 examples, 0 failures`
12. Phase 11 case-qualifier emission red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb -e "emits case_stmt qualifier keyword when case metadata includes a qualifier"`
     - `1 example, 1 failure`
   - green verification:
     - same command after implementation
     - `1 example, 0 failures`
   - DSL/export + importer regression:
     - `bundle exec rspec spec/rhdl/dsl_spec.rb -e "qualified case statement" spec/rhdl/verilog_export_spec.rb -e "unique case statement"`
     - `2 examples, 0 failures`
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb spec/rhdl/dsl_spec.rb spec/rhdl/verilog_export_spec.rb`
     - `158 examples, 0 failures`
13. Phase 11 always_ff intent inference red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb -e "treats always_ff process intent as clocked when sensitivity edges are absent"`
     - `1 example, 1 failure`
   - green verification:
     - same command after implementation
     - `1 example, 0 failures`
   - broader translator + DSL/export + importer regression:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb spec/rhdl/dsl_spec.rb spec/rhdl/verilog_export_spec.rb`
     - `159 examples, 0 failures`
14. Phase 10 unsupported-diagnostic metadata red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/mapper/statement_mapper_spec.rb -e "includes hint metadata on unsupported diagnostics when present on the source node"`
     - `1 example, 1 failure`
   - green verification:
     - same command after implementation
     - `1 example, 0 failures`
   - mapper/import regression:
     - `bundle exec rspec spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper/expression_mapper_spec.rb spec/rhdl/import/mapper/declaration_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb`
     - `32 examples, 0 failures`
15. Phase 11 always_comb naming uplift red/green:
   - red baseline:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb -e "uses always_comb process intent for combinational naming when domain is absent"`
     - `1 example, 1 failure`
   - green verification:
     - same command after implementation
     - `1 example, 0 failures`
   - broader translator + importer + DSL/export regression:
     - `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb spec/rhdl/import/mapper/statement_mapper_spec.rb spec/rhdl/import/mapper/expression_mapper_spec.rb spec/rhdl/import/mapper/declaration_mapper_spec.rb spec/rhdl/import/mapper_spec.rb spec/rhdl/import/ir_spec.rb spec/rhdl/import/project_spec.rb spec/rhdl/dsl_spec.rb spec/rhdl/verilog_export_spec.rb`
     - `165 examples, 0 failures`
16. Broader importer sweep note (current baseline):
   - `bundle exec rspec spec/rhdl/import spec/rhdl/cli/import_spec.rb`
   - `199 examples, 2 failures`
   - failing examples:
     - `spec/rhdl/import/pipeline_spec.rb:1230` (`runs ao486_program_parity checks for ao486 top`)
     - `spec/rhdl/import/pipeline_spec.rb:1302` (`prunes prior profile report artifacts across consecutive runs`)

## Uplift Metrics (New Tranche Targets)
1. `hints.summary.extracted_count > 0` on supported Surelog fixture designs.
2. `hints.summary.applied_count / hints.summary.extracted_count >= 0.70` on curated uplift corpus.
3. `recovery.summary.dsl_uplift_score` must not regress by more than 2% on the same corpus.
4. `recovery.summary.lowered_count` trend is non-increasing per tranche for the uplift corpus.
5. All hint-applied modules must pass 3-way parity (`source Verilog`, `generated Verilog`, `generated IR`).

## Exit Criteria Per Phase
1. Phase 1: deterministic red baseline captured.
2. Phase 2: frontend preserves recoverable case/for forms.
3. Phase 3: mapper + import IR represent case/for.
4. Phase 4: translator emits readable case/for DSL blocks.
5. Phase 5: lowering supports emitted case/for statements.
6. Phase 6: recovery report + strict mode wired.
7. Phase 7: Surelog auto-hints integrated with warn-and-continue fallback.
8. Phase 8: deterministic canonical hint extraction + report accounting.
9. Phase 9: AST/hint fusion recovers additional high-level forms with deterministic conflict policies.
10. Phase 10: mapper/import IR preserve enriched forms + provenance.
11. Phase 11: translator emits maximal high-level DSL from enriched IR.
12. Phase 12: DSL/lowering/export/sim fully support newly emitted forms.
13. Phase 13: hint-applied modules are 3-way parity clean.
14. Phase 14: uplift scoring/gates are enforced and regression-safe.

## Acceptance Criteria (Full Completion)
1. Import pipeline preserves recoverable high-level procedural constructs end-to-end.
2. Generated components use human-readable DSL control-flow forms.
3. Generated component behavior remains parity-clean across:
   - source Verilog simulation
   - generated Verilog simulation
   - generated IR simulation
4. No custom component `to_verilog` methods are introduced.
5. Recovery/nonrecoverable behavior is visible in import reporting.
6. Hint extraction/application is measurable and stable via `hints.summary`.
7. Hint-applied output improves DSL uplift score on the maintained corpus without parity regressions.
8. Conflict handling between AST and hints is deterministic and policy-driven.

## Risks and Mitigations
1. Risk: Verilator AST loop shape variability.
   - Mitigation: fixture-based normalization tests for each supported node shape.
2. Risk: Statement emission changes may alter behavior.
   - Mitigation: enforce lowering + parity tests in same tranche.
3. Risk: Tooling dependency churn for Surelog.
   - Mitigation: warn-and-continue fallback and isolated backend adapter.
4. Risk: Hint conflicts may overfit to one frontend representation.
   - Mitigation: explicit conflict-policy modes and provenance-preserving diagnostics.
5. Risk: Higher-level uplift may hide semantic drift.
   - Mitigation: mandatory 3-way parity gates for every hint-applied construct family.

## Testing Gates
1. Unit: `spec/rhdl/import/frontend/normalizer_spec.rb`
2. Unit: `spec/rhdl/import/mapper/statement_mapper_spec.rb`, `spec/rhdl/import/ir_spec.rb`
3. Unit: `spec/rhdl/import/translator/module_emitter_spec.rb`
4. Unit: `spec/rhdl/codegen/ir/lower_process_spec.rb`
5. Unit: `spec/rhdl/import/frontend/surelog_hint_adapter_spec.rb`
6. Integration: `spec/rhdl/import/project_spec.rb`, `spec/rhdl/import/pipeline_spec.rb`, `spec/rhdl/import/report_spec.rb`
7. Behavioral parity: component + program parity harness suites for hint-applied modules.
8. Regression: importer/parity suites relevant to touched paths.

## Implementation Checklist
- [x] Phase 1: PRD created and execution started.
- [x] Phase 1: deterministic failing specs added (red baseline).
- [x] Phase 2: normalizer preserves `case`/recoverable `for`.
- [x] Phase 3: mapper + import IR case/for support.
- [x] Phase 4: emitter case/for DSL output.
- [x] Phase 5: lower case/for statements to backend IR.
- [x] Phase 6: recovery reporting + strict mode.
- [x] Phase 7: Surelog auto-hints integration.
- [x] Phase 8: canonical hint extraction and deterministic normalization.
- [ ] Phase 9: hint-aware AST enrichment + conflict policies.
- [ ] Phase 10: mapper/import IR uplift with provenance.
- [ ] Phase 11: translator maximizes high-level DSL emission from hints.
- [ ] Phase 12: DSL/lowering/export/sim coverage for newly emitted forms.
- [ ] Phase 13: 3-way behavioral parity for hint-applied modules.
- [ ] Phase 14: uplift scoring and regression gates.
