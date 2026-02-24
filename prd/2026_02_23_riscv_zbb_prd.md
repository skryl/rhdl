# RISC-V Zbb Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zbb (basic bit-manipulation subset) after Zba, preserving Linux shell boot.

## Goals

1. Implement selected Zbb operations used by baseline toolchains/workloads.
2. Add single-cycle + pipelined tests.
3. Keep Linux shell gate green.

## Non-Goals

1. Zbkb/Zbc semantics beyond this phase.

## Phased Plan (Red/Green)

### Phase 2.1 - Zbb tests and implementation

Red:
1. Add failing tests for selected ops (`andn`, `orn`, `xnor`, `min/max`, `minu/maxu`).

Green:
1. Implement decode/ALU behavior and pass tests on both cores.

Exit Criteria:
1. Zbb tests pass on both cores.

### Phase 2.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zbb selected-op tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: signed/unsigned comparison mistakes.
Mitigation: include signed/unsigned edge-case vectors.

## Implementation Checklist

- [x] Add Zbb failing tests.
- [x] Implement Zbb single-cycle + pipeline.
- [x] Run Zbb tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zbb_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
