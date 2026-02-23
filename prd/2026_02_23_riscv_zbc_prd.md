# RISC-V Zbc Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zbc (carry-less multiply subset) after Zbkb.

## Goals

1. Implement `clmul` family operations in both cores.
2. Validate deterministic results with known vectors.
3. Preserve Linux shell boot.

## Non-Goals

1. Broader crypto extension set outside Zbc.

## Phased Plan (Red/Green)

### Phase 4.1 - Zbc tests/implementation

Red:
1. Add failing tests for `clmul`, `clmulh`, `clmulr`.

Green:
1. Implement and validate on both cores.

Exit Criteria:
1. Zbc tests pass on both cores.

### Phase 4.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zbc tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: polynomial multiply implementation errors.
Mitigation: cross-check against reference software model in tests.

## Implementation Checklist

- [x] Add Zbc failing tests.
- [x] Implement Zbc single-cycle + pipeline.
- [x] Run Zbc tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zbc_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
