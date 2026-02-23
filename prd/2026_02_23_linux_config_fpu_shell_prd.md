# Linux `CONFIG_FPU` Enablement + Shell Boot PRD

## Status

Completed (2026-02-23)

## Context

The current Linux minimum profile for RISC-V disables `CONFIG_FPU`, and the default DTB ISA string does not currently advertise `f` (`rv32imasu_zicsr_zifencei`). We need to enable Linux kernel FPU support while preserving the existing compile-backend boot-to-shell flow.

Current practical constraints:
1. Linux shell boot must remain reliable on `--mode ir --sim compile`.
2. The build path must keep deterministic artifact names used by `--linux` defaults.
3. We should only enable `F` in this work, not re-enable unrelated ISA extensions.

## Goals

1. Enable `CONFIG_FPU=y` in the generated Linux kernel config used by default Linux artifacts.
2. Align DTB ISA declaration with `F` support (`...f...` in `riscv,isa`).
3. Preserve boot-to-shell behavior with default `--linux` artifacts on compile backend.
4. Keep existing CLI default artifact contracts (`kernel`, `dtb`, `initramfs`) intact.

## Non-Goals

1. Enabling `C`, `V`, `Zb*`, `Zicbo*`, or other non-`F` extensions.
2. Implementing new FP functionality in userland beyond boot-to-shell validation.
3. Performance tuning or kernel size optimization beyond functional correctness.
4. Changing multi-hart/SMP behavior.

## Phased Plan (Red/Green)

### Phase 0 - Baseline Contract and Failure Signal

Red:
1. Add a reproducible check that fails when `CONFIG_FPU` is not enabled in Linux artifacts.
2. Capture baseline shell-boot signal on compile backend for comparison.

Green:
1. Confirm baseline failure for `CONFIG_FPU` check.
2. Confirm baseline shell probe still passes before changes.

Exit Criteria:
1. We have deterministic red/green checks for config state and shell reachability.

### Phase 1 - Enable `CONFIG_FPU` in Linux Build Profile

Red:
1. Add or tighten build-time guard so the build fails if `CONFIG_FPU` is not `y` after `olddefconfig`.

Green:
1. Remove the minimum-profile force-disable of `FPU`.
2. Keep other currently-disabled extension toggles unchanged.
3. Rebuild kernel artifacts and confirm `linux_kernel.config` contains `CONFIG_FPU=y`.

Exit Criteria:
1. `examples/riscv/software/bin/linux_kernel.config` includes `CONFIG_FPU=y`.
2. Kernel build succeeds with current default Linux flow.

### Phase 2 - DTB ISA Alignment for `F`

Red:
1. Add a check that fails when generated DTB/DTS ISA string omits `f`.

Green:
1. Update default Linux ISA string to include `f` (target: `rv32imafsu_zicsr_zifencei`).
2. Regenerate DTB artifacts and verify the DTS advertises `f`.

Exit Criteria:
1. `examples/riscv/software/bin/rhdl_riscv_virt.dts` advertises an ISA string including `f`.
2. Linux boot does not regress due to ISA declaration mismatch.

### Phase 3 - Compile-Backend Boot-to-Shell Validation

Red:
1. Ensure slow Linux milestone check fails on panic/no-init/no-progress markers.
2. Require compile backend path for this validation.

Green:
1. Run compile-backend Linux boot validation to shell prompt.
2. Confirm command execution at shell (`echo` token round-trip).

Exit Criteria:
1. Compile-backend Linux path reaches shell prompt with `CONFIG_FPU=y`.
2. No panic/no-init fail-fast markers are hit.

### Phase 4 - CLI Contract and Documentation Parity

Red:
1. Add or update checks for `--linux` default artifact resolution using default kernel/dtb/initramfs.

Green:
1. Validate CLI defaults still boot with the updated artifacts.
2. Update `docs/riscv.md` if ISA default string behavior changed.

Exit Criteria:
1. `--linux` defaults continue to work without requiring explicit `--kernel`/`--dtb`.
2. Docs match shipped behavior.

## Test Strategy and Gates

1. Config/Artifact gate:
`rg '^CONFIG_FPU=y' examples/riscv/software/bin/linux_kernel.config`

2. DTB ISA gate:
`rg 'riscv,isa = \".*f.*\"' examples/riscv/software/bin/rhdl_riscv_virt.dts`

3. CLI/runner contract gate:
`bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`

4. End-to-end Linux shell gate (compile backend):
`bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`

## Acceptance Criteria

1. Linux artifacts are built with `CONFIG_FPU=y`.
2. Default DTB ISA string used in build artifacts includes `f`.
3. Default `--linux` flow reaches a working shell on compile backend.
4. No Linux panic/no-init/no-progress failure markers occur in the validated boot path.
5. User-facing docs are aligned if default ISA string behavior changes.

## Risks and Mitigations

1. Risk: DTB ISA mismatch causes runtime feature-disable or boot instability.
Mitigation: enforce DTS ISA gate and validate shell boot after DTB regeneration.

2. Risk: Kernel emits FP paths that expose hardware/RTL gaps.
Mitigation: keep fail-fast markers and compile-backend shell probe in the critical path.

3. Risk: Boot timing regresses with `FPU` enabled.
Mitigation: keep no-progress guard configurable and treat milestone thresholds as explicit test parameters.

4. Risk: Scope creep into other extensions while enabling `F`.
Mitigation: lock this PRD scope to `CONFIG_FPU` + ISA string alignment only.

## Implementation Checklist

- [x] Phase 0: Baseline red/green checks captured.
- [x] Phase 1: `CONFIG_FPU` enabled in Linux build profile and artifact verified.
- [x] Phase 2: DTB ISA string updated to include `f` and artifact verified.
- [x] Phase 3: Compile-backend boot-to-shell validation green.
- [x] Phase 4: CLI default contract + docs parity verified.
- [x] PRD status updated to `Completed` with validation notes.

## Validation Notes (2026-02-23)

1. Baseline red/green capture
- `rg -n '^CONFIG_FPU=y' examples/riscv/software/bin/linux_kernel.config`
  - Baseline result: no match (red; `CONFIG_FPU` not enabled in existing artifact).
- `bundle exec ruby /tmp/rhdl_shell_probe_quick.rb`
  - Baseline result: Linux banner + init handoff reached; shell path was sensitive to overlay `inittab`.
  - Follow-up fix applied: overlay `inittab` reset to `::respawn:/bin/sh` for stable shell startup.

2. Build/profile update execution
- Updated `examples/riscv/build_linux.sh`:
  - default DT ISA to `rv32imafsu_zicsr_zifencei`
  - restored minimal-profile extension-disable set
  - kept `FPU` enabled
  - added build-time guard requiring `CONFIG_FPU=y` when `MIN_PROFILE=1`
- Rebuilt artifacts:
  - `JOBS=1 examples/riscv/build_linux.sh --no-clean --no-rootfs`
  - Result: success; kernel + dtb artifacts regenerated.

3. Config and DTB gates
- `rg -n '^CONFIG_FPU=y' examples/riscv/software/bin/linux_kernel.config`
  - Result: `CONFIG_FPU=y` present.
- `rg -n 'riscv,isa = \"rv32[^_\"]*f[^_\"]*_\"' examples/riscv/software/bin/rhdl_riscv_virt.dts`
  - Result: DTS advertises `rv32imafsu_zicsr_zifencei`.

4. Boot-to-shell/CLI validation
- `bundle exec ruby /tmp/rhdl_shell_probe_quick.rb`
  - Result: pass (`linux banner`, `init handoff`, `shell prompt`, and shell command token).
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
  - Result: pass (`7 examples, 0 failures`).
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
  - Result: pass (`1 example, 0 failures`) with Linux banner and init milestone over UART.

5. Documentation parity
- Updated `docs/riscv.md` minimum-profile wording from `RV32IMA-focused` to `RV32IMAF-focused`.
