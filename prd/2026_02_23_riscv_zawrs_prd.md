# RISC-V Zawrs Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zawrs (`wrs.*`) semantics compatible with current LR/SC reservation model.

## Goals

1. Decode and execute `wrs.nto`/`wrs.sto` behavior for single-hart model.
2. Validate no deadlock or illegal trap regressions.
3. Preserve Linux shell boot.

## Non-Goals

1. Multi-hart wakeup fairness/performance guarantees.

## Phased Plan (Red/Green)

### Phase 5.1 - Zawrs tests/implementation

Red:
1. Add failing tests for `wrs.*` decode and reservation interactions.

Green:
1. Implement deterministic semantics and pass tests on both cores.

Exit Criteria:
1. Zawrs tests pass on both cores.

### Phase 5.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zawrs tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: wait semantics stall pipeline indefinitely.
Mitigation: enforce deterministic bounded behavior in single-hart model.

## Implementation Checklist

- [x] Add Zawrs failing tests.
- [x] Implement Zawrs single-cycle + pipeline.
- [x] Run Zawrs tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zawrs_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
