# 2026_03_04_dead_legacy_path_cleanup_prd

## Status
Proposed

## Context
Repository review identified remaining dead and legacy code paths after namespace and simulator migrations:
1. Live breakage from removed namespace usage:
   - `RHDL::Codegen::IR::IR_COMPILER_AVAILABLE` still referenced in active paths.
2. Dead/low-value compatibility shims still present:
   - `lib/rhdl/simulation.rb` redirect shim.
   - legacy `RHDL::HDL::Synth*` aliases.
   - unused compatibility helpers/aliases in behavior and MOS6502 register surfaces.
3. Verilog simulator backend surface advertises `:iverilog` paths that are intentionally unimplemented.
4. Existing API migration plan should not hard-remove `to_circt` / `to_circt_hierarchy`; instead, keep them and add/keep IR aliases.

User requirement update:
1. Do not rename/remove `to_circt` and `to_circt_hierarchy`.
2. Use alias-based compatibility for IR naming (`to_ir` and hierarchy alias per request).

## Goals
1. Fix all known live failures from legacy namespace references.
2. Remove dead or unreferenced legacy code paths where safe.
3. Keep CIRCT naming entrypoints (`to_circt`, `to_circt_hierarchy`) while exposing IR aliases.
4. Align backend/API surface with actual implemented behavior.
5. Add hygiene guardrails so removed legacy paths do not reappear.

## Non-goals
1. Changing simulation semantics/performance.
2. Rewriting example architectures or large runner interfaces.
3. Removing supported public APIs that are explicitly retained by request (`to_circt*`).

## Phased Plan

### Phase 1: Baseline + Red Gates
Red:
1. Add or update targeted checks/specs to fail on:
   - `RHDL::Codegen::IR` in active runtime code.
   - dead shim usage (`rhdl/simulation` require path).
   - removed compatibility constants once hard-cut is done.
2. Capture reproducible baseline failures for:
   - `bench:native[cpu8bit,*]`
   - `RHDL_ENABLE_ARCILATOR_GPU=1` parity spec path.

Green:
1. Baseline failure set is reproducible with deterministic commands.

Exit criteria:
1. Red checks fail for known broken legacy paths and no unrelated areas.

### Phase 2: Fix Live P0 Namespace Failures
Red:
1. Keep failing checks for `RHDL::Codegen::IR::IR_COMPILER_AVAILABLE`.

Green:
1. Replace runtime usage with canonical constant:
   - `RHDL::Sim::Native::IR::COMPILER_AVAILABLE`
2. Update affected spec(s) to same canonical constant.
3. Confirm unavailable compiler path yields `skip` behavior, not `NameError`.

Exit criteria:
1. `bundle exec rake "bench:native[cpu8bit,10]"` does not raise `NameError`.
2. `RHDL_ENABLE_ARCILATOR_GPU=1 bundle exec rspec spec/examples/8bit/hdl/cpu/arcilator_gpu_parity_spec.rb` no longer fails from missing constant.

### Phase 3: Dead Compatibility Path Cleanup
Red:
1. Add focused checks for unreferenced/deprecated shims targeted for removal.

Green:
1. Remove `lib/rhdl/simulation.rb` shim.
2. Remove unused synth alias constants in `lib/rhdl/synth.rb` (`RHDL::HDL::Synth*` family).
3. Remove unused behavior compatibility helper `evaluate_for_synthesis_flat`.
4. Remove unused MOS6502 aliases (`StackPointer6502`, `ProgramCounter6502`) if no active callsites remain.

Exit criteria:
1. No active code/spec/docs depend on removed shims/constants/helpers.
2. Relevant unit/integration specs remain green.

### Phase 4: CIRCT/IR API Alias Policy (Keep `to_circt*`)
Red:
1. Add/adjust API specs to lock desired alias policy:
   - `to_circt` remains available.
   - `to_circt_hierarchy` remains available.
   - IR-named aliases are available as requested (`to_ir`, hierarchy alias).

Green:
1. Keep existing `to_circt` and `to_circt_hierarchy` methods.
2. Ensure IR aliases are present and tested:
   - `to_ir` (single module path).
   - hierarchy alias per requested naming (`to_ir_heirarchy`), with canonical wiring to hierarchy IR generation.
3. Update docs to describe both naming styles and preferred usage.

Exit criteria:
1. No forced callsite rename away from `to_circt*`.
2. API specs pass for both CIRCT-named and IR-named entrypoints.

### Phase 5: Verilog Backend Surface Alignment
Red:
1. Add checks to detect unsupported pseudo-backends still exposed in runtime dispatch.

Green:
1. Remove `:iverilog` branches that only raise `NotImplementedError` from Verilog simulator runtime manager.
2. Keep backend validation/messages aligned with actually implemented backend(s).

Exit criteria:
1. Runtime backend dispatch only includes implemented backends.
2. Verilator-backed runner specs remain green.

### Phase 6: Hygiene Guardrails + Validation
Red:
1. Extend hygiene checks/specs to fail on reintroduced legacy symbols and removed shims.

Green:
1. Update `hygiene_task` forbidden patterns for:
   - `RHDL::Codegen::IR`
   - `require 'rhdl/simulation'`
   - removed synth alias constants
2. Keep exclusions for vendor/submodule/generated trees unchanged.
3. Run targeted then broad validation gates.

Exit criteria:
1. `bundle exec rake hygiene:check` passes.
2. Targeted specs for touched areas pass.
3. Fast suite passes under current AO486 import exclusion policy.

## Acceptance Criteria
1. No active runtime path references `RHDL::Codegen::IR::IR_COMPILER_AVAILABLE`.
2. `bench:native[cpu8bit,*]` runs without legacy namespace crashes.
3. `RHDL_ENABLE_ARCILATOR_GPU=1` parity path no longer fails on missing constants.
4. `lib/rhdl/simulation.rb` is removed and no active code requires it.
5. Unused `RHDL::HDL::Synth*` alias constants are removed.
6. `evaluate_for_synthesis_flat` and unused MOS6502 aliases are removed unless proven needed by active callsites.
7. `to_circt` and `to_circt_hierarchy` remain available.
8. IR aliases are available and tested (`to_ir`, hierarchy alias as requested).
9. Verilog simulator dispatch reflects only implemented backends.
10. Hygiene/task/spec gates pass for touched surfaces.

## Risks and Mitigations
1. Risk: Removing compatibility shims breaks external/private downstream scripts.
   Mitigation: enforce in-repo callsite grep before removal and document removals in changelog/PR notes.
2. Risk: hierarchy alias naming mismatch (`hierarchy` vs requested `heirarchy`) causes confusion.
   Mitigation: codify exact accepted alias names in specs and docs in Phase 4.
3. Risk: over-broad hygiene regexes produce false positives in fixtures/vendor trees.
   Mitigation: keep explicit scan exclusions and verify with hygiene task specs.
4. Risk: backend surface cleanup changes user expectations.
   Mitigation: keep CLI/help/docs explicit about implemented backends only.

## Implementation Checklist
- [ ] Phase 1: Baseline failure reproduction and red gates added.
- [ ] Phase 2: P0 namespace breakages fixed (`Codegen::IR` usage removed).
- [ ] Phase 3: Dead compatibility shims/helpers/aliases removed.
- [ ] Phase 4: `to_circt*` retained and IR aliases locked via specs/docs.
- [ ] Phase 5: Verilog backend surface aligned to implemented backends.
- [ ] Phase 6: Hygiene guardrails updated and full validation completed.
