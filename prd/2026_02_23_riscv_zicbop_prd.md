# RISC-V Zicbop Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable cache-block prefetch operations with safe behavior in current memory model.

## Goals

1. Decode/execute prefetch instructions without illegal traps.
2. Preserve functional memory behavior.
3. Preserve Linux shell boot.

## Non-Goals

1. Microarchitectural prefetch performance modeling.

## Phased Plan (Red/Green)

### Phase 7.1 - Zicbop tests/implementation

Red:
1. Add failing decode/behavior tests for prefetch instructions.

Green:
1. Implement safe semantics and pass tests on both cores.

Exit Criteria:
1. Zicbop tests pass on both cores.

### Phase 7.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zicbop tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: unintended memory side-effects.
Mitigation: keep semantics side-effect-safe for current model and test explicitly.

## Implementation Checklist

- [x] Add Zicbop failing tests.
- [x] Implement Zicbop single-cycle + pipeline.
- [x] Run Zicbop tests.
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
