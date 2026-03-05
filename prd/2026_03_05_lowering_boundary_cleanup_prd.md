# Lowering Boundary Cleanup PRD

## Status
Completed (2026-03-05)

## Context
`ArcToGpuLowering` had become a mixed frontend/backend entrypoint, with `SynthToGpuLowering` and `GemToGpuLowering` routing through Arc-specific options. This obscured ownership boundaries and made feature gating (for example GEM interpreter mode) harder to reason about.

## Goals
- Keep `ArcToGpuLowering` as the ARC-IR frontend entrypoint.
- Keep `SynthToGpuLowering` as the synth/hw IR frontend entrypoint.
- Keep `GemToGpuLowering` as the AIG-oriented frontend entrypoint.
- Share common GPU lowering mechanics via a dedicated delegate.

## Non-Goals
- Rewrite kernel generation internals.
- Change runtime behavior/perf policy outside frontend ownership boundaries.

## Phased Plan
### Phase 1: Introduce shared delegate
Red:
- Existing lowering specs fail if delegate does not preserve metadata/output contracts.
Green:
- Add `GpuLoweringDelegate` for shared parse/validate/emit/metadata flow.
- Keep existing Arc/Synth/GEM output format unchanged.
Exit Criteria:
- Arc/Synth/GEM lowering specs pass.

### Phase 2: ARC frontend boundary
Red:
- Arc entrypoint accepts non-ARC frontend options.
Green:
- Restrict `ArcToGpuLowering.lower` to ARC-facing API and route through delegate with ARC parser semantics.
Exit Criteria:
- Arc lowering specs pass and enforce ARC requirements.

### Phase 3: Synth and GEM frontend boundaries
Red:
- Synth frontend accepts ARC wrappers; GEM frontend path naming remains synth-generic.
Green:
- `SynthToGpuLowering` uses delegate with synth parser guard.
- `GemToGpuLowering` takes AIG-oriented input key (`aig_mlir_path`) while retaining legacy compatibility.
- Update runner callsites to use AIG-oriented key.
Exit Criteria:
- Synth/GEM specs pass, runner specs pass.

## Acceptance Criteria
- Distinct frontend ownership:
  - Arc -> ARC input contract
  - Synth -> synth/hw input contract
  - Gem -> AIG input contract
- Shared backend mechanics live in delegate.
- All touched specs green.

## Risks and Mitigations
- Risk: subtle metadata drift during delegate extraction.
  - Mitigation: preserve existing field layout and verify via existing specs.
- Risk: break legacy callers for GEM input key.
  - Mitigation: keep `synth_mlir_path` compatibility alias and add test.

## Implementation Checklist
- [x] Add `GpuLoweringDelegate`.
- [x] Refactor `ArcToGpuLowering.lower` to ARC-only entry semantics.
- [x] Refactor `SynthToGpuLowering` to synth-owned parsing and delegate usage.
- [x] Refactor `GemToGpuLowering` to AIG-owned entry semantics (+ compatibility alias).
- [x] Update runner callsites to `aig_mlir_path`.
- [x] Add/adjust specs for new boundaries.
- [x] Run targeted lowering and runner specs.
