# RISC-V Zba Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zba (address-generation bit-manip subset) in both cores as the first extension phase, while preserving Linux shell boot.

## Goals

1. Implement core Zba decode/execute paths in single-cycle and pipelined cores.
2. Add focused Zba tests for both cores.
3. Keep Linux compile-backend shell boot green.

## Non-Goals

1. Full Zbb/Zbkb/Zbc behavior.
2. Immediate expansion to other phases.

## Phased Plan (Red/Green)

### Phase 1.1 - Tests first

Red:
1. Add failing Zba spec covering `sh1add`, `sh2add`, `sh3add`.

Green:
1. Tests pass on both cores.

Exit Criteria:
1. Zba test passes single-cycle + pipelined.

### Phase 1.2 - Linux shell gate

Red:
1. Run Linux milestone/shell probe and capture failures if any.

Green:
1. Linux reaches shell and command round-trip succeeds.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zba op coverage test green for both cores.
2. Linux compile backend boots to shell.

## Risks and Mitigations

1. Risk: decode collisions with existing OP paths.
Mitigation: isolate funct7/funct3 matching and add explicit tests.

## Implementation Checklist

- [x] Add Zba failing tests.
- [x] Implement Zba decode/execute in single-cycle core.
- [x] Implement Zba decode/execute in pipelined core.
- [x] Run Zba tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zba_extension_spec.rb`
- Result: pass (`4 examples, 0 failures`) on single-cycle and pipeline harnesses.

2. Linux build/config gate:
- `JOBS=1 examples/riscv/build_linux.sh --no-clean --no-rootfs`
- Result: pass.
- `examples/riscv/software/bin/linux_kernel.config` includes `CONFIG_RISCV_ISA_ZBA=y`.
- `examples/riscv/software/bin/rhdl_riscv_virt.dts` includes `riscv,isa = \"rv32imafsu_zba_zicsr_zifencei\"`.

3. Linux shell gate:
- `bundle exec ruby /tmp/rhdl_shell_probe_quick.rb`
- Result: pass (`linux banner`, `init handoff`, `shell prompt`, and `echo RHDL_PROBE_OK` round-trip).
