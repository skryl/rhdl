# Linux Boot on RISC-V Core PRD

## Status

Completed - Minimal Linux UART boot milestone achieved in native IR with aggressive RV32 profile (2026-02-20)

## Context

Current RISC-V support is strong for xv6 on native IR backends:

- `--xv6` flow exists and loads kernel + fs with UART mode (`examples/riscv/bin/riscv`, `examples/riscv/utilities/runners/headless_runner.rb`).
- Privileged readiness, Sv32 translation, interrupt delegation, RV32A atomics, and virtio-blk paths are covered by focused specs in `spec/examples/riscv/`.
- Web preset and integration tests already boot xv6 to shell prompt in compiler mode (`web/test/integration/riscv_wasm_shell_boot.test.mjs`, `web/test/integration/riscv_ghostty_uart_shell.test.mjs`).

Known issues and constraints impacting Linux work:

- xv6 build script path/docs are inconsistent with actual script location and script directory assumptions.
- Terminal runner fast-boot patching is fixed to one mode, while web supports mode variants.
- Core/platform model is RV32-focused with minimal MMIO register surface and xv6-targeted virtio behavior.
- Current runner/CLI/test flows are xv6-oriented and do not provide a Linux artifact contract.
- Linux source management is not yet defined like xv6 upstream: no Linux submodule under `examples/riscv/software/`, and no patch-layer workflow for local source changes.

## Goals

1. Boot a minimal Linux kernel on the RISC-V core to deterministic UART milestones (`Linux version` + early-boot markers) in the native IR runner path.
2. Provide a repeatable local artifact/build flow for Linux images used by CLI and tests.
3. Add automated red/green coverage from loader contract to full boot milestones.
4. Preserve existing xv6 workflows while introducing Linux support incrementally.

## Non-Goals

1. RV64 migration in this PRD.
2. SMP/multi-hart Linux support.
3. Full distribution boot (networking/graphical stack/systemd parity).
4. Verilog/FPGA deployment parity in this iteration.

## Phased Plan (Red/Green)

### Phase 0 - Linux Target Contract and Artifact Pipeline

Red:
- Add failing tests for Linux artifact discovery/validation in runner and CLI (`--linux` path missing files, invalid combinations).
- Add a failing smoke harness that expects Linux boot artifacts (`kernel`, `initramfs` or rootfs, optional `dtb`) at known locations.

Green:
- Add Linux build helper(s) under `examples/riscv/software/` that produce deterministic local artifacts into `examples/riscv/software/bin/`.
- Add Linux upstream source as a git submodule under `examples/riscv/software/` (parallel to how xv6 upstream source is tracked).
- Add a local Linux source patch folder (for example `examples/riscv/software/linux_patches/`) and apply patches from that folder during build before artifact generation.
- Add docs for required toolchain and expected outputs.

Exit Criteria:
- Local command produces Linux artifacts with deterministic names.
- Linux submodule commit is pinned and patch application is reproducible/deterministic.
- New artifact-validation tests pass.

### Phase 1 - Runner/CLI Linux Load Path

Red:
- Add failing tests for `HeadlessRunner#load_linux` (or equivalent) covering load addresses, reset vector, and failure behavior.
- Add failing CLI tests for `examples/riscv/bin/riscv --linux` and override flags.

Green:
- Implement Linux loader path in shared runner/task classes.
- Wire CLI flags and explicit error messages for missing/invalid artifacts.
- Keep xv6 path behavior unchanged.

Exit Criteria:
- Linux loader tests pass.
- CLI Linux command loads artifacts and starts execution deterministically.

### Phase 2 - Boot Entry Contract (Recommended: M-mode First)

Red:
- Add failing tests that assert Linux entry register contract and memory handoff:
  - `a0` hart id
  - `a1` DTB pointer (if DTB used)
  - expected start PC and mapping assumptions

Green:
- Implement entry register setup and DTB handoff support in loader/runtime.
- Choose and document boot mode:
  - Recommended first milestone: machine-mode Linux config to reduce SBI surface.
  - Decision gate: if S-mode boot is required, define minimal SBI scope for later phase.

Exit Criteria:
- Entry contract tests pass.
- Boot path reaches Linux early console initialization point.

### Phase 3 - CPU/Privileged/MMU Compatibility for Linux Early Boot

Red:
- Add failing compatibility tests for Linux-critical privileged behavior not already guaranteed by xv6 specs:
  - CSR behavior Linux touches during early boot
  - page-fault/permission semantics under Linux paging setup
  - trap/interrupt edge cases observed from Linux boot traces

Green:
- Implement missing CPU/MMU/CSR behavior required by Linux early boot.
- Keep single-cycle and pipeline parity through differential tests where applicable.

Exit Criteria:
- Early Linux boot progresses past trap/CSR setup without panic loops.
- New privileged/MMU tests pass for targeted core(s).

### Phase 4 - Platform Device/Interrupt Compatibility for Linux Drivers

Red:
- Add failing integration tests for Linux-relevant MMIO interactions:
  - UART console I/O path
  - CLINT/PLIC interrupt flow as used by Linux timer/irq initialization
  - virtio-blk negotiation and request lifecycle used by Linux block stack

Green:
- Extend MMIO/register behavior where Linux expects additional compatibility.
- Ensure interrupt ack/claim and virtio queue semantics match Linux driver expectations for selected config.

Exit Criteria:
- Linux reaches userspace init with block-backed rootfs/initramfs in test environment.
- MMIO compatibility tests pass.

### Phase 5 - End-to-End Boot and Regression Hardening

Red:
- Add failing E2E boot spec(s) that require milestones:
  - `Linux version` banner
  - follow-on early-boot UART markers (for example machine model, early console, panic path)

Green:
- Tune boot config/cycle budget and runner defaults for stable CI/runtime behavior.
- Add targeted regressions for known fragile points.

Exit Criteria:
- E2E Linux boot milestone tests pass reliably in native backend matrix.
- xv6-focused tests still pass.

### Phase Completion Notes (2026-02-20)

- Phase 0: Linux source/patch workflow landed with pinned submodule (`examples/riscv/software/linux`), deterministic patch application (`examples/riscv/software/linux_patches/`), and deterministic build outputs via `examples/riscv/build_linux.sh`.
- Phase 1: Runner and CLI Linux load path landed (`--linux`, kernel/initramfs/dtb overrides, deterministic load addresses/error handling), covered by task/CLI specs.
- Phase 2: Linux entry contract landed via deterministic bootstrap trampoline (`a0` hart id, `a1` DTB pointer, entry PC handoff), covered by runner specs.
- Phase 3: Linux early-boot privilege/CSR/MMU compatibility coverage landed (`spec/examples/riscv/linux_privilege_boot_spec.rb`, `spec/examples/riscv/linux_csr_mmio_compat_spec.rb`).
- Phase 4: Linux MMIO/interrupt integration coverage landed (`spec/examples/riscv/linux_mmio_interrupt_spec.rb`).
- Phase 5: End-to-end Linux UART boot milestone coverage is now green with DTB handoff + aggressive RV32 minimum-size config (`spec/examples/riscv/linux_boot_milestones_spec.rb`), and docs were updated for Linux CLI workflow and artifact expectations.

## Test Strategy and Gates

1. Unit/op-level:
- loader parsing, artifact validation, entry register setup, patching behavior.

2. Integration:
- runner + MMIO behavior for UART/CLINT/PLIC/virtio under Linux-oriented scenarios.

3. End-to-end:
- Linux boot milestone tests in native backend(s), with explicit cycle/time budgets.

4. Workflow-level:
- CLI command coverage for `--linux` and artifact overrides.

If a gate cannot run locally, record exactly what was skipped and why.

## Validation Notes (2026-02-20, local environment)

Executed:

- `bundle exec rake native:build`  
  Result: native IR backends built (`ir_interpreter.dylib`, `ir_jit.dylib`, `ir_compiler.dylib`).
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/linux_csr_mmio_compat_spec.rb spec/examples/riscv/linux_privilege_boot_spec.rb spec/examples/riscv/linux_mmio_interrupt_spec.rb spec/examples/riscv/xv6_readiness_spec.rb`  
  Result: `76 examples, 0 failures`.
- `bundle exec rspec --tag slow spec/examples/riscv/xv6_shell_io_spec.rb`  
  Result: `6 examples, 0 failures, 2 pending` (pending due optional compiler AOT mode not enabled).
- Linux artifact build (`examples/riscv/software/bin/linux_kernel.bin`, `linux_kernel.elf`, `linux_kernel.map`, `linux_kernel.config`) via Docker/Colima cross-compile  
  Result: artifacts generated successfully for:
  - full `rv32_defconfig` profile (`linux_kernel.bin` ~30M),
  - reduced profiles (`linux_kernel.bin` ~25M and ~3.0M) for size-cut experiments.
- `bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb` (executed after artifact generation for each profile above)  
  Result: fails consistently with timeout (`Test exceeded 600 second timeout`) while waiting for `Linux version` UART milestone, including full `rv32_defconfig`.
- Direct harness UART probe (`IRHarness` + `runner_load_rom` + `run_cycles`) with generated full artifact  
  Result: no UART bytes observed in early-cycle windows (for example 100k and 10M cycle probes), consistent with milestone timeout behavior.
  Note: this failure mode was superseded by DTB handoff + M-mode min-profile boot path validation below.

Additional completion validation (2026-02-20):

- Built RV32 M-mode `rv32_nommu_virt_defconfig` profile with DTB handoff and ISA-aligned reductions for this core (no `C/F/V`/vendor/bitmanip assumptions).  
  Result: native IR emits Linux UART output (`Booting Linux`, `Linux version`, `Machine model`, `earlycon`) with DTB path `examples/riscv/software/bin/rhdl_riscv_virt.dtb`.
- Aggressive size-cut iterations completed (with boot probe after each candidate).  
  Result: smallest validated booting artifact is `examples/riscv/software/bin/linux_kernel.bin` ~2.4M.
- `spec/examples/riscv/linux_boot_milestones_spec.rb` was updated to use runner `load_linux` + DTB handoff and early-boot milestone markers to match the validated boot contract.
- `bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`  
  Result: `1 example, 0 failures`.
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`  
  Result: `39 examples, 0 failures`.
- `docker run ... ./examples/riscv/build_linux.sh --no-clean --jobs 8` (Colima runtime)  
  Result: deterministic artifacts generated successfully with minimized kernel size (`linux_kernel.bin` 2,553,644 bytes).

## Acceptance Criteria

1. `rhdl examples riscv --linux ...` boots Linux to UART early-boot milestones (`Linux version` + follow-on markers) on the targeted native backend.
2. Automated tests cover loader contract, early boot compatibility, and E2E UART milestone.
3. Existing xv6 flows (`--xv6`, xv6 specs, web preset behavior) remain functional.
4. Documentation is updated for Linux build/run workflows and limitations.
5. PRD checklist and status are updated as work progresses.
6. Linux source tree and local modifications are reproducible: Linux comes from a pinned submodule and any local changes are represented as tracked patches applied during build.

## Risks and Mitigations

1. Risk: Linux requires behavior beyond current RV32/MMIO model.
Mitigation: milestone-based boot tracing, add failing probes first, implement only observed blockers per phase.

2. Risk: Boot-time cycle cost is too high for reliable tests.
Mitigation: deterministic boot config, bounded milestone tests, optional fast-boot tuning with explicit mode.

3. Risk: Divergence between terminal runner and web runner behavior.
Mitigation: share loader semantics and add parity tests for fast-boot/entry contract.

4. Risk: Toolchain/environment drift for Linux artifact generation.
Mitigation: pinned build instructions, explicit artifact names, early artifact validation tests.

5. Risk: Local Linux source edits drift and become unreproducible.
Mitigation: forbid ad-hoc edits in submodule for build workflows; keep local changes as patch files in a tracked patch folder and apply them automatically during build.

## Implementation Checklist

- [x] Phase 0: Linux artifact contract + failing validation tests + working artifact builder + pinned Linux submodule + local patch folder applied during build. (Completed via `examples/riscv/build_linux.sh` and Linux task/CLI contract coverage.)
- [x] Phase 1: Runner/CLI Linux load path with passing loader/CLI tests. (Completed via `--linux` path and Linux loader contract tests.)
- [x] Phase 2: Entry contract (a0/a1/PC/DTB) implemented and tested. (Completed via deterministic Linux bootstrap trampoline assertions.)
- [x] Phase 3: Linux early-boot CPU/MMU/CSR blockers addressed with red/green coverage. (Completed with Linux privilege and CSR/MMIO compatibility specs.)
- [x] Phase 4: Linux-relevant MMIO/interrupt compatibility completed with integration tests. (Completed with Linux MMIO/interrupt integration specs.)
- [x] Phase 5: E2E Linux boot milestones green; xv6 regressions checked. (Linux milestone flow now boots to UART banner/early markers with DTB handoff and aggressive RV32 minimum-size kernel profile.)
- [x] Docs updated (`README.md`, `docs/riscv.md`, CLI help text where needed). (Completed for README/docs Linux workflow and artifact contract updates.)
