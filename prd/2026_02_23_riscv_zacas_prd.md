# RISC-V Zacas Phase PRD

## Status

Completed (2026-02-23)

## Context

Enable Zacas compare-and-swap atomics on top of existing RV32A model.

## Goals

1. Add CAS decode/execute behavior in both cores.
2. Validate success/failure return semantics.
3. Preserve Linux shell boot.

## Non-Goals

1. Multi-hart memory ordering beyond current model.

## Phased Plan (Red/Green)

### Phase 6.1 - Zacas tests/implementation

Red:
1. Add failing CAS tests for success and failure cases.

Green:
1. Implement CAS path and pass on both cores.

Exit Criteria:
1. Zacas tests pass on both cores.

### Phase 6.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Zacas tests pass.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: CAS return-code mismatch.
Mitigation: assert architectural return semantics explicitly in tests.

## Implementation Checklist

- [x] Add Zacas failing tests.
- [x] Implement Zacas single-cycle + pipeline.
- [x] Run Zacas tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/zacas_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
