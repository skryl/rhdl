# Status

In Progress - 2026-03-12

# Context

The Game Boy runtime currently exposes staged-vs-normalized imported Verilog selection only on the direct Verilator path, via `--mode verilog --verilog-dir ... --use-staged-verilog`.

That behavior is inconsistent in two ways:

1. The direct Verilator path defaults to normalized imported Verilog.
2. The Arcilator wrapper path rebuilds from staged imported Verilog by default and does not expose a normalized-source override.

This creates avoidable confusion. Users should be able to select the imported Verilog source boundary explicitly and consistently across both runtime backends, and they should also be able to explicitly force the runtime back onto the RHDL-exported source path when that is the comparison they want.

# Goals

1. Make imported Verilog execution default to staged imported Verilog.
2. Rename the user-facing flags to:
   - `--use-staged-source`
   - `--use-normalized-source`
3. Add:
   - `--use-rhdl-source`
4. Apply that contract consistently to:
   - direct Verilator imported-Verilog runs
   - imported Arcilator runs
   - RHDL-exported Verilator runs
   - RHDL-MLIR Arcilator runs
5. Preserve the existing handwritten HDL workflows.

# Non-Goals

1. Changing the importer source-top default for `bin/gb import`.
2. Changing the handwritten HDL default runtime flow.
3. Reworking the import artifact layout.
4. Generalizing this CLI contract to every example/system in this pass.

# Phased Plan

## Phase 1: Shared CLI and runner selection contract

### Red

1. Add failing CLI/task/headless-runner expectations for:
   - staged default on imported Verilog runs
   - explicit normalized override
   - explicit staged override for Arcilator

### Green

1. Add a shared runtime source-selection option that can represent:
   - `:staged`
   - `:normalized`
   - `:rhdl`
2. Wire the CLI flags to that shared option.
3. Keep the existing handwritten HDL path unchanged when no imported artifacts are involved.

### Exit Criteria

1. CLI/task/headless-runner tests prove the contract.
2. No ambiguity remains when both flags are absent.

## Phase 2: Verilator and Arcilator backend alignment

### Red

1. Add failing backend specs showing:
   - Verilator imported runs default to staged source selection.
   - Verilator normalized selection still works explicitly.
   - Arcilator wrapper mode can rebuild from normalized imported Verilog when requested.

### Green

1. Update `VerilogRunner` imported path selection to use staged by default.
2. Update `ArcilatorRunner` to select staged or normalized imported Verilog as the wrapper/core MLIR source boundary.
3. Add a RHDL-source mode for:
   - `VerilogRunner` via `to_verilog`
   - `ArcilatorRunner` via `to_mlir_hierarchy`
4. Keep raw-core fallback behavior valid when import reports are incomplete.

### Exit Criteria

1. Backend selection specs are green.
2. Both backends expose the same staged/normalized vocabulary.

## Phase 3: Sequential validation and command confirmation

### Red

1. Add or extend focused smoke checks proving the real CLI commands select the intended source boundary.

### Green

1. Run focused sequential specs.
2. Smoke-check:
   - Verilator staged default
   - Verilator normalized override
   - Arcilator staged default
   - Arcilator normalized override
   - Verilator RHDL-source mode
   - Arcilator RHDL-source mode where practical

### Exit Criteria

1. The documented commands match actual runtime behavior.

# Acceptance Criteria

1. `bin/gb --mode verilog` uses staged imported Verilog by default when running against imported artifacts.
2. `--use-staged-source` forces staged imported Verilog on both Verilator and Arcilator imported paths.
3. `--use-normalized-source` forces normalized imported Verilog on both Verilator and Arcilator imported paths.
4. `--use-rhdl-source` forces the RHDL-exported source path on both Verilator and Arcilator.
5. Handwritten HDL flows remain intact.

# Risks And Mitigations

1. Risk: imported `hdl_dir` Verilator runs currently resolve through raised RHDL rather than direct imported Verilog.
   Mitigation: explicitly detect imported trees and route source selection through import-report artifacts.

2. Risk: normalized imported Verilog may need different wrapper/source composition in Arcilator mode than staged imported Verilog.
   Mitigation: add focused backend specs for wrapper MLIR construction before changing the runtime build path.

3. Risk: CLI semantics become ambiguous if both staged and normalized flags are passed.
   Mitigation: reject conflicting flags up front.

# Implementation Checklist

- [x] Phase 1 red: add failing CLI/task/headless-runner selection tests
- [x] Phase 1 green: wire shared staged/normalized source-selection option
- [x] Phase 2 red: add failing Verilator/Arcilator backend selection tests
- [x] Phase 2 green: implement aligned backend behavior
- [x] Phase 3 red: add focused command-selection smoke checks
- [ ] Phase 3 green: run sequential validation and confirm commands for the imported-tree RHDL-source smoke paths
