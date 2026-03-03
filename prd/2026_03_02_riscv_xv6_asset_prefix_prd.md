# RISC-V xv6 software/bin asset prefix PRD

## Status
Completed (2026-03-02)

## Context
The RISC-V `software/bin` directory contains both Linux and xv6 artifacts. xv6 artifacts previously used generic names (`kernel.bin`, `fs.img`, `kernel_srcmap.json`), which made asset ownership ambiguous and increased risk of cross-flow confusion in CLI, web presets, and test harnesses.

## Goals
- Rename xv6 artifacts in `examples/riscv/software/bin` to `xv6_*` naming.
- Keep command-line xv6 runner behavior unchanged (same flags, same mode semantics).
- Keep web xv6 runner behavior unchanged with updated default asset paths.
- Update tests/docs to reflect the new names.

## Non-Goals
- No Linux artifact renaming.
- No behavior changes to runner load order, bootstrap logic, or fast-boot semantics.
- No changes to xv6 source tree build targets inside `examples/riscv/software/xv6`.

## Phased Plan

### Phase 1: Artifact rename + producer updates
- Red:
  - Add/adjust CLI spec coverage to assert xv6 default path resolution with renamed assets.
  - Verify stale old-path references exist before edits.
- Green:
  - Update `build_xv6.sh` outputs to write `xv6_kernel.*`, `xv6_fs.img`, and `xv6_kernel_srcmap.json`.
  - Rename tracked xv6 artifacts in `software/bin`.
- Exit criteria:
  - Build script emits only `xv6_*` artifact names for xv6 outputs.
  - Tracked xv6 binaries/srcmap are renamed in git.

### Phase 2: Consumer updates (CLI/web/tests/docs)
- Red:
  - Confirm failing/default-path mismatches in CLI/web references after producer rename.
- Green:
  - Update CLI defaults, web generation/presets, benchmarks, tests, and docs to `xv6_*` paths.
- Exit criteria:
  - No stale xv6 `software/bin/kernel.bin|fs.img|kernel_srcmap.json` references remain outside intentional legacy cleanup lines.

## Acceptance Criteria
- `rhdl examples riscv --xv6` defaults resolve to `software/bin/xv6_kernel.bin` and `software/bin/xv6_fs.img`.
- Web `riscv` preset defaults point to `xv6_kernel.bin`, `xv6_fs.img`, `xv6_kernel_srcmap.json`.
- Updated tests for CLI defaults pass.
- Documentation reflects renamed xv6 artifacts.

## Risks and Mitigations
- Risk: Missing one path reference causes runtime or test breakage.
  - Mitigation: grep sweep for old path patterns + targeted spec/test runs.
- Risk: Existing generated files diverge from source configs.
  - Mitigation: update tracked generated config files and test expectations consistently.

## Implementation Checklist
- [x] Phase 1 Red: identify all old xv6 path references.
- [x] Phase 1 Green: update xv6 build outputs to `xv6_*` names.
- [x] Phase 1 Green: rename tracked xv6 artifacts in `software/bin`.
- [x] Phase 1 Exit criteria met.
- [x] Phase 2 Red: identify downstream CLI/web/test/doc references.
- [x] Phase 2 Green: update CLI, web presets/generation, tests, docs.
- [x] Phase 2 Exit criteria met.
- [x] Acceptance criteria validated with targeted test commands.
