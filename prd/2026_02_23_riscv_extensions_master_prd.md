# RISC-V Extension Bring-up Program (Z* + C + V) Master PRD

## Status

Completed (2026-02-23)

## Context

We need a deterministic, phase-by-phase implementation program for enabling additional RISC-V ISA extensions in this repo while preserving Linux bootability on the compile backend after each phase.

This program is ordered easiest-to-hardest:
1. Zba
2. Zbb
3. Zbkb
4. Zbc
5. Zawrs
6. Zacas
7. Zicbop
8. Zicboz
9. Zicbom
10. C
11. V

## Goals

1. Implement each extension phase in ordered sequence.
2. Keep single-cycle and pipelined cores functionally aligned.
3. Enforce Linux boot-to-shell as a hard gate after each phase.
4. Maintain deterministic CLI Linux defaults (`--linux`) and artifact paths.

## Non-Goals

1. SMP or multi-hart Linux support.
2. Full formal proof of extension semantics in this milestone.
3. Performance optimization beyond functional correctness.
4. Non-RISC-V subsystem redesign.

## Program Phases (Red/Green)

### Phase 0 - Program scaffolding and invariants

Red:
1. Capture baseline extension-off state for all targeted symbols.
2. Establish failing checks for missing per-phase PRDs and missing shell gate evidence.

Green:
1. Create all per-phase PRDs.
2. Define mandatory per-phase validation contract.

Exit Criteria:
1. All per-phase PRDs exist and are decision-complete.
2. Validation contract is explicit and repeatable.

### Phase 1..11 - Extension implementation phases

Each phase follows:

Red:
1. Add/adjust targeted extension tests that fail before implementation.
2. Add/adjust build/config checks for intended ISA/config changes.

Green:
1. Implement extension logic in single-cycle core.
2. Implement extension logic in pipelined core.
3. Update build/config defaults for the extension when intended.
4. Rebuild artifacts and run shell gate.

Exit Criteria (for every phase):
1. Extension targeted tests pass on single-cycle and pipelined harnesses.
2. Linux compile backend reaches shell and executes a command.
3. No panic/no-init/no-progress fail-fast markers appear.

## Per-Phase Mandatory Validation Gates

1. Extension-targeted spec(s) for single-cycle and pipelined cores.
2. `bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
3. `RHDL_LINUX_LIVE_UART=1 bundle exec rspec --tag slow spec/examples/riscv/linux_boot_milestones_spec.rb`
4. Shell probe command round-trip (`echo RHDL_PROBE_OK`) on `:compile` backend.

## Acceptance Criteria

1. All 11 phases are marked Completed in their own PRDs.
2. Linux boots to shell after each completed phase.
3. Single-cycle and pipelined extension tests are green for each phase.
4. CLI Linux default artifact contract remains valid.

## Risks and Mitigations

1. Risk: extension semantics cause regressions in boot path.
Mitigation: make shell gate mandatory after each phase.

2. Risk: single-cycle/pipeline drift.
Mitigation: pair each phase with parity-style dual-core tests.

3. Risk: phase coupling increases debug cost.
Mitigation: strict one-extension-at-a-time progression.

## Implementation Checklist

- [x] Phase 0: Program scaffolding PRDs created.
- [x] Phase 1: Zba complete + shell gate pass.
- [x] Phase 2: Zbb complete + shell gate pass.
- [x] Phase 3: Zbkb complete + shell gate pass.
- [x] Phase 4: Zbc complete + shell gate pass.
- [x] Phase 5: Zawrs complete + shell gate pass.
- [x] Phase 6: Zacas complete + shell gate pass.
- [x] Phase 7: Zicbop complete + shell gate pass.
- [x] Phase 8: Zicboz complete + shell gate pass.
- [x] Phase 9: Zicbom complete + shell gate pass.
- [x] Phase 10: C complete + shell gate pass.
- [x] Phase 11: V complete + shell gate pass.
