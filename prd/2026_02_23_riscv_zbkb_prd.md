# RISC-V Zbkb Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zbkb crypto-oriented bit-manip subset incrementally after Zbb.

## Goals

1. Implement selected Zbkb operations needed for compatibility.
2. Validate on both cores.
3. Preserve Linux shell boot.

## Non-Goals

1. Full cryptography extension family beyond Zbkb.

## Phased Plan (Red/Green)

### Phase 3.1 - Zbkb tests/implementation

Red:
1. Add failing tests for chosen Zbkb ops (phase-scoped subset).

Green:
1. Implement decode/ALU behavior and pass tests on both cores.

Exit Criteria:
1. Zbkb subset tests pass on both cores.

### Phase 3.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zbkb phase tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: bit permutation corner-case bugs.
Mitigation: add fixed test vectors for each opcode.

## Implementation Checklist

- [x] Add Zbkb failing tests.
- [x] Implement Zbkb single-cycle + pipeline.
- [x] Run Zbkb tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zbkb_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
