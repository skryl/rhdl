# Linux MMU SBI + Shell Boot Completion PRD

## Status

In Progress (2026-02-23)

## Context

The prior Linux PRD (`prd/2026_02_20_linux_boot_riscv_prd.md`) completed a nommu/M-mode milestone path, but current MMU/S-mode boot still has blocking gaps:

1. Linux MMU kernel expects SBI firmware behavior, but runner bootstrap only did register setup + `jalr` with no M-mode trap firmware.
2. Default Linux initramfs path used a custom shim profile, not a full BusyBox rootfs flow, causing init/shell contract failures.
3. Boot validation accepted broad early markers and backend fallback; it did not enforce compile-backend shell reachability with initramfs defaults.

## Goals

1. Add a deterministic M-mode bootstrap firmware path that hands off Linux to S-mode via `mret` and services required SBI calls.
2. Make default `linux_initramfs.cpio` a real Buildroot BusyBox rootfs artifact (no command shim).
3. Validate MMU Linux boot-to-shell milestones using `--mode ir --sim compile` only.
4. Keep existing xv6 and CLI Linux artifact contracts intact.

## Non-Goals

1. SMP/multi-hart Linux support.
2. OpenSBI parity for all SBI extensions.
3. RV64 migration.
4. Full distro/systemd boot.

## Phased Plan (Red/Green)

### Phase 0 - MMU/SBI Gap Reproduction and Contract

Red:
- Capture failing MMU boot symptom with no effective S-mode firmware handoff/SBI service.
- Confirm runner bootstrap lacks trap firmware and delegated-path setup.

Green:
- Define minimal SBI scope for MMU single-hart boot:
  - `SBI_EXT_BASE` version/impl/probe
  - `SBI_EXT_TIME` set_timer
  - legacy timer/console fallback stubs
- Define delegation and handoff contract:
  - `mtvec`, `medeleg`, `mideleg`, `mcounteren/scounteren`, `mstatus.MPP=S`, `mepc`, `a0/a1`, `mret`.

Exit Criteria:
- Boot blocker and firmware contract are explicit and testable.

### Phase 1 - Runner Bootstrap Firmware Implementation

Red:
- Add/adjust runner bootstrap tests that fail against the old 7-instruction jump trampoline.

Green:
- Replace trampoline generation with assembled M-mode firmware blob in `HeadlessRunner`.
- Handle supervisor ecall trap dispatch in M-mode and return via `mret`.
- Keep Linux load addresses and DTB/initramfs loading behavior unchanged.

Exit Criteria:
- Runner bootstrap tests validate M-mode firmware shape + S-mode handoff + SBI base call behavior.

### Phase 2 - Real BusyBox Initramfs Defaults

Red:
- Reproduce shell/init failures when using shim initramfs as default artifact.

Green:
- Update `examples/riscv/build_linux.sh` so `linux_initramfs.cpio` is the full Buildroot rootfs (`rootfs.cpio`), preserving ext2 + busybox outputs.
- Remove shim-initramfs generation from default flow.

Exit Criteria:
- Build output contains real `linux_initramfs.cpio` and default CLI Linux path resolves to that artifact.

### Phase 3 - Compile-Backend Shell Boot Validation

Red:
- Tighten Linux slow spec to fail unless compile backend and initramfs-backed shell milestones are reached.

Green:
- Require compile backend for Linux boot milestone spec.
- Require initramfs artifact presence and pass it through `load_linux`.
- Validate post-init shell marker path (including getty enter flow when needed).

Exit Criteria:
- Targeted Linux boot test demonstrates kernel banner + init milestone + shell marker in compile mode.

## Test Strategy and Gates

1. Unit:
- `spec/examples/riscv/utilities/tasks/run_task_spec.rb`

2. CLI contract:
- `spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`

3. End-to-end slow Linux boot:
- `spec/examples/riscv/linux_boot_milestones_spec.rb` (compile backend only)

4. Artifact generation:
- `examples/riscv/build_linux.sh` producing kernel + dtb + initramfs + fs image.

## Acceptance Criteria

1. Linux bootstrap path uses M-mode firmware handoff (`mret` to S-mode), not direct jump-only trampoline.
2. SBI base/time path is sufficient for MMU early boot progression in single-hart setup.
3. Default `linux_initramfs.cpio` is a real Buildroot rootfs artifact and boots to shell markers.
4. Linux slow boot spec runs in compile backend and validates shell reachability signals.
5. Existing Linux CLI defaults (`--linux` default kernel/initramfs/dtb) remain valid.

## Risks and Mitigations

1. Risk: CPU interrupt/delegation semantics differ from spec corner cases.
Mitigation: keep firmware scope minimal, validate with compile backend, and add targeted follow-up tests for observed failures only.

2. Risk: Shell prompt format varies by init/userspace image.
Mitigation: support configurable marker sets and include enter-to-activate path.

3. Risk: Build time/cost for Linux artifacts.
Mitigation: keep artifact names deterministic and run focused test gates first.

## Implementation Checklist

- [x] Phase 0 contract captured.
- [x] Phase 1 runner SBI firmware implementation + unit coverage updates.
- [x] Phase 2 Buildroot initramfs default switch (no shim default path).
- [ ] Phase 3 compile-backend shell boot validation green with generated artifacts.
- [x] Added live UART streaming + fail-fast no-progress markers in Linux slow boot spec to shorten debug loops.
- [ ] PRD status moved to Completed with executed validation notes.

## Current Validation Notes (2026-02-23)

Executed:

1. `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb`
- Result: pass (`36 examples, 0 failures`), including new bootstrap SBI handoff runtime assertion.

2. `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- Result: pass (`7 examples, 0 failures`).

3. `./examples/riscv/build_linux.sh --no-rootfs --no-clean --jobs 8`
- Result: pass; kernel/dtb artifacts regenerated.

4. `bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Result: fail-fast in ~40s with explicit no-UART-progress signal:
  - `No UART progress for 10000000 cycles while waiting for "Linux version"`

Interpretation:

1. Test harness/debug loop speed is improved (live UART + no-progress fail-fast works).
2. MMU compile-path Linux boot remains blocked before UART banner, requiring additional hardware/firmware compatibility work.
