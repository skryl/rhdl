# RISC-V C Extension Phase PRD

## Status

Completed (2026-02-23)

## Context

Bring compressed instruction support to a Linux-boot-stable level after Z* phases.

## Goals

1. Complete required RV32C decode/decompress coverage for Linux/toolchain output.
2. Ensure single-cycle and pipeline control-flow/trap correctness with mixed-width streams.
3. Preserve Linux shell boot.

## Non-Goals

1. RV64C support.
2. Compression-performance tuning.

## Phased Plan (Red/Green)

### Phase 10.1 - C tests/implementation

Red:
1. Add failing mixed-width and illegal-encoding tests for unsupported C forms.

Green:
1. Extend compressed decoder and pass tests on both cores.

Exit Criteria:
1. C extension tests pass single-cycle + pipeline.

### Phase 10.2 - Linux shell gate

Red:
1. Run Linux shell gate and capture regressions.

Green:
1. Linux boot-to-shell remains green.

Exit Criteria:
1. Linux shell gate green.

## Acceptance Criteria

1. Mixed-width execution and trap semantics are stable on both cores.
2. Linux compile-backend shell boot passes.

## Risks and Mitigations

1. Risk: partial C coverage causes illegal-instruction traps during boot.
Mitigation: gate with Linux shell test and expand decoder only as needed.

## Implementation Checklist

- [x] Add/expand C failing tests.
- [x] Implement/extend C support single-cycle + pipeline.
- [x] Run C tests.
- [x] Run Linux shell gate.
- [x] Mark PRD complete.

## Validation Notes (2026-02-23)

1. Extension tests:
- `bundle exec rspec spec/examples/riscv/rv32c_compile_extension_spec.rb`
- Result: pass on single-cycle and pipeline harnesses.

2. Linux validation gates:
- `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
- Compile-backend shell probe: `echo RHDL_PROBE_OK` round-trip.
- Result: pass.
