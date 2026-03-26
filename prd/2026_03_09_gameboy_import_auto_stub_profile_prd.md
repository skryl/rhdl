# Status

Completed - March 9, 2026

## Context

The Game Boy importer already supports explicit `stub_modules`, and the runtime parity work has proven that a small subset of wrapper-disabled subsystems can be stubbed without changing normal simulation behavior:

1. `gb_savestates`
2. `gb_statemanager__vhdl_2e2d161b9c1b`
3. `sprites_extra`

Right now that knowledge lives in spec-local wiring. The importer itself does not expose a named, reusable auto-stub mode for simulation-oriented imports, which keeps the parity path fragile and duplicative.

## Goals

1. Add a Game Boy importer auto-stub mode for the known simulation-safe stub set.
2. Keep the raw import flow available for strict import/unit-equivalence workflows.
3. Switch the heavy Game Boy parity specs to use the importer-level auto-stub mode instead of local stub lists.
4. Expose the mode through the Game Boy import CLI/docs.

## Non-Goals

1. Making all Game Boy imports stubbed by default.
2. Expanding the safe set beyond the wrapper-disabled subsystems in this change.
3. Changing the handwritten `gameboy.rb` wrapper boundary.

## Phased Plan

### Phase 1: Importer Auto-Stub Profile

#### Red

1. Add failing importer coverage for an opt-in simulation-safe auto-stub profile.
2. Add failing coverage for merging explicit stub overrides on top of the profile.

#### Green

1. Add a named Game Boy auto-stub profile in `SystemImporter`.
2. Merge the profile with explicit `stub_modules` deterministically.
3. Keep the feature opt-in so strict/raw imports remain unchanged.

#### Exit Criteria

1. `SystemImporter` can produce the simulation-safe stub set without spec-local duplication.

### Phase 2: Parity/CLI Integration

#### Red

1. Add failing CLI coverage for toggling importer auto stubs.
2. Update parity specs to consume the importer profile instead of local stub lists.

#### Green

1. Thread the new option through the Game Boy import CLI.
2. Switch runtime/behavioral parity specs to the importer profile.
3. Document the option in README/docs.

#### Exit Criteria

1. Simulation-oriented Game Boy imports can opt into the shared stub profile from both Ruby and CLI entry points.

### Phase 3: Validation

#### Red

1. Run targeted importer/CLI/integration specs covering the new behavior.

#### Green

1. Keep the importer and Game Boy import correctness specs green.

#### Exit Criteria

1. The importer auto-stub mode is implemented, documented, and validated.

## Acceptance Criteria

1. Game Boy `SystemImporter` accepts an auto-stub mode for the simulation-safe profile.
2. The simulation-safe profile covers `gb_savestates`, `gb_statemanager__vhdl_2e2d161b9c1b`, and `sprites_extra`.
3. Explicit `stub_modules` merge with the auto-stub profile and can override a profile entry by module name.
4. The Game Boy import CLI exposes the option.
5. The runtime parity specs use the importer profile instead of hard-coded local stub lists.

## Risks And Mitigations

1. Auto stubs could accidentally leak into strict equivalence/import workflows.
   - Mitigation: keep the profile opt-in.
2. The profile could grow beyond what is clearly safe.
   - Mitigation: keep the first profile limited to wrapper-disabled subsystems only.
3. Explicit override merging could become nondeterministic.
   - Mitigation: merge by module name with stable ordering and targeted tests.

## Implementation Checklist

- [x] Phase 1: Importer Auto-Stub Profile
- [x] Phase 2: Parity/CLI Integration
- [x] Phase 3: Validation
