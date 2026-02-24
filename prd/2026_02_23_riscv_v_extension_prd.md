# RISC-V V Extension Phase PRD

## Status

Completed (2026-02-23)

## Context

Finalize/expand vector support after C phase, preserving Linux shell stability.

## Goals

1. Bring vector subset to phase-defined completeness for both cores.
2. Validate vector state/control/ALU/memory behavior in scoped profile.
3. Preserve Linux shell boot.

## Non-Goals

1. Full RVV instruction-space coverage in one phase.
2. Vector performance optimization.

## Phased Plan (Red/Green)

### Phase 11.1 - V tests/implementation

Red:
1. Add failing tests for targeted vector subset completeness gaps.

Green:
1. Implement missing vector behavior and pass tests on both cores.

Exit Criteria:
1. V phase tests pass single-cycle + pipeline.

### Phase 11.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Scoped V phase tests pass on both cores.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: vector control/hazard interactions regress scalar behavior.
Mitigation: add mixed scalar/vector regression tests before phase completion.

## Implementation Checklist

- [x] Add/expand V failing tests.
- [x] Implement/extend V single-cycle + pipeline.
- [x] Run V tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/rvv_compile_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
