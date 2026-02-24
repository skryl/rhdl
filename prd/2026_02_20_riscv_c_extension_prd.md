# RISC-V C Extension (RV32C) for Basic + Pipelined Cores PRD

## Status

Proposed (2026-02-20)

## Context

Current RISC-V core work in this repo is centered on RV32I/RV32IMA compatibility, and Linux build defaults currently disable compressed instructions.
Both core implementations are in scope for parity:

- Single-cycle core path (`examples/riscv/hdl/cpu.rb`)
- Pipelined core path (`examples/riscv/hdl/pipeline/pipelined_cpu.rb`, `examples/riscv/hdl/pipeline/pipelined_datapath.rb`)

Adding `C` support improves code density, broadens binary compatibility, and reduces friction when running toolchains that default to compressed output.

## Goals

1. Implement architecturally correct RV32C behavior in both basic and pipelined cores.
2. Support mixed 16-bit and 32-bit instruction streams with consistent PC/trap semantics.
3. Keep `C` support configurable so existing non-`C` flows remain deterministic.
4. Add red/green regression coverage for compressed decode, control flow, and exceptions.

## Non-Goals

1. RV64C support.
2. Compressed floating-point instructions that require `F`/`D`.
3. Performance optimization beyond functional correctness.
4. Toolchain packaging/distribution work outside repo-local build/test flows.

## Phased Plan (Red/Green)

### Phase 0 - ISA Contract and Config Surface

- Red: add failing tests that assert current behavior rejects compressed opcodes when `C` is disabled.
- Red: add failing tests for feature toggle behavior in both harnesses.
- Green: add ISA/config toggle for `C` support and plumb it through single-cycle and pipelined runners.
- Green: expose clear user-facing mode/feature signaling (including explicit errors for invalid combinations).

Exit Criteria:

- `C` support can be enabled/disabled deterministically in both cores.
- Feature-toggle tests pass for both cores.

### Phase 1 - Single-Cycle Fetch/Decode + Execute

- Red: add failing single-cycle tests for `PC + 2` progression, mixed-width decode, and representative RV32C instruction execution.
- Green: implement variable-length fetch/decode and decompression path in single-cycle core.
- Green: ensure immediate/sign-extension and destination/source register mapping match RV32C spec behavior.

Exit Criteria:

- Single-cycle RV32C instruction tests pass.
- Mixed 16/32-bit stream tests pass without breaking existing RV32I tests.

### Phase 2 - Pipelined Fetch/Decode + Hazard Updates

- Red: add failing pipeline tests for compressed instruction fetch alignment, decode, and control hazard behavior.
- Red: add failing tests for load-use and forwarding interactions when instruction length varies.
- Green: update IF/ID and decode path to support variable-length instruction handling.
- Green: update hazard/flush/stall logic to preserve correctness across `PC + 2` and `PC + 4` transitions.

Exit Criteria:

- Pipelined RV32C path passes decode/control/hazard tests.
- No regressions in existing pipeline RV32I coverage.

### Phase 3 - Trap, Debug, and Control-Flow Correctness

- Red: add failing tests for branch/jump targets, exception `mepc`, and illegal compressed encodings.
- Green: implement trap PC capture and control-flow semantics for compressed instructions.
- Green: update debug/disassembly views where needed so instruction stepping remains coherent.

Exit Criteria:

- Trap/control-flow tests pass for compressed and mixed-width programs.
- Debug stepping and instruction reporting are consistent.

### Phase 4 - End-to-End Integration and Documentation

- Red: add failing integration specs that run compressed binaries on both cores.
- Green: wire integration paths in CLI/harness flows for `C`-enabled runs.
- Green: update docs for extension support, toggles, and limitations.

Exit Criteria:

- End-to-end compressed program runs are green for both cores.
- Documentation reflects behavior and configuration accurately.

## Acceptance Criteria

1. Both basic and pipelined cores execute RV32C instruction streams correctly.
2. Mixed 16/32-bit instruction sequences preserve architectural correctness.
3. Feature gating for `C` is deterministic and well-tested.
4. Existing RV32I/RV32IMA tests remain green.
5. Docs and help text reflect new `C` support behavior.

## Risks and Mitigations

1. Risk: variable-length fetch breaks PC/trap accounting.
Mitigation: add early failing tests for `mepc`, branch targets, and sequential stepping.

2. Risk: pipeline hazard logic regresses under mixed instruction lengths.
Mitigation: add focused stall/forward/flush tests before pipeline edits.

3. Risk: decode/decompression mismatches between cores.
Mitigation: share decode fixtures and parity tests across both implementations.

4. Risk: ambiguous feature-toggle behavior.
Mitigation: enforce explicit config defaults and error paths in CLI/harness.

## Implementation Checklist

- [ ] Phase 0: ISA contract and `C` config gate with failing-then-passing tests.
- [ ] Phase 1: Single-cycle RV32C fetch/decode/execute support.
- [ ] Phase 2: Pipelined RV32C fetch/decode/hazard support.
- [ ] Phase 3: Trap/debug/control-flow correctness for compressed instructions.
- [ ] Phase 4: End-to-end integration coverage and docs updates.

