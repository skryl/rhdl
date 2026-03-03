# RISC-V Linux DTB/DTS bin prefix rename PRD

## Status
Completed (2026-03-02)

## Context
Linux artifact names under `examples/riscv/software/bin` still used the legacy prefix `rhdl_riscv_*` for DTB/DTS outputs, while other Linux artifacts use `linux_*` naming.

## Goals
- Rename `software/bin/rhdl_riscv_*` artifacts to `software/bin/linux_*`.
- Keep CLI, web presets, and tests aligned with the new names.
- Preserve runtime behavior (only file naming changes).

## Non-Goals
- No Linux boot logic changes.
- No changes to xv6 flow beyond existing naming updates.

## Phased Plan

### Phase 1: Rename producer outputs
- Red:
  - Identify all `rhdl_riscv_*` references.
- Green:
  - Update `build_linux.sh` output paths from `rhdl_riscv_virt.dts/dtb` to `linux_virt.dts/dtb`.
  - Rename tracked `rhdl_riscv_virt.dtb` artifact to `linux_virt.dtb`.
- Exit criteria:
  - Linux build script emits `linux_virt.*` names.

### Phase 2: Update consumers
- Red:
  - Confirm stale path references in CLI/web/spec/docs.
- Green:
  - Update CLI defaults, web generation constants/config, specs, and docs.
- Exit criteria:
  - No remaining runtime references to `rhdl_riscv_*` names.

## Acceptance Criteria
- CLI Linux default DTB path is `software/bin/linux_virt.dtb`.
- Web Linux preset uses `./assets/fixtures/riscv/software/bin/linux_virt.dtb`.
- Linux-related specs pass with renamed paths.

## Risks and Mitigations
- Risk: Missing one path breaks load flow.
  - Mitigation: repo-wide grep + targeted CLI/web unit tests.

## Implementation Checklist
- [x] Locate all `rhdl_riscv_*` path references.
- [x] Rename build outputs to `linux_virt.*`.
- [x] Rename tracked DTB artifact in git.
- [x] Update CLI/web/spec/docs references.
- [x] Run targeted tests and grep verification.
