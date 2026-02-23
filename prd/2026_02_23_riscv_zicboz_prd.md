# RISC-V Zicboz Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable cache-block zero operations with deterministic behavior in current memory model.

## Goals

1. Decode and execute block-zero behavior safely.
2. Validate correctness for supported address classes.
3. Preserve Linux shell boot.

## Non-Goals

1. Full cache hierarchy modeling.

## Phased Plan (Red/Green)

### Phase 8.1 - Zicboz tests/implementation

Red:
1. Add failing tests for block-zero decode and behavior.

Green:
1. Implement deterministic semantics and pass tests on both cores.

Exit Criteria:
1. Zicboz tests pass on both cores.

### Phase 8.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zicboz tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: alignment or permission handling errors.
Mitigation: include alignment/permission edge tests.

## Implementation Checklist

- [x] Add Zicboz failing tests.
- [x] Implement Zicboz single-cycle + pipeline.
- [x] Run Zicboz tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zicbo_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
