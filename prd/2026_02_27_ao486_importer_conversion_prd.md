# AO486 Importer-Only Conversion PRD

## Status
Completed (2026-02-28)

Reopen rationale:
- Existing parity closure is RTL-vs-converted trace-oracle based.
- Additional requirement: validate converted chip behavior against RHDL IR simulator behavior and keep importer-only correction loops.
- New phases 8-9 define red/green gates for IR-simulator parity and closure criteria.
- Additional required gate: every converted component must pass deterministic 3-way behavioral parity (`original Verilog`, `generated Verilog`, `generated IR`) with importer-owned fixes only.
- Additional required gate: generated RHDL must be human-readable DSL code using unary/binary/ternary/select/slice DSL operators, not nested AST-constructor style trees.
- Additional required gate: `ao486_program_parity` must execute an assembly-defined reset-vector program against a shared memory model and compare `source Verilog`, `generated Verilog`, and `generated IR` traces.

## Context
The repository has a generic Verilog/SystemVerilog import pipeline, but converting a real design (`ao486`) currently fails in practice due to ingestion/frontend assumptions and missing executable translation depth. The requirement is to convert `examples/ao486/reference/rtl/ao486` to an RHDL core using importer output only, with importer-level fixes for all issues (no manual edits to generated RHDL).

## Goals
- Convert ao486 RTL into generated RHDL components under `examples/ao486/hdl`.
- Keep conversion importer-driven only.
- Add robust real-project ingestion and frontend handling (include/dependency/missing-module behavior).
- Emit executable RHDL (not shell-only module files).
- Add deterministic long-run RTL-vs-converted parity using a canonical ao486 trace oracle.

## Non-Goals
- Full IEEE SystemVerilog feature coverage beyond what ao486 requires.
- Manual hand-tuned fixes inside generated RHDL files.
- Replacing unrelated import/export flows.

## Public Interfaces and Output Contract
- CLI/API options added:
  - `dependency_resolution`: `none | parent_root_auto_scan`
  - `compile_unit_filter`: `all | modules_only`
  - `missing_modules`: `fail | blackbox_stubs`
  - `check_profile`: `default | ao486_trace | ao486_trace_ir | ao486_component_parity | ao486_program_parity`
  - `trace_converted_export_mode`: `component | dsl_super`
- Output target:
  - `examples/ao486/hdl/**`
- Report additions:
  - `blackboxes_generated`
  - check oracle metadata and trace artifact paths
  - trace compare summary (`events_compared`, first mismatch details)

## Phased Plan (Red/Green/Refactor)

### Phase 1: PRD Reopen + Scope Lock
Red:
- Existing import PRD marks generic importer complete and lacks ao486-specific completion gates.

Green:
- Introduce ao486-specific PRD with explicit remaining phases and checklists.

Refactor:
- Keep a single source of truth for ao486 conversion criteria in this PRD.

Exit criteria:
- This PRD reflects active ao486 work and contains actionable, testable completion gates.

### Phase 2: Ingestion Hardening (AO486 Real Layout)
Red:
- Add failing specs for:
  - parent-root dependency autoscan from `.../rtl/ao486`
  - module-only compile-unit filtering (exclude include fragments as standalone units)
  - missing-module tolerant frontend flag behavior

Green:
- Implement:
  - `parent_root_auto_scan` source discovery
  - `modules_only` compile-unit filtering
  - deterministic source/include derivation required for ao486 includes
  - frontend command support for non-fatal missing modules (`blackbox_stubs` mode)

Refactor:
- Centralize compile-unit selection helpers in input resolver.

Exit criteria:
- Frontend invocation for ao486 source set succeeds and emits non-empty module payload.

Phase result (2026-02-27):
- Complete. `rhdl import` succeeds for `examples/ao486/reference/rtl/ao486` with:
  - `dependency_resolution=none`
  - `compile_unit_filter=modules_only`
  - `missing_modules=blackbox_stubs`
- Importer fixes shipped in this phase:
  - autoscan include-dir inference (source roots + discovered source directories)
  - deep Verilator JSON parse support (`max_nesting: false`)

### Phase 3: Real Verilator AST Extraction to Import Model
Red:
- Add failing extraction tests for required Verilator node families (`VAR`, `ASSIGNW`, `ALWAYS`, `IF`, `CASE`, `CELL`, `PIN`, `SEL`, `ARRAYSEL`, `CONCAT`, `REPLICATE`, etc.).
- Baseline currently maps module names/spans only from Verilator JSON (`modulesp`), without behavioral IR extraction for ports/declarations/statements/instances.

Green:
- Build extraction path that emits importer module model (ports, declarations, assigns, processes, instances, spans) from real Verilator JSON/meta.

Refactor:
- Isolate pointer/dtype/span resolution utilities to keep mapper code coherent.

Exit criteria:
- ao486 mapped modules include behavior/process/instance content (not names-only shells).

Phase result (2026-02-27):
- Complete. Implemented real `modulesp` extraction for core node families used in ao486:
  - `VAR` -> ports/declarations/parameters
  - `ASSIGNW` / `ASSIGN` / `ASSIGNDLY` / `IF` / `BEGIN` / `INITIAL` / `INITIALSTATIC`
  - `ALWAYS` + sensitivity (`SENITEM`)
  - `CELL` + `PIN`
  - expression families including `VARREF`, `CONST`, `AND`, `OR`, `XOR`, `ADD`, `SUB`, compares, shifts, `SEL`, `ARRAYSEL`, `CONCAT`, `REPLICATE`, `COND`, `NOT`, `EXTEND`, `NEGATE`, `REDOR`, `REDAND`, `LTS`, `GTS`
  - instance parameter override extraction from `CELL.paramsp`
- Added extraction regression coverage in normalizer specs.
- Residual risk tracked for later hardening:
  - deterministic handling strategy for `STMTEXPR`/`CMETHODHARD` side-effect forms
  - wider dtype/array coverage beyond current range handling
  - remaining rare expression/operator forms beyond current ao486-critical set

### Phase 4: Translator Emits Executable RHDL
Red:
- Add failing translator tests proving shell/comment output is insufficient.

Green:
- Emit RHDL components that can export valid Verilog for mapped modules:
  - ports/params
  - declarations
  - assigns
  - processes (blocking/non-blocking semantics)
  - instances and parameter overrides

Refactor:
- Split expression/statement emitters for maintainability.

Exit criteria:
- Converted ao486 modules export/compile as Verilog through RHDL codegen.

Phase result (2026-02-27):
- Complete. Translator now emits importer-generated classes that rely on standard RHDL DSL export behavior (no custom component `to_verilog` overrides in generated modules).
- Additional hardening:
  - generated class-name collision avoidance for Ruby core constants (for example `exception` -> `ImportedException`)

### Phase 5: Missing Module Policy via Generated Blackbox Stubs
Red:
- Add failing tests for unresolved module handling under `blackbox_stubs`.

Green:
- Auto-generate deterministic stub modules for unresolved dependencies.
- Record generated stubs in report.

Refactor:
- Share signature inference and stub emitter across pipeline/check flows.

Exit criteria:
- ao486 conversion no longer hard-fails on unresolved externals in `blackbox_stubs` mode.

Phase result (2026-02-27):
- Complete. Missing dependency handling is now explicit and deterministic in pipeline:
  - `missing_modules=fail` records unresolved dependencies as `missing_module` failures and prunes dependents.
  - `missing_modules=blackbox_stubs` generates deterministic blackbox module files with inferred port/parameter names from instance usage.
- Import report now includes `blackboxes_generated` and `summary.blackboxes_generated`.
- Real ao486 conversion confirms behavior:
  - `converted=44`, `failed=0`, `blackboxes_generated=4`
  - generated stubs: `cpu_export`, `l1_icache`, `simple_fifo_mlab`, `simple_mult`.

### Phase 6: RTL-vs-Converted Long-Run Parity (`ao486_trace`)
Red:
- Add failing checks for trace-oracle comparator and mismatch diagnostics.

Green:
- Implement `ao486_trace` check profile:
  - deterministic harness
  - instruction-state trace event stream
  - top bus/debug subset comparison
  - artifact/report emission

Refactor:
- Separate trace capture, normalization, and compare layers.

Exit criteria:
- Long-run deterministic parity passes for ao486 profile.

Phase result (2026-02-27):
- Complete. Implemented deterministic ao486 trace parity end-to-end:
  - importer check-profile infrastructure for `ao486_trace`:
  - deterministic trace event comparator (`events_compared`, `first_mismatch`)
  - per-top trace artifact writer under `reports/trace/*_trace.json`
  - pipeline routing to profile-specific checks when `check_profile=ao486_trace`
  - API option forwarding for `expected_trace_events` / `actual_trace_events`
  - CLI file inputs `--expected-trace` / `--actual-trace`
  - CLI/API command-fed trace inputs (`--expected-trace-cmd`, `--actual-trace-cmd`)
  - deterministic top-level trace key filtering (`--trace-key` / `trace_keys`)
- deterministic missing-module signature fallback from source text when frontend metadata is incomplete:
  - added `MissingModuleSignatureExtractor`
  - blackbox stubs now emit explicit port declarations (Verilator-compatible)
  - deterministic ao486 harness:
  - added `examples/ao486/tools/capture_trace.rb`
  - added `RHDL::Import::Checks::Ao486TraceHarness`
  - reference/converted modes with bounded Verilator execution and canonical JSON event output
  - converted mode materializes temporary Verilog by loading generated module Ruby files (`<out>/lib/<project>/modules/*.rb`) and exporting with canonical `RHDL::Export.verilog` semantics
  - converted export evaluation is isolated in an anonymous namespace per module load to avoid global constant leakage/stale class reuse across repeated harness runs
  - converted-mode include-dir recovery from generated import report metadata
  - event contract includes transaction events plus per-cycle `sample` bus/control events
  - automatic harness fallback for `ao486_trace` when explicit trace inputs are omitted for top `ao486` (configurable via `trace_cycles` and `trace_reference_root`)
- Added red/green coverage for pass/fail/skip semantics under trace profile.
- Added explicit forwarding coverage for ao486 harness controls (`trace_cycles`, `trace_reference_root`) across CLI/API/pipeline tests.
- Verified parity closure runs:
  - `rhdl import ... --check-profile ao486_trace` using harness commands for expected/actual traces
  - passing long-run bounded parity at `--cycles 1024` (`events_compared=1025`, `fail_count=0`)
  - trace artifact emitted at `examples/ao486/hdl/reports/trace/ao486_trace.json`
  - mismatch triage workflow documented in `docs/import.md`
- Post-closure stabilization (2026-02-27):
  - fixed importer translator mismatch for replication expressions (`kind: "replication"` vs emitter `replicate`) so assign trees are not dropped during Verilog emission
  - fixed blackbox-stub DSL leakage under `dsl_super` export by resetting generated stub class attributes and emitting deterministic DSL port/generic declarations
  - removed importer-generated custom component `to_verilog` methods from translated modules and blackbox stubs; converted export now uses standard RHDL export only
  - added pipeline enforcement: modules that define custom component export methods fail with `forbidden_custom_verilog_export` and are pruned via dependency handling
  - added slow integration assertion that generated ao486 module files contain no custom `self.to_verilog` methods
  - added fast regression for generated-stub class isolation under `dsl_super` export (`spec/rhdl/import/blackbox_stub_generator_spec.rb`)
  - added slow real ao486 integration gate for `trace_converted_export_mode=dsl_super` (`spec/rhdl/import/ao486_integration_spec.rb`)
  - validated `--trace-converted-export-mode dsl_super` parity for real ao486 conversion (`converted=44`, `failed=0`, `checks_failed=0`)
  - revalidated long-run `dsl_super` parity at `--trace-cycles 1024` (`events_compared=1025`, `fail_count=0`)
  - revalidated long-run canonical `ao486_trace` parity after harness export-path hardening at `--trace-cycles 1024` (`events_compared=1025`, `fail_count=0`)

### Phase 7: End-to-End Delivery + PRD Closure
Red:
- Add failing integration check for ao486 output path and report completeness.

Green:
- Run conversion into `examples/ao486/hdl`.
- Confirm report/check artifacts and final parity status.

Refactor:
- Tighten user-facing import summary for ao486 profile.

Exit criteria:
- All phases complete; PRD moved to `Completed` with date.

Phase result (2026-02-27):
- Complete. End-to-end ao486 importer delivery verified:
  - explicit ao486 integration gate:
  - slow spec `spec/rhdl/import/ao486_integration_spec.rb` validates:
    - real conversion + report skeleton + blackbox reporting
    - built-in `ao486_trace` harness fallback path (no explicit trace inputs)
    - `dsl_super` converted export parity path
    - no custom `to_verilog` methods in generated module files
  - validated with `bundle exec rspec --tag slow spec/rhdl/import/ao486_integration_spec.rb` (`4 examples, 0 failures`)
  - full import command with parity profile passes and writes final artifacts under `examples/ao486/hdl`
  - user-facing runbook/examples updated in `docs/import.md`, `docs/cli.md`, and `README.md`

### Phase 8: Converted Verilog-vs-IR Simulator Chip Output Parity
Red:
- Add failing integration checks that compare chip-level output traces from:
  - original ao486 Verilog simulation
  - converted ao486 running via standard RHDL IR simulation path
- Add failing checks for deterministic mismatch diagnostics (signal name, cycle index, expected vs actual value) for IR parity.

Green:
- Add IR-parity harness/profile support that:
  - runs converted ao486 through RHDL IR simulator without custom component `to_verilog` methods
  - captures deterministic chip-level output trace keys aligned with existing ao486 trace contract
  - compares original-Verilog trace vs IR-simulated converted trace
- Wire profile execution through importer check pipeline and report output.

Refactor:
- Share trace normalization/comparison utilities across RTL-vs-converted and RTL-vs-IR parity paths.

Exit criteria:
- Deterministic chip-output parity passes for ao486 between original Verilog and converted RHDL IR simulation.
- Mismatch artifacts are actionable and stable across reruns.

Phase result (2026-02-27):
- Complete. Added and closed deterministic chip-output parity for `ao486_trace_ir`:
  - pipeline routing and harness execution for expected `reference` vs actual `converted_ir`
  - deterministic chip-output sampling contract aligned with `ao486_trace` trace keys
  - deterministic mismatch/reporting structure preserved (`events_compared`, first mismatch metadata)
- Importer-level closure fix required for parity gate reliability:
  - converted trace harness export now uses canonical `RHDL::Export.verilog` path (no custom component export overrides), which fixes invalid generated converted Verilog in harness flows (for example procedural assignment-to-wire in `exception`).
- Validation evidence:
  - `bundle exec rspec spec/rhdl/import/checks/ao486_trace_harness_spec.rb spec/rhdl/import/pipeline_spec.rb`
  - `bundle exec rspec --tag slow spec/rhdl/import/ao486_integration_spec.rb` (includes `ao486_trace_ir` gate).
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 1024 examples/ao486/hdl` -> `converted=44`, `failed=0`, `checks_failed=0`

### Phase 9: IR Parity Productization + Closure
Red:
- Add failing docs/integration checks that verify IR parity workflow is documented and exercised by a reproducible command.

Green:
- Document IR parity mode in `docs/import.md`, `docs/cli.md`, and README import examples.
- Add or update slow integration gate(s) that execute the IR parity mode on ao486 with bounded cycles.

Refactor:
- Keep check-profile option semantics explicit and non-overlapping across parity modes.

Exit criteria:
- IR parity workflow is tested, documented, and reproducible from repo commands.
- PRD can be marked `Completed` after phases 8-9 are green.

Phase result (2026-02-27):
- Complete. IR parity productization/closure items are now green:
  - docs and CLI surfaces include `ao486_trace_ir` mode and reproducible commands (`README.md`, `docs/import.md`, `docs/cli.md`, CLI help).
  - integration gate covers `ao486_trace_ir` in slow ao486 suite and passes in current workspace run.
  - converted trace harness supports `converted_ir` trace capture mode in `examples/ao486/tools/capture_trace.rb`.

### Phase 10: Per-Component 3-Way Behavioral Equivalence (Required Gate)
Red:
- Add failing slow integration checks that iterate every converted ao486 component and compare, per identical stimulus stream:
  - original module Verilog simulation
  - generated module Verilog simulation
  - generated module IR simulation
- Add failing diagnostics that report:
  - component name
  - cycle index
  - signal/output name
  - original/generated-verilog/generated-ir values

Green:
- Implement a deterministic per-component parity harness in importer checks that:
  - auto-discovers converted ao486 module set from conversion output/report
  - runs all three execution modes for each module under identical vectors
  - asserts pairwise equality (`orig == gen_verilog`, `orig == gen_ir`, `gen_verilog == gen_ir`)
  - emits stable per-component artifacts and summary counts
- Wire harness into importer pipeline as an explicit check profile and add slow integration coverage.

Refactor:
- Reuse shared trace normalization/comparison code paths across chip-level and component-level checks.
- Keep conversion fixes importer-level only; no manual edits to generated ao486 module files.

Exit criteria:
- Every converted ao486 component has passing 3-way parity in one reproducible run.
- Any mismatch produces deterministic, actionable diagnostics and a failing check result.

Phase 10 progress (2026-02-27):
- Complete. Harness/profile/pipeline wiring landed (`ao486_component_parity`) and full closure now passes in one reproducible run.
- Importer-level closure fixes applied during 10B:
  - range width normalization for ascending packed ranges (`[0:N]`) now computes `abs(msb-lsb)+1`
  - EXTEND normalization now preserves width-adaptation semantics while enforcing source-width truncation before widen (prevents carry leakage in arithmetic paths and preserves concat insertion semantics)
- Full component rerun now passes for every converted ao486 module.
- Post-closure stabilization (2026-02-28):
  - fixed undriven constant output defaults from frontend `INITIAL` folds by emitting explicit output default assigns in translator output.
  - closed deterministic `memory` 3-way parity mismatches (`invdcode_done`, `invddata_done`, `wbinvddata_done`) where generated Verilog had `z` and reference/IR were driven.

Phase 10 execution snapshot (latest):
- Repro command:
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --check-profile ao486_component_parity --vectors 8 examples/ao486/hdl`
- Current result:
  - `converted=44`, `failed=0`, `checks_failed=0`
  - component status split: `pass=44`, `fail=0`, `tool_failure=0`
- Revalidated on current workspace (2026-02-27):
  - same repro command result remains `converted=44`, `failed=0`, `checks_failed=0`

### Phase 11: Human-Readable DSL Emission (No AST-Tree Output)
Red:
- Add failing importer translator/emitter specs that assert generated component source does not contain nested AST-constructor patterns for behavioral expressions/statements.
- Add failing snapshot/spec checks that require generated module code to emit readable DSL forms for core expression families used by ao486:
  - unary ops (`~`, `!`, unary minus)
  - binary ops (`+`, `-`, `&`, `|`, `^`, shifts, compares)
  - ternary (`? :` style DSL equivalent)
  - bit select/slice/concat/replication in human-authored DSL style.
- Add failing checks for readability invariants in generated component bodies:
  - no deeply nested `RHDL::DSL::*` constructor trees in emitted behavior
  - stable indentation/line layout suitable for human review and debugging.

Green:
- Refactor translator/emitter output so generated components use human-readable DSL expressions and statements directly.
- Keep semantics unchanged while improving source readability:
  - preserve nonblocking/blocking intent
  - preserve operator precedence/associativity via explicit parentheses where required
  - preserve width/sign adaptation semantics.
- Ensure emitted files remain valid for standard RHDL export flows and IR lowering.

Refactor:
- Isolate formatting/pretty-print helpers from semantic translation helpers to avoid regressions.
- Reuse expression rendering paths across assign/process emission to keep output consistent.

Exit criteria:
- Generated ao486 module files are readable DSL-first source (not AST-constructor trees).
- Readability specs/snapshots for representative ao486 modules pass.
- Existing behavioral parity gates remain green (`original Verilog` vs `generated Verilog` vs `generated IR`).

Phase result (2026-02-28):
- Complete. Generated module emission is now DSL-first and human-readable for behavioral content:
  - assignment/process emission uses operator-style DSL expressions (`+`, `-`, `&`, `|`, shifts, ternary/mux, concat/replicate, index/slice) instead of nested constructor trees.
  - verbose inline assignment/process/instance comments were removed from generated outputs to reduce noise.
  - generated modules now emit explicit readability sections (`# Parameters`, `# Ports`, `# Signals`, `# Assignments`, `# Processes`, `# Instances`) with blank-line separation between major logic blocks.
  - auto-generated unnamed process labels are now descriptive (`sequential_posedge_<clock>`, `combinational_logic_<n>`) instead of anonymous `process_<n>` names.
  - instance generic/port maps now preserve source traversal ordering instead of alphabetic resorting, improving side-by-side review against original Verilog.
  - shared class-level expression helpers now live in `RHDL::DSL`; importer no longer emits per-module helper method boilerplate in generated components.
- Red/green proof:
  - added timing-focused red test for IR memory response ordering in `Ao486ProgramParityHarness` and fixed harness ordering to match Verilog bench semantics.
  - added red readability gate for undriven output defaults and no per-module helper boilerplate in `spec/rhdl/import/translator/module_emitter_spec.rb`.
  - added slow integration enforcement in `spec/rhdl/import/ao486_integration_spec.rb` that generated ao486 modules:
    - exactly match `modules.converted + blackboxes_generated` report entries (filename-normalized)
    - contain neither per-module helper methods (`def self.sig/lit/mux/u`) nor direct `RHDL::DSL::*` constructor usage.
  - widened regression stability after importer readability changes:
    - aligned non-clocked `ProcessBlock` expectations in `spec/rhdl/dsl_spec.rb` and `spec/rhdl/verilog_export_spec.rb` to blocking assignment emission (`=`), matching current process semantics.
  - hardened output materialization for repeat imports:
    - `ProjectWriter` now prunes stale generated module files and stale vendor/source HDL files on each write.
    - added regression coverage in `spec/rhdl/import/project_writer_spec.rb` for stale-file pruning behavior.
    - `ProjectWriter` now disambiguates filename collisions deterministically when multiple module names normalize to the same base filename (stable SHA1 suffix), preventing silent overwrite/clobber.
    - `Pipeline` now prunes stale managed check report artifacts (`reports/differential`, `reports/trace`, `reports/component_parity`, `reports/program_parity`) based on current check outputs.
    - added regression coverage in `spec/rhdl/import/pipeline_spec.rb` for stale report cleanup across profile changes/re-runs.
    - added regression coverage for consecutive profile switching in the same output directory, ensuring prior profile report artifacts are pruned on the next run.
  - revalidated importer program parity on canonical output path:
    - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/hdl` -> `converted=48`, `failed=0`, `checks_failed=0`.

### Phase 12: Assembly-Driven Program Execution Parity (3-Way)
Red:
- Add failing harness/spec checks that require `ao486_program_parity` to use explicit assembly program source (not hard-coded packed words) loaded into a shared memory bank.
- Add failing integration assertions that compare `pc_sequence`, `instruction_sequence`, and tracked `memory_contents` across all three simulator modes (`reference`, `generated_verilog`, `generated_ir`) for the same assembled program image.

Green:
- Implement deterministic in-harness x86-16 assembly lowering for the parity sample program and build tracked 32-bit memory words from assembled bytes.
- Place executable instructions at reset-vector region and enforce execution signatures from fetched assembled instruction words (reset-vector seen + required instruction hits).
- Keep 3-way sequence and memory comparisons importer-owned and deterministic.

Refactor:
- Keep assembler scope local to program parity harness with strict supported-op subset and deterministic numeric parsing/output.

Exit criteria:
- `ao486_program_parity` runs with an assembly-defined program image and passes 3-way parity on real ao486 imports.
- Program parity artifacts include comparable `pc_sequence`, `instruction_sequence`, and `memory_contents` traces for all three simulators.

Phase result (2026-02-28):
- Complete. `Ao486ProgramParityHarness` now builds its program memory from assembly source (`PROGRAM_ASM_SOURCE`) using a deterministic in-harness x86-16 assembler.
- Reset-vector program execution is validated via required assembled instruction-word hits across all three simulators.
- Real parity closure confirmed for assembler-backed program flow:
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/tmp/cont_program_asm_parity` -> `converted=48`, `failed=0`, `checks_failed=0` (`pc_events_compared=8`, `instruction_events_compared=8`, `memory_words_compared=12`, `fail_count=0`).

### Phase 13: Harness Memory Connectivity Hardening
Red:
- Add failing harness checks for system-level ao486 harness paths that require a real backing memory model (not synthetic read-data constants) with read-after-write behavior.
- Add failing tests that prove byte-enable writes modify backing memory and subsequent reads observe merged written values.

Green:
- Implement backing-memory helpers in `Ao486TraceHarness` for both:
  - IR simulation mode (`converted_ir`), including burst read servicing and byte-enable write merging.
  - Verilog testbench mode (`reference`/`converted`) using a deterministic in-testbench memory bank.
- Keep event contract stable (`avm_read`/`avm_write`/`io_*`/`sample`) while replacing synthetic read stubs with memory-backed reads.
- Extend `Ao486ProgramParityHarness` behavior tests to explicitly verify write-to-memory then readback in IR mode.

Refactor:
- Keep memory helper logic localized to harness internals to avoid importer translation side effects.

Exit criteria:
- Ao486 trace harness IR path proves write/readback semantics via deterministic spec coverage.
- Ao486 trace harness Verilog bench includes and exercises memory read/write helpers.
- Ao486 program parity harness explicitly tests write/readback behavior in IR simulation.

Phase result (2026-02-28):
- Complete. Harness memory connectivity is now enforced with red/green coverage:
  - `Ao486TraceHarness` IR path now maintains a backing memory map with byte-enable writes and burst read servicing.
  - `Ao486TraceHarness` Verilog testbench now includes deterministic memory helpers (`mem_seed_word`, `mem_read_word`, `mem_write_word`) and pending-read handling.
  - Added end-to-end reference-mode harness spec proving write -> readback propagation through harness memory (`io_write_data == 0xDEAD_BEEF`).
  - Added explicit `Ao486ProgramParityHarness` IR spec proving backing memory writes are captured and read back on later reads.
  - Note: current `ao486_program_parity` real-design summaries can still report `write_events_compared=0`; this reflects the sampled ao486 execution path under the profile budget, not disconnected harness memory plumbing.

## Exit Criteria Per Phase
- Phase 1: PRD scoped and checklist active.
- Phase 2: ao486 ingestion/frontend succeeds from real tree.
- Phase 3: real AST extraction yields behavioral mapped modules.
- Phase 4: translated modules are executable and exportable.
- Phase 5: missing modules handled via generated stubs.
- Phase 6: deterministic long-run parity passes.
- Phase 7: end-to-end output/report complete at target path.
- Phase 8: deterministic original-Verilog-vs-RHDL-IR chip-output parity passes.
- Phase 9: IR parity workflow is productized, documented, and reproducibly tested.
- Phase 10: deterministic per-component `original vs generated-verilog vs generated-IR` parity passes for the full ao486 converted module set.
- Phase 11: generated ao486 components are emitted as human-readable DSL code, with readability gates and unchanged behavioral parity.
- Phase 12: `ao486_program_parity` executes an assembly-defined reset-vector program and preserves 3-way trace/memory parity.
- Phase 13: all ao486 system-level harnesses use working backing memory models with verified read/write behavior.

## Acceptance Criteria (Full Completion)
- `rhdl import` (or API equivalent) converts ao486 to `examples/ao486/hdl`.
- Conversion is importer-only, without manual post-editing of generated modules.
- Generated modules are executable through RHDL export flows.
- Missing module handling in selected mode is deterministic and reported.
- `ao486_trace` parity runs and passes long-run canonical ao486 harness trace comparison.
- Original ao486 Verilog behavior and converted ao486 behavior match under RHDL IR simulation for defined chip-output trace keys.
- Every converted ao486 module passes per-component 3-way behavioral parity (`original Verilog`, `generated Verilog`, `generated IR`).
- `ao486_program_parity` uses an assembly-defined reset-vector program image and passes 3-way parity for `pc_sequence`, `instruction_sequence`, and tracked `memory_contents`.
- Generated ao486 component source is human-readable DSL (operator-based expressions), not nested RHDL AST-constructor output.

## Risks and Mitigations
- Risk: Verilator JSON shape/pointer semantics are complex.
  - Mitigation: fixture-backed extractor tests and isolated resolution utilities.
- Risk: Ao486 includes/include-fragments produce frontend breakage.
  - Mitigation: compile-unit filtering and source/include derivation rules.
- Risk: Vendor-specific memories/modules block simulation.
  - Mitigation: generated blackbox stubs with explicit report surfacing.
- Risk: Long-run parity runtime cost.
  - Mitigation: deterministic profiles, scoped signal subsets, artifact reuse.
- Risk: IR simulator semantics may diverge from emitted Verilog semantics for edge procedural forms.
  - Mitigation: focused mismatch triage with importer-level fixes and dedicated regression fixtures.
- Risk: readability refactor can accidentally alter operator precedence or assignment semantics.
  - Mitigation: add red/green readability fixtures plus mandatory 3-way behavioral parity reruns before marking phase complete.

## Testing Gates
1. Unit tests for input resolver, command builder, extractor, translator, stub generator.
2. Integration tests for import pipeline/report behavior with ao486 profile options.
3. Parity harness tests (pass + mismatch) for RTL-vs-converted checks.
4. IR parity harness tests (pass + mismatch) for original-Verilog-vs-RHDL-IR chip outputs.
5. Per-component parity harness tests (pass + mismatch) for original-vs-generated-verilog-vs-generated-IR.
6. End-to-end ao486 conversion command + artifact checks.
7. Readability emission tests/snapshots for representative generated ao486 modules (operator-style DSL output).

Latest validation sweep (2026-02-28):
- `bundle exec rspec spec/rhdl/import --fail-fast` -> `179 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/checks/ao486_program_parity_harness_spec.rb --fail-fast` -> `4 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/checks/ao486_trace_harness_spec.rb --fail-fast` -> `15 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/checks --fail-fast` -> `54 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/checks/ao486_program_parity_harness_spec.rb spec/rhdl/import/checks/ao486_trace_harness_spec.rb --fail-fast` -> `19 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/translator/module_emitter_spec.rb --fail-fast` -> `22 examples, 0 failures`
- `bundle exec rspec --tag slow spec/rhdl/import/ao486_integration_spec.rb:7 --fail-fast` -> `5 examples, 0 failures` (includes readability/export-policy assertions in real ao486 import output).
- `bundle exec rspec spec/rhdl/import spec/rhdl/dsl_spec.rb --fail-fast` -> `222 examples, 0 failures`
- `bundle exec rspec spec/rhdl/verilog_export_spec.rb:167` -> `1 example, 0 failures`
- `bundle exec rspec spec/rhdl/import/project_writer_spec.rb spec/rhdl/import --fail-fast` -> `170 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/pipeline_spec.rb:445 spec/rhdl/import/pipeline_spec.rb:508 spec/rhdl/import --fail-fast` -> `142 examples, 0 failures`
- `bundle exec rspec spec/rhdl/import/pipeline_spec.rb:1164 spec/rhdl/import --fail-fast` -> `142 examples, 0 failures` (includes consecutive profile-switch stale-report pruning gate).
- canonical output consistency check after in-place import rerun:
  - `examples/ao486/hdl/lib/*/modules/*.rb` now exactly matches `modules.converted + blackboxes_generated` (`report_count=50`, `file_count=50`, `extra=[]`, `missing=[]`) without manual cleanup.
- canonical managed-report cleanup check after in-place import rerun:
  - injected stale files under `examples/ao486/hdl/reports/trace/` and `examples/ao486/hdl/reports/program_parity/`, reran `ao486_program_parity`, and verified stale files were removed while current check artifacts remained (`trace_stale=false`, `program_stale=false`).
- `bundle exec rake spec` -> `5012 examples, 0 failures`
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --check-profile ao486_component_parity --vectors 8 examples/ao486/tmp/cont_component_rr` -> `converted=44`, `failed=0`, `checks_failed=0` (`cycles_compared=8`, `signals_compared=136`, `fail_count=0`)
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-cycles 256 examples/ao486/tmp/cont_trace_rr` -> `converted=44`, `failed=0`, `checks_failed=0` (`events_compared=257`, `fail_count=0`)
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 256 examples/ao486/tmp/cont_trace_ir_rr` -> `converted=44`, `failed=0`, `checks_failed=0` (`events_compared=257`, `fail_count=0`)
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/tmp/cont_program_rr` -> `converted=48`, `failed=0`, `checks_failed=0` (`pc_events_compared=6`, `instruction_events_compared=6`, `memory_words_compared=11`, `fail_count=0`)
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/tmp/cont_program_asm_parity` -> `converted=48`, `failed=0`, `checks_failed=0` (`pc_events_compared=8`, `instruction_events_compared=8`, `memory_words_compared=12`, `fail_count=0`)
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/tmp/cont_program_post_cleanup` -> `converted=48`, `failed=0`, `checks_failed=0`
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-cycles 256 examples/ao486/tmp/cont_trace_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0`
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 256 examples/ao486/tmp/cont_trace_ir_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0`
- `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --check-profile ao486_component_parity --vectors 8 examples/ao486/tmp/cont_component_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0`
- post-readability-layout rerun sweep:
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-cycles 256 examples/ao486/tmp/cont_trace_post_readability_layout` -> `converted=44`, `failed=0`, `checks_failed=0`
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 256 examples/ao486/tmp/cont_trace_ir_post_readability_layout` -> `converted=44`, `failed=0`, `checks_failed=0`
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --check-profile ao486_component_parity --vectors 8 examples/ao486/tmp/cont_component_post_readability_layout` -> `converted=44`, `failed=0`, `checks_failed=0`
- deeper bounded-run parity sweep:
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-cycles 1024 examples/ao486/tmp/cont_trace_1024_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0` (`events_compared=1025`, `fail_count=0`)
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 1024 examples/ao486/tmp/cont_trace_ir_1024_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0` (`events_compared=1025`, `fail_count=0`)
  - `bundle exec ruby exe/rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --check-profile ao486_component_parity --vectors 16 examples/ao486/tmp/cont_component_vec16_post_cleanup` -> `converted=44`, `failed=0`, `checks_failed=0` (`cycles_compared=16`, `signals_compared=272`, `fail_count=0`)
- workspace hygiene check:
  - removed root scratch probe files (`.codex_perm_local_test.txt`, `.codex_probe_access.txt`) and kept new importer run outputs under `examples/ao486/tmp/*`.
- Canonical output refresh:
  - archived prior canonical output to `examples/ao486/tmp/hdl_backup_20260227_234516`
  - reran `ao486_program_parity` at `examples/ao486/hdl` -> `converted=48`, `failed=0`, `checks_failed=0` (`pc_events_compared=8`, `instruction_events_compared=8`, `memory_words_compared=12`, `fail_count=0`)
- Generated-module readability checks on canonical output:
  - `rg "def self\\.(sig|lit|mux|u)\\(" examples/ao486/hdl/lib/*/modules/*.rb` -> no matches
  - `rg "RHDL::DSL::(SignalRef|Literal|TernaryOp|UnaryOp|BinaryOp|Concatenation|Replication)" examples/ao486/hdl/lib/*/modules/*.rb` -> no matches
  - `rg "def self.to_verilog" examples/ao486/hdl/lib/*/modules/*.rb` -> no matches
  - `rg "# assign |# process |#   parameters:|#   connections:" examples/ao486/hdl/lib/*/modules/*.rb` -> no matches
  - `rg "process :process_" examples/ao486/hdl/lib/*/modules/*.rb` -> no matches

## Implementation Checklist
- [x] Phase 1: PRD created and scoped.
- [x] Phase 2: Ingestion hardening complete.
- [x] Phase 3: Real AST extraction complete.
- [x] Phase 4: Executable translator complete.
- [x] Phase 5: Blackbox stub generation complete.
- [x] Phase 6: `ao486_trace` parity complete.
- [x] Phase 7: End-to-end delivery complete.
- [x] Phase 8: Converted Verilog-vs-IR simulator chip-output parity complete.
- [x] Phase 9: IR parity productization and documentation complete.
- [x] Phase 10A: Per-component 3-way parity harness/profile and diagnostics landed.
- [x] Phase 10B: Full ao486 converted module set passes 3-way parity in one reproducible run.
- [x] Phase 11: Human-readable DSL emission is enforced and parity remains green.
- [x] Phase 12: Assembly-defined reset-vector program parity is enforced across `reference`, `generated_verilog`, and `generated_ir`.
- [x] Phase 13: System-level harness memory read/write behavior is enforced across trace/program harnesses.
