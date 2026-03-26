# Test Suite Failure Remediation PRD

**Status:** In Progress
**Date:** 2026-03-13

## Context

A full test suite run across all 8 scopes revealed 254 failures grouped into 10 distinct failure families. Two scopes (hdl, mos6502) are fully green. Six scopes have failures that trace back to a small number of root causes.

## Goals

- Fix all 254 test failures across the 6 affected scopes.
- Do not break currently passing tests.

## Non-Goals

- Performance optimization.
- New feature work.
- Fixing pending/skipped tests.

## Failure Families

### Family 1: IR Compiler Codegen — wrong argument count (~177 failures)
- **Scopes:** lib (22), gameboy (155)
- **Root cause:** Generated Rust calls `evaluate_inline(signals)` but the function signature now requires 3 args (`signals`, `wide_hi`, `overwide_ptrs`).
- **Key files:** IR compiler codegen (likely `lib/rhdl/sim/native/ir/` Rust template generation)
- **Failing specs:**
  - `spec/rhdl/sim/native/ir/ir_compiler_vcd_spec.rb` (22 failures)
  - `spec/examples/gameboy/hdl/cpu/sm83_spec.rb` (149 failures)
  - `spec/examples/gameboy/utilities/cli_spec.rb` (6 failures, IR compile backend)

### Family 2: ao486 SystemStackError in `strip_trailing_loc` (35 failures)
- **Scopes:** ao486
- **Root cause:** Infinite recursion in `lib/rhdl/codegen/circt/import.rb:3897` — regex in `strip_trailing_loc` triggers deep recursive resolution chains via `normalize_value_token` → `lookup_value` → recursive `resolve_llhd_stop_env`/`resolve_llhd_branch_stop_env`.
- **Failing specs:**
  - `spec/examples/ao486/import/cpu_importer_spec.rb` (3 failures)
  - 16 unit specs under `spec/examples/ao486/import/unit/ao486/` (32 failures)

### Family 3: ao486 Compilation failed — fast path blocker (10 failures)
- **Scopes:** ao486
- **Root cause:** `RuntimeError: compiled fast path requires runtime fallback for combinational assigns`. Design too complex for compiler fast path.
- **Failing specs:**
  - `spec/examples/ao486/hdl/cpu_parity_package_spec.rb` (1)
  - `spec/examples/ao486/hdl/cpu_parity_runtime_spec.rb` (4)
  - `spec/examples/ao486/hdl/cpu_parity_verilator_runtime_spec.rb` (4)
  - `spec/examples/ao486/hdl/cpu_trace_package_spec.rb` (1)

### Family 4: CIRCT assign preservation — extra `[:signal, N]` element (7 failures)
- **Scopes:** lib
- **Root cause:** Roundtrip assigns return an unexpected extra signal element at the beginning of the array.
- **Failing specs:**
  - `spec/rhdl/codegen/circt/assign_preservation_spec.rb` (7 failures)

### Family 5: Gameboy speedcontrol clock logic (5 failures)
- **Scopes:** gameboy
- **Root cause:** Clock enable/divider outputs always 1 instead of expected phase patterns.
- **Failing specs:**
  - `spec/examples/gameboy/hdl/speedcontrol_spec.rb` (5 failures)

### Family 6: Apple2 arcilator runner (3 failures)
- **Scopes:** apple2
- **Root cause:** `ArgumentError: wrong number of arguments (given 0, expected 1)` in `compile_arcilator` at `arcilator_runner.rb:392`, plus nil RAM read in render spec.
- **Failing specs:**
  - `spec/examples/apple2/runners/arcilator_runner_build_spec.rb` (2 failures)
  - `spec/examples/apple2/runners/arcilator_runner_render_spec.rb` (1 failure)

### Family 7: Apple2 IR timeout (2 failures)
- **Scopes:** apple2
- **Root cause:** IR simulator compilation and JIT backend exceed test timeouts (10s/60s).
- **Failing specs:**
  - `spec/examples/apple2/hdl/apple2_spec.rb` (2 failures)

### Family 8: Sparc64 timeout in `apply_patch_file!` (3 failures)
- **Scopes:** sparc64
- **Root cause:** `Timeout::Error` during `run_command` in `system_importer.rb` when staging source bundles.
- **Failing specs:**
  - `spec/examples/sparc64/import/system_importer_spec.rb` (3 failures)

### Family 9: ao486 Verilog tree strategy syntax error (2 failures)
- **Scopes:** ao486
- **Root cause:** Generated `import_all.tree.sv` has invalid `reg in_reset = 1;` syntax.
- **Failing specs:**
  - `spec/examples/ao486/import/system_importer_spec.rb` (2 failures)

### Family 10: Miscellaneous one-offs (5 failures)
- **lib** (4):
  - `spec/rhdl/codegen/circt/api_spec.rb` — array signal rewrite (1), backedge state (1)
  - `spec/rhdl/codegen/circt/import_cleanup_spec.rb` — seq.firmem preservation (1)
  - `spec/rhdl/sim/native/ir/simulator_load_spec.rb` — missing expected RuntimeError (1)
- **riscv** (1):
  - `spec/examples/riscv/zawrs_extension_spec.rb` — wrs.nto/wrs.sto triggers illegal-instruction trap

## Phased Plan

### Phase 1: Family 1 — IR Compiler Codegen (highest impact, ~177 failures)
1. Red: Confirm `ir_compiler_vcd_spec.rb` fails with argument mismatch.
2. Green: Update Rust codegen template to pass all 3 required args to `evaluate_inline`.
3. Verify: `spec[lib]` IR compiler specs + `spec[gameboy]` sm83 + cli specs go green.

### Phase 2: Family 2 — ao486 stack overflow (35 failures)
1. Red: Confirm `cpu_importer_spec.rb` fails with SystemStackError.
2. Green: Break recursion cycle in `strip_trailing_loc` / resolution chain.
3. Verify: ao486 import specs go green.

### Phase 3: Family 3 — ao486 fast path blocker (10 failures)
1. Red: Confirm parity specs fail with RuntimeError.
2. Green: Either extend fast path to handle the combinational assigns or add fallback.
3. Verify: ao486 parity/trace specs go green.

### Phase 4: Family 4 — Assign preservation (7 failures)
1. Red: Confirm assign_preservation_spec fails.
2. Green: Fix roundtrip to not prepend extra `[:signal, N]`.
3. Verify: assign_preservation_spec goes green.

### Phase 5: Family 5 — Speedcontrol (5 failures)
1. Red: Confirm speedcontrol_spec fails.
2. Green: Fix clock enable/divider logic.
3. Verify: speedcontrol_spec goes green.

### Phase 6: Family 6 — Arcilator runner (3 failures)
1. Red: Confirm arcilator_runner_build_spec fails.
2. Green: Fix `compile_arcilator` argument and nil RAM read.
3. Verify: arcilator specs go green.

### Phase 7: Families 7-10 — Timeouts and one-offs (12 failures)
1. Investigate and fix timeout thresholds or underlying slowness.
2. Fix ao486 tree strategy Verilog syntax.
3. Fix misc one-offs (api_spec, import_cleanup_spec, simulator_load_spec, zawrs).
4. Verify each fix individually.

## Exit Criteria

- All 254 failures resolved.
- No regressions in currently passing scopes (hdl, mos6502).

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| IR codegen fix breaks other backends | Run full lib + gameboy suites after change |
| ao486 recursion fix changes import semantics | Verify all ao486 import specs, not just previously failing ones |
| Fast path changes affect other architectures | Run mos6502 + riscv as regression check |
| Timeout fixes are environment-dependent | Increase timeouts conservatively; verify on CI |

## Implementation Checklist

- [ ] Family 1: IR compiler codegen arg mismatch
- [ ] Family 2: ao486 stack overflow in strip_trailing_loc
- [ ] Family 3: ao486 fast path blocker
- [ ] Family 4: CIRCT assign preservation
- [ ] Family 5: Gameboy speedcontrol
- [ ] Family 6: Apple2 arcilator runner
- [ ] Family 7: Apple2 IR timeout
- [ ] Family 8: Sparc64 timeout
- [ ] Family 9: ao486 Verilog tree strategy
- [ ] Family 10: Miscellaneous one-offs
