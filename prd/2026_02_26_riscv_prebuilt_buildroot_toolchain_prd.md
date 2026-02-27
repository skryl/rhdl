# PRD: RISC-V Linux Buildroot Prebuilt Toolchain Default

**Status:** Completed (2026-02-26)

## Context

`examples/riscv/software/build_linux.sh` currently defaults to an internal
Buildroot toolchain profile. This causes long initramfs builds because Buildroot
rebuilds binutils/gcc/uClibc in the rootfs phase. Recent runs also showed
persistent-workspace extraction corruption (`No such file or directory` under
`buildroot-2025.02.1/`) that forced costly rebuild loops.

The target workflow should optimize for fast iterative Linux bring-up where:

1. Rootfs work is mostly BusyBox + overlay.
2. Toolchain build time is avoided by using a prebuilt external toolchain.
3. Buildroot host-arch constraints are explicit and configurable.

## Goals

1. Make the default Buildroot defconfig use an external prebuilt rv32g/ilp32d
   uClibc toolchain.
2. Add explicit Buildroot container platform control (`linux/amd64` path for
   Apple Silicon users).
3. Keep persistent Buildroot workspace behavior while hardening source-tree
   integrity checks and re-extraction flow.
4. Preserve kernel build behavior and existing CLI surface (except additive
   options/env vars).

## Non-Goals

1. Reworking the Linux kernel config/profile.
2. Replacing Docker/Lima runtime selection logic.
3. Adding a full new CI pipeline for Dockerized Linux builds.
4. Producing an ext2 image by default (initramfs-first flow remains default).

## Phased Plan

### Phase 1: Prebuilt Defconfig + Script Wiring

Red:
- Reproduce slow toolchain compile behavior with internal toolchain default.
- Verify current default points at internal defconfig.

Green:
- Add a new Buildroot defconfig selecting external prebuilt rv32g/ilp32d
  uClibc toolchain.
- Switch script default `BUILDROOT_DEFCONFIG` to the new file.

Exit criteria:
- Script default references new prebuilt defconfig.
- New defconfig is present under `examples/riscv/software/buildroot/`.

### Phase 2: Buildroot Platform Control + Workspace Robustness

Red:
- Reproduce Buildroot host-arch/platform mismatch behavior and partial
  extraction failure pattern.

Green:
- Add `--buildroot-platform` and `BUILDROOT_PLATFORM`.
- Apply platform override to Buildroot-only docker runs.
- Harden Buildroot source integrity check (`docs/manual/manual.mk` plus existing
  checks) and use atomic re-extract/move flow.

Exit criteria:
- Buildroot stage accepts platform override from CLI/env.
- Buildroot extraction path self-heals from partial trees.

### Phase 3: Docs + Validation

Red:
- Ensure docs do not yet describe prebuilt default/platform requirement.

Green:
- Update `docs/riscv.md` and `README.md` with new default behavior and Apple
  Silicon guidance.
- Run targeted checks (script syntax + Buildroot config resolution checks where
  available in local environment).

Exit criteria:
- Docs reflect new default and platform flag.
- Validation commands are recorded with pass/fail status.

## Acceptance Criteria

1. `build_linux.sh` defaults to prebuilt external Buildroot defconfig.
2. Buildroot stage can be run with explicit platform override
   (`--buildroot-platform linux/amd64`).
3. Workspace corruption from partial Buildroot extraction is automatically
   repaired on next run.
4. Rootfs artifact checks treat `linux_fs.img` as optional unless produced by
   defconfig.
5. Docs and README usage examples match implemented behavior.

## Risks and Mitigations

1. Risk: Platform-specific image handling introduces runtime confusion.
   Mitigation: keep option additive, document explicit Apple Silicon command.
2. Risk: External toolchain profile incompatibility with local docker arch.
   Mitigation: expose platform override and keep internal defconfigs available.
3. Risk: Buildroot extraction hardening could mask tarball issues.
   Mitigation: fail fast when expected extracted directory is missing.

## Implementation Checklist

- [x] Phase 1: Add prebuilt external Buildroot defconfig.
- [x] Phase 1: Switch `build_linux.sh` default defconfig to prebuilt profile.
- [x] Phase 2: Add `--buildroot-platform` flag and `BUILDROOT_PLATFORM` env.
- [x] Phase 2: Apply platform override to Buildroot docker workflows.
- [x] Phase 2: Harden Buildroot source integrity and extraction flow.
- [x] Phase 2: Keep `linux_fs.img` optional in artifact verification/output.
- [x] Phase 3: Update `docs/riscv.md` and `README.md`.
- [x] Phase 3: Run targeted validation commands and record outcomes.

## Validation Results

1. `bash -n examples/riscv/software/build_linux.sh` passed.
2. `./examples/riscv/software/build_linux.sh --help` includes:
   - default prebuilt defconfig path
   - `--buildroot-platform`
   - `BUILDROOT_PLATFORM`
3. Buildroot config resolution check (amd64 container) passed:
   - `make defconfig` + `make olddefconfig` with
     `rhdl_riscv32_mmu_busybox_prebuilt_defconfig`
   - resulting `.config` contains:
     - `BR2_riscv_g=y`
     - `BR2_RISCV_ABI_ILP32D=y`
     - `BR2_TOOLCHAIN_EXTERNAL=y`
     - `BR2_TOOLCHAIN_EXTERNAL_BOOTLIN=y`
     - `BR2_TOOLCHAIN_EXTERNAL_BOOTLIN_RISCV32_ILP32D_UCLIBC_STABLE=y`
