## Status

In Progress - March 5, 2026
Phase 1 completed - March 5, 2026
Phase 2 in progress - imported-core cleanup and workspace artifact mirroring landed - March 5, 2026
Phase 2 telemetry update - mixed import now reports timed phase boundaries and fails fast on imported-core cleanup instead of appearing hung - March 5, 2026
Phase 2 cleanup update - selective LLHD module cleanup and canonical firtool export now work on full GameBoy mixed import artifacts; remaining blocker is strict full-design CIRCT->RHDL import/raise performance on array-heavy cleaned core MLIR - March 5, 2026
Phase 2 raise stabilization update - shared-subexpression hoisting in behavior and sequential emission eliminated the GameBoy CIRCT->RHDL raise blowups; the real mixed importer path now completes again with 77 raised files and green GameBoy import coverage specs - March 5, 2026
Phase 2 runtime export update - mixed import now preserves the raw `firtool` Verilog artifact separately and overlays only true generated-VHDL memory modules onto the canonical runtime Verilog artifact so Verilator can compile the imported GameBoy design again without losing the raw exported comparison artifact - March 6, 2026
Phase 2 runtime artifact update - mixed import now emits and mirrors a cached `runtime_json_path` artifact derived from the imported CIRCT core package so imported GameBoy runtime specs can reuse the flattened CIRCT runtime payload instead of reparsing MLIR every time - March 6, 2026

## Context

The current Verilog import path still routes through `circt-translate --import-verilog`, Moore, and the downstream LLHD/core path. That has forced a growing stack of ARC-specific rewrites, LLHD probing, compat fallback logic, and example-specific import workarounds.

That is the wrong architectural center for the runtime split we want:

`Mixed HDL -> GHDL -> Pure Verilog -> circt-verilog -> CIRCT core IR ->`
- `firtool --verilog` for Verilator
- core-to-ARC lowering for Arcilator
- direct CIRCT-to-RHDL raising for RHDL

This PRD hard-cuts the import flow to that pipeline and removes the Moore/LLHD rewrite stack for ARC.

## Goals

1. Make `circt-verilog` the only Verilog import frontend.
2. Make CIRCT core IR the canonical imported representation for Verilator, Arcilator, and RHDL.
3. Replace the current rewrite-heavy ARC preparation flow with a single structural import path.
4. Make runtime Verilog come from `firtool --verilog` on imported core IR.
5. Remove import-time flags and metadata tied to LLHD time elimination workarounds.

## Non-Goals

1. Preserving the `circt-translate` import path as a fallback.
2. Preserving `--arc-remove-llhd` or any LLHD/Moore-specific ARC workaround path.
3. Preserving example-specific compat import retries or synthetic compat Verilog modules.
4. Solving every possible frontend limitation in `circt-verilog` with ad hoc rewrites.

## Phased Plan

### Phase 1: Frontend And CLI Hard Cut

#### Red

1. Add or update tooling and CLI specs to fail until:
   - Verilog import invokes `circt-verilog`, not `circt-translate`
   - `rhdl import --help` no longer advertises import `--tool`
   - `rhdl import --help` no longer advertises `--[no-]arc-remove-llhd`
2. Add a dependency check covering required `circt-verilog` availability.

#### Green

1. Replace the import command builder with a `circt-verilog` frontend wrapper.
2. Remove the import CLI tool-selection flag.
3. Remove the ARC LLHD flag surface from the CLI and task layer.
4. Add `circt-verilog` to dependency/docs checks as a required tool.

#### Exit Criteria

1. Import CLI no longer exposes Moore/LLHD tool selection or ARC rewrite flags.
2. The only Verilog import frontend path in shared tooling is `circt-verilog`.

### Phase 2: Canonical Import Artifacts

#### Red

1. Add failing task/importer specs that require import reports to expose:
   - `pure_verilog_root`
   - `pure_verilog_entry_path`
   - `core_mlir_path`
   - `normalized_verilog_path`
2. Add failing checks that no report metadata references `.arc_remove_llhd`, runtime rewrite staging, or LLHD probe outputs.

#### Green

1. Make mixed import produce the four canonical artifacts.
2. Preserve directory structure in the staged pure-Verilog tree.
3. Normalize imported `circt-verilog --ir-hw` output to pure core MLIR before `firtool` export when LLHD signal/time overlays survive the frontend.
4. Emit normalized runtime Verilog from the cleaned imported core IR with `firtool --verilog`.
5. Raise RHDL from `core_mlir_path`, not from re-imported emitted Verilog.
6. Mirror the cleaned core MLIR and canonical Verilog into the example importer workspace for parity/debug workflows.

#### Exit Criteria

1. Import reports expose only the new canonical artifact model for this flow.
2. Runtime Verilog and RHDL raising both derive from the same imported core IR lineage.

### Phase 3: Remove Rewrite And Compat Layers

#### Red

1. Add failing specs that assert:
   - no `.arc_remove_llhd` staging tree is created
   - no compat fallback path is attempted
   - no synthetic compat modules such as `spram_compat` or `dpram_compat` are emitted
2. Add failing search-based regression checks for the removed flags and helper paths in touched areas.

#### Green

1. Delete the ARC LLHD rewrite/probe stack.
2. Delete the mixed import compat fallback logic.
3. Delete Verilog-side semantic rewrite helpers that only existed to support the old ARC path.
4. Keep only minimal source hygiene required for GHDL VHDL analysis/synthesis.

#### Exit Criteria

1. The old ARC elimination path is gone from CLI, shared tasks, and example importers.
2. Mixed import no longer depends on compat retry strategies or replacement Verilog modules.

### Phase 4: Runtime Consumer Cutover

#### Red

1. Add or update integration specs so they fail until:
   - Verilator consumes `normalized_verilog_path`
   - Arcilator consumes ARC lowered from `core_mlir_path`
   - RHDL backends consume RHDL raised from the same `core_mlir_path`
2. Add failing GameBoy and ao486 import/runtime checks for the shared artifact ownership.

#### Green

1. Rewire GameBoy and ao486 importer/runtime helpers to the new artifact model.
2. Remove spec-local or example-local ARC preparation that depends on Moore/LLHD.
3. Ensure the three downstream consumers branch from the same imported core IR.

#### Exit Criteria

1. Verilator, Arcilator, and RHDL are all sourced from one canonical import lineage.
2. Runtime/import specs no longer exercise Moore/LLHD ARC preparation.

### Phase 5: Regression Gates And Documentation

#### Red

1. Run targeted unit, integration, and example import specs.
2. Run the relevant import/runtime smoke checks for GameBoy and ao486.

#### Green

1. Update touched docs and help text to match the hard cut.
2. Update this PRD checklist and status as phases land.
3. Record any remaining frontend limitations as `circt-verilog` blockers, not rewrite TODOs.

#### Exit Criteria

1. Touched tests are green.
2. Docs and CLI help match the new import contract.
3. This PRD is the sole active ARC-import migration plan for this work.

## Acceptance Criteria

1. `rhdl import` uses `circt-verilog` as the only Verilog import frontend.
2. Import reports expose canonical pure-Verilog, core-MLIR, and normalized-Verilog artifacts.
3. Verilator consumes normalized Verilog emitted from imported core IR.
4. Arcilator consumes ARC derived from imported core IR without Moore/LLHD staging.
5. RHDL raises directly from imported core IR.
6. The `--tool` and `--arc-remove-llhd` import surfaces are removed.
7. The old ARC LLHD rewrite/probe path and compat import path are removed from the codebase.

## Risks And Mitigations

1. `circt-verilog` may not support all imported constructs yet.
   - Mitigation: treat failures as frontend blockers, capture them in focused specs, and do not reintroduce rewrite fallbacks.
2. Exported normalized Verilog may not initially match current runtime expectations.
   - Mitigation: lock the consumer contract with targeted runtime integration specs before broadening scope.
3. Removing compat logic may expose hidden dependencies in example systems.
   - Mitigation: migrate GameBoy and ao486 explicitly and run their import/runtime gates before calling the phase complete.

## Implementation Checklist

- [x] Phase 1: Frontend And CLI Hard Cut
- [ ] Phase 2: Canonical Import Artifacts
- [ ] Phase 3: Remove Rewrite And Compat Layers
- [ ] Phase 4: Runtime Consumer Cutover
- [ ] Phase 5: Regression Gates And Documentation
