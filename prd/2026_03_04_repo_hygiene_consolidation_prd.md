# 2026_03_04_repo_hygiene_consolidation_prd

## Status
Completed (2026-03-04)

## Context
The repository currently has multiple hygiene regressions introduced during simulator namespace/path migration and ongoing workflow changes:
1. Inconsistent submodule metadata vs index state (`.gitmodules` does not match gitlinks in index).
2. Stale `.gitignore` entries for old simulator paths and missing ignore coverage for moved native crates.
3. Tracked ephemeral files (`.tmp` probes and web test run metadata).
4. `rhdl clean` does not clean major generated artifact directories.
5. Cross-example duplicated Apple2/MOS6502 software assets should be shared locally.
6. Identical IR VCD implementation is duplicated in three crates.

User requirements:
1. Add a formal PRD for this work.
2. Implement all planned hygiene fixes.
3. Implement hygiene checks as a CLI task under `lib/rhdl/cli/tasks` (not a standalone script).
4. Use conservative deduplication with symlink sharing between example directories where appropriate.
5. Normalize xv6 as a proper submodule.

## Goals
1. Add `RHDL::CLI::Tasks::HygieneTask` and wire it to CLI + rake.
2. Normalize `.gitignore` and native crate ignore coverage to current `lib/rhdl/sim/native/*` paths.
3. Remove tracked ephemeral artifacts and prevent reintroduction.
4. Normalize submodule metadata/index for `examples/riscv/software/xv6` and `examples/ao486/reference`.
5. Expand `rhdl clean` to clean generated simulation/web/temp artifacts.
6. Replace duplicated Apple2/MOS6502 shared software files with symlinks.
7. Remove IR VCD source duplication across interpreter/JIT/compiler crates.

## Non-goals
1. Changing simulator execution behavior or semantics.
2. Refactoring intentional diagram-mode duplicate outputs in this pass.
3. Changing Linux submodule content/workflow beyond metadata consistency and documentation.

## Phased Plan

### Phase 1: Hygiene Task Foundation (Red/Green)
Red:
1. Add task spec that fails without hygiene checks.
2. Add failing checks for submodule parity, stale ignore paths, tracked ephemera, and duplicate policy.

Green:
1. Implement `lib/rhdl/cli/tasks/hygiene_task.rb`.
2. Wire in `lib/rhdl/cli.rb`, `exe/rhdl`, and `Rakefile` (`hygiene:check`).
3. Provide deterministic, actionable failure output and nonzero exit on failure.

Refactor:
1. Add a small allowlist file for intentional duplicates.

Exit criteria:
1. `rhdl hygiene` and `bundle exec rake hygiene:check` run and report current failures accurately.

### Phase 2: Ignore and Tracked-Noise Normalization (Red/Green)
Red:
1. Ensure hygiene check flags old `lib/rhdl/codegen/*/sim` ignore paths.
2. Ensure hygiene check flags tracked `.tmp` probe files and `web/test-results/.last-run.json`.

Green:
1. Update `.gitignore` from old simulator paths to moved `lib/rhdl/sim/native/*` paths.
2. Add `/.tmp/` and `/web/test-results/` ignores.
3. Add crate-local `.gitignore` in moved netlist crates.
4. Remove ephemeral files from index.

Refactor:
1. Keep ignore rules explicit to avoid swallowing submodule source content.

Exit criteria:
1. Hygiene check passes ignore + tracked-noise sections.

### Phase 3: Submodule Consistency (Red/Green)
Red:
1. Ensure hygiene check fails when `.gitmodules` entries and gitlinks diverge.

Green:
1. Restore `examples/riscv/software/xv6` as a real gitlink submodule.
2. Restore `examples/ao486/reference` as a real gitlink submodule.
3. Verify `.gitmodules` and gitlink index entries are aligned.

Refactor:
1. Ensure docs and hints reference canonical submodule locations.

Exit criteria:
1. `git submodule status` and hygiene check agree on full submodule set.

### Phase 4: Clean Surface Expansion (Red/Green)
Red:
1. Add/adjust specs for `GenerateTask#clean_all` to fail unless new targets are cleaned.

Green:
1. Extend `GenerateTask#clean_all` to include:
   - native build artifacts via `NativeTask`.
   - `**/.verilator_build*`, `**/.arcilator_build*`, `**/.hdl_build`.
   - `web/dist`, `web/build/*` generated dirs, `web/test-results`.
   - `tmp` and `.tmp`.
2. Update `rhdl clean --help` text accordingly.

Refactor:
1. Keep clean non-destructive for dependency installs (`node_modules`) and submodule source trees.

Exit criteria:
1. Updated clean specs pass and manual clean smoke confirms target paths are removed.

### Phase 5: Conservative Dedup via Symlinks (Red/Green)
Red:
1. Add hygiene duplicate-policy check for Apple2/MOS6502 shared assets.

Green:
1. Keep Apple2 software assets as canonical.
2. Replace MOS6502 copies with symlinks for shared files:
   - fig-forth files (`fig6502.asm`, `Makefile`, `README.TXT`)
   - Karateka disk/memory artifacts
   - shared ROMs (`appleiigo.rom`, `disk2_boot.bin`)
3. Keep intentional duplicates allowlisted (diagram modes and generated TS/MJS pairs).

Refactor:
1. Add concise policy documentation (`docs/repo_hygiene.md`).

Exit criteria:
1. Duplicate-policy check passes with only allowlisted duplicates.

### Phase 6: IR VCD Dedup (Red/Green)
Red:
1. Build checks fail if shared VCD extraction breaks crate compilation.

Green:
1. Introduce shared IR VCD module under `lib/rhdl/sim/native/ir/common/vcd.rs`.
2. Have interpreter/JIT/compiler include shared source instead of duplicated copies.
3. Preserve crate interfaces.

Refactor:
1. Add comments documenting shared ownership and include pattern.

Exit criteria:
1. All three crates compile and existing relevant specs pass.

### Phase 7: Validation and Completion
Red:
1. Run focused tests and hygiene check to identify remaining gaps.

Green:
1. Pass targeted task specs and hygiene checks.
2. Verify submodule status and docs consistency.
3. Mark PRD `Completed` with date and checked implementation checklist.

Refactor:
1. Record any non-runnable gates explicitly.

Exit criteria:
1. Acceptance criteria all satisfied.

## Acceptance Criteria
1. `lib/rhdl/cli/tasks/hygiene_task.rb` exists and is wired to CLI (`rhdl hygiene`) and rake (`hygiene:check`).
2. `.gitignore` contains only current simulator native paths and relevant temp/test ignores.
3. No tracked `.tmp/riscv_ext_probe.*` or `web/test-results/.last-run.json` remain.
4. `.gitmodules` and gitlinks are consistent for:
   - `examples/apple2/reference`
   - `examples/gameboy/reference`
   - `examples/riscv/software/linux`
   - `examples/riscv/software/xv6`
   - `examples/ao486/reference`
5. `rhdl clean` removes expanded generated artifact set.
6. Shared Apple2/MOS6502 software files are symlinked, not duplicated.
7. IR VCD code is centralized/shared with no three-way duplicated copies.

## Risks and Mitigations
1. Risk: submodule conversion can disrupt working copy state.
   Mitigation: perform conversion with explicit index checks and validate `git submodule status` after each change.
2. Risk: expanded clean could remove files users expect to keep.
   Mitigation: exclude dependency installs and source trees; cover with specs.
3. Risk: symlink behavior differs across tools/platforms.
   Mitigation: use relative symlinks and add hygiene validation for link targets.
4. Risk: shared Rust include path can break crate builds.
   Mitigation: run targeted native task/check and focused specs after change.

## Implementation Checklist
- [x] Phase 1: Add hygiene task + spec + CLI/rake wiring.
- [x] Phase 2: Update ignore rules and untrack ephemeral files.
- [x] Phase 3: Normalize xv6 and ao486 submodules.
- [x] Phase 4: Expand `rhdl clean` behavior + tests.
- [x] Phase 5: Symlink shared Apple2/MOS6502 assets + duplicate policy.
- [x] Phase 6: Consolidate IR VCD source.
- [x] Phase 7: Run validation gates and mark PRD completed.
