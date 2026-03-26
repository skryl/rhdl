# AO486 CLI And Display Alignment PRD

## Status
- Proposed: 2026-03-11
- In Progress: 2026-03-11
- Completed: 2026-03-11

## Context
- The AO486 example runner exposes backend-oriented run flags (`--mode ir|verilator|arcilator`) that do not match the public mode vocabulary used by the RISC-V runner (`ir`, `verilog`, `circt`).
- The AO486 run CLI is also missing the short `-s` speed flag that exists on the RISC-V binary.
- AO486 text/debug rendering uses a simpler display/debug presentation than the boxed debug panel used by the RISC-V runner.
- AO486 non-headless execution was still one-shot, so `bin/ao486 ... -s ...` exited after the first backend chunk instead of behaving like the RISC-V interactive runner.

## Goals
- Add `-s` as a short alias for AO486 speed control.
- Align AO486 public run-mode names with the RISC-V runner surface.
- Keep existing AO486 backend aliases working for compatibility.
- Make AO486 debug/display rendering match the RISC-V boxed-panel style.
- Make non-headless AO486 execution own the interactive loop so `--speed` behaves as per-frame chunk size instead of a single-run limit.

## Non-goals
- Add new AO486 simulation backends beyond the existing IR/Verilator/Arcilator implementations.
- Rework AO486 runtime internals outside CLI mode normalization and display/debug presentation.
- Change import/parity/verify subcommand semantics.

## Phased plan

### Phase 1 (Red)
- Capture current AO486 CLI and display adapter contract.
- Identify public help/spec/doc surfaces that must change together.

### Phase 2 (Green)
- Update `examples/ao486/utilities/cli.rb`:
  - add `-m`
  - add `-s`
  - normalize public modes to `ir`, `verilog`, `circt`
  - preserve `verilator` / `arcilator` aliases
- Update `examples/ao486/utilities/runners/headless_runner.rb` to resolve canonical modes onto existing concrete runners.

### Phase 3 (Green)
- Update `examples/ao486/utilities/display_adapter.rb` and AO486 runner rendering to emit a boxed debug panel matching the RISC-V presentation style.
- Adjust AO486 debug line formatting to use the aligned display contract.

### Phase 4 (Green)
- Update CLI/docs/spec text that documents the AO486 public interface.

### Phase 5 (Green)
- Move interactive loop ownership into `examples/ao486/utilities/runners/headless_runner.rb`.
- Keep concrete AO486 backend runners finite-chunk so `--speed` remains a per-frame/per-chunk budget.

## Exit criteria
- `bin/ao486` accepts `-s`.
- AO486 public run mode help and parsing accept `ir`, `verilog`, and `circt`.
- Existing `verilator` / `arcilator` callers still work.
- AO486 debug rendering uses a boxed panel instead of the old dashed footer format.
- `bin/ao486 --mode verilog --bios --dos -d -s 10000` stays interactive instead of exiting after launch.

## Acceptance criteria
- AO486 CLI help, README, and CLI docs describe the same public run contract.
- AO486 runner mode normalization routes canonical modes to the existing concrete runner implementations.
- AO486 display/debug output matches the RISC-V-style boxed panel layout.
- AO486 interactive mode repeatedly executes backend chunks until interrupted, while omitted `--cycles` / `--speed` remain unbounded.

## Risks and mitigations
- Risk: direct AO486 callers may still pass old mode names.
  - Mitigation: keep old names as aliases and only canonicalize the public CLI help/output.
- Risk: display formatting changes could break existing AO486 integration expectations.
  - Mitigation: update AO486 integration specs alongside the renderer contract.

## Implementation checklist
- [x] Create PRD for AO486 CLI/display alignment.
- [x] Add AO486 `-s` and aligned `-m` parsing with compatibility aliases.
- [x] Canonicalize AO486 public modes onto existing runner backends.
- [x] Switch AO486 debug rendering to RISC-V-style boxed panel output.
- [x] Update README / CLI docs / specs to the new public contract.
- [x] Keep AO486 interactive mode alive across repeated backend chunks.
