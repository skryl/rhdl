# RISC-V Web Linux Runner PRD

## Status
- Completed (2026-02-24)

## Context
- The web simulator currently exposes one RISC-V preset focused on xv6 boot assets (`kernel.bin` + `fs.img`).
- Local Linux build artifacts now exist in `examples/riscv/software/bin/` (`linux_kernel.bin`, `linux_initramfs.cpio`, `rhdl_riscv_virt.dtb`).
- We need a second web RISC-V preset for Linux while keeping the existing xv6 preset unchanged.

## Goals
1. Add a second web runner preset: `riscv_linux`.
2. Keep current `riscv` xv6 preset behavior unchanged.
3. Autoload Linux kernel/initramfs/dtb for `riscv_linux`.
4. Use the single core (`RHDL::Examples::RISCV::CPU`) for the Linux preset.
5. Keep web generation and runtime behavior backward compatible with existing presets.

## Non-Goals
1. No default runner change (still `apple2`).
2. No removal/rename of existing `riscv` xv6 preset.
3. No OOO/pipeline preset work in this change.
4. No redesign of non-RISC-V web preset handling.

## Phased Plan (Red/Green/Refactor)

## Phase 1: Preset + Generator Wiring
### Red
1. Add/adjust tests that fail until a second RISC-V config path is recognized by web generator/runtime.

### Green
1. Add `examples/riscv/config_linux.json` with runner id `riscv_linux`.
2. Update `RUNNER_CONFIG_PATHS` in `lib/rhdl/cli/tasks/web_generate_task.rb` to include the new config.
3. Ensure `web:generate` can export both `riscv` and `riscv_linux` presets.

### Refactor
1. Keep new constants and paths localized in `WebGenerateTask`.

### Exit Criteria
1. Web generator accepts both RISC-V config files.
2. Existing `riscv` config remains unchanged.

## Phase 2: Linux Artifact Staging for Web
### Red
1. Add/adjust tests for optional Linux artifact staging behavior.

### Green
1. Extend `generate_runner_default_bin_assets` to optionally copy:
2. `linux_kernel.bin`
3. `linux_initramfs.cpio`
4. `rhdl_riscv_virt.dtb`
5. Generate a Linux bootstrap binary fixture for web load flow.

### Refactor
1. Group Linux asset constants and keep optional-copy behavior consistent with existing optional assets.

### Exit Criteria
1. `web/assets/fixtures/riscv/software/bin/` can contain Linux artifacts when present.
2. Missing Linux files produce warnings, not hard failure.

## Phase 3: Runtime Loader Support for Multi-Asset Linux Boot
### Red
1. Add failing tests in `web/test/components/sim/services/initializer_runtime_service.test.mjs` for ordered multi-asset loading.
2. Add failing test for backward compatibility with current `defaultDisk` + `defaultBin` flow.

### Green
1. Add `defaultAssets` preset schema support in `initializer_runtime_service.mjs`.
2. Load ordered assets (`kind: main`/`disk`) through current runner APIs.
3. Autoload Linux kernel/initramfs/dtb/bootstrap for `riscv_linux`.
4. Preserve old path for presets without `defaultAssets`.

### Refactor
1. Reuse helpers for parsing/copying/default handling.
2. Keep new logic isolated behind `defaultAssets` presence.

### Exit Criteria
1. `riscv_linux` autoload path works without altering current xv6 path.
2. Existing non-Linux presets continue to initialize correctly.

## Phase 4: Docs + Validation
### Red
1. Confirm docs references are outdated and fail new behavior expectations.

### Green
1. Update `docs/web_simulator.md` runner list and RISC-V section for both presets.
2. Update `docs/riscv.md` web preset section for `riscv` (xv6) and `riscv_linux` (Linux).
3. Run targeted tests:
4. `bundle exec rspec spec/rhdl/cli/tasks/web_generate_task_spec.rb`
5. `node --test web/test/components/sim/services/initializer_runtime_service.test.mjs`

### Refactor
1. Keep docs concise and aligned with generated behavior.

### Exit Criteria
1. Tests for touched areas pass.
2. Docs reflect current runner presets and assets.

## Acceptance Criteria
1. Web preset list includes `riscv` and `riscv_linux`.
2. `riscv` still boots with xv6 defaults (`kernel.bin` + `fs.img`).
3. `riscv_linux` autoloads Linux artifacts from web fixtures when present.
4. Missing Linux fixtures do not crash initialization; warnings are logged.
5. Generator and runtime remain backward compatible.

## Risks and Mitigations
1. Risk: Linux bootstrap requirements diverge from CLI flow.
   - Mitigation: Reuse bootstrap generation logic from existing RISC-V runner code path.
2. Risk: Breaking existing xv6 path.
   - Mitigation: Gate new runtime path behind `defaultAssets`; keep old logic intact.
3. Risk: Generated presets drift from source config.
   - Mitigation: Update docs to call out regeneration and keep source configs authoritative.

## Implementation Checklist
- [x] Phase 1: Add PRD and start execution.
- [x] Phase 1: Add `examples/riscv/config_linux.json`.
- [x] Phase 1: Include Linux config in web generator config paths.
- [x] Phase 2: Add Linux optional asset staging in web generator.
- [x] Phase 2: Add Linux bootstrap fixture generation for web.
- [x] Phase 3: Add `defaultAssets` runtime support.
- [x] Phase 3: Add/adjust initializer runtime tests for ordered Linux loads.
- [x] Phase 4: Update docs (`docs/web_simulator.md`, `docs/riscv.md`).
- [x] Phase 4: Run targeted Ruby and web tests.
