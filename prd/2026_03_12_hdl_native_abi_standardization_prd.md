## Status

In Progress - 2026-03-13

Current progress:

1. Shared HDL ABI/core and standardized `HeadlessRunner` trace facade are
   implemented.
2. Phase 3 is complete:
   - Verilator: MOS6502, Apple II, RISC-V
   - Arcilator: Apple II, RISC-V
3. Game Boy is complete on the shared ABI/core path for both Verilator and
   Arcilator, including shared runtime trace/VCD support.
4. Wave 1 + Game Boy now enforce the runner ABI contract on load, expose a
   uniform native `sim` object from their headless adapters, and no longer rely
   on Apple II Arcilator silently falling back to Verilator.
5. AO486 and SPARC64 remain intentionally deferred outside the current scope.

## Context

The native HDL backends for Verilator and Arcilator do not currently share the
same ABI as the IR interpreter/JIT/compiler backends.

That mismatch shows up in three places:

1. Example runners export ad hoc `sim_create` / `sim_poke` / `sim_peek`
   signatures instead of the IR native ABI surface.
2. `HeadlessRunner` APIs probe backend capabilities with `respond_to?` instead
   of binding through a declared runtime contract.
3. Trace/VCD, signal indexing, runner memory/control/probe, and capability
   reporting drift by backend and by example.

The repository already contains two strong precedents for the target design:

1. `lib/rhdl/sim/native/ir/simulator.rb` and the IR FFI crates define the
   desired ABI surface and Ruby binding model.
2. The Apple II and RISC-V web builders already export IR-style ABI entrypoints
   (`sim_create`, `sim_get_caps`, `sim_signal`, `sim_exec`, `sim_trace`,
   `sim_blob`, `runner_*`) even though their trace implementations are still
   incomplete.

## Goals

1. Standardize the native HDL ABI to the IR interpreter/JIT/compiler ABI.
2. Add a shared HDL ABI/core layer for Verilator and Arcilator native backends.
3. Route `HeadlessRunner` runtime and trace access through the standardized ABI.
4. Convert the existing native HDL runners in phases:
   - first: runners that do not include `ao486`, `gameboy`, or `sparc64`
   - second: `ao486`, `gameboy`, and `sparc64`
5. Keep the shared VCD / trace contract aligned with the IR backends.

## Non-Goals

1. Reworking the IR native ABI.
2. Replacing example-specific runtime semantics such as Apple II display logic,
   Game Boy cartridge behavior, SPARC64 subprocess management, or AO486 DOS
   harness behavior with a generic abstraction.
3. Converting unrelated Ruby, netlist, or pure-Ruby runner interfaces.
4. Moving the HDL backends onto Rust crates in this slice.

## Phased Plan

### Phase 1: Red - PRD and ABI contract tests

1. Write this PRD and lock the target ABI to the IR native ABI.
2. Add red tests for the shared HDL Ruby adapter and first-wave runners that
   expect:
   - the IR-native symbol set,
   - IR-native caps / enum semantics,
   - IR-native trace/VCD method behavior through `HeadlessRunner`.
3. Capture the baseline failures on the current first-wave runners.

Exit criteria:

1. The ABI target is documented here.
2. First-wave ABI tests exist and fail against the pre-change HDL runners.

### Phase 2: Green - shared HDL ABI/core layer

1. Add the shared Ruby ABI/core layer that mirrors the IR native binding model.
2. Add shared constants / struct packing / dispatcher helpers aligned with the
   IR ABI.
3. Add shared Verilator / Arcilator support code under:
   - `lib/rhdl/sim/native/verilog/verilator`
   - `lib/rhdl/sim/native/mlir/arcilator`
4. Preserve unsupported-op behavior by caps and IR-style return values instead
   of introducing backend-specific alternate entrypoints.

Exit criteria:

1. A shared HDL ABI/core exists and can bind a backend exposing the IR ABI.
2. The shared layer does not depend on example-specific logic.

### Phase 3: Green - first-wave runner conversion

Convert the simpler runner set first:

1. Verilator
   - MOS6502
   - Apple II
   - RISC-V
2. Arcilator
   - Apple II
   - RISC-V

For each runner:

1. Export the IR-native ABI surface from the native library.
2. Bind the runner through the shared HDL ABI/core layer.
3. Expose runtime / trace access through the example `HeadlessRunner`.

Exit criteria:

1. All first-wave runners use the standardized ABI.
2. First-wave headless flows use the shared HDL ABI/core.
3. First-wave ABI and trace tests pass.

### Phase 4: Green - second-wave runner conversion

Convert the heavier bespoke runners after phase 3 is green:

1. Verilator
   - Game Boy
   - SPARC64
   - AO486
2. Arcilator
   - Game Boy
   - SPARC64
   - AO486

For each runner:

1. Keep its bespoke behavior behind the standardized ABI and runner extension
   surface.
2. Move any common runtime/trace/capability plumbing into the shared HDL ABI/core
   instead of re-implementing it locally.
3. Update `HeadlessRunner` to expose the standardized trace/runtime surface.

Exit criteria:

1. The second-wave runners use the standardized ABI for core runtime access.
2. Example-specific extensions still work through the shared ABI/core.

### Phase 5: Verification and cleanup

1. Run the targeted first-wave and second-wave specs.
2. Run the shared headless-runner specs that exercise the new top-level trace
   surface.
3. Record any intentionally unsupported ABI operations or remaining follow-up
   work.

Exit criteria:

1. Targeted specs are green.
2. Unsupported operations are documented by caps / tests rather than hidden.

## Acceptance Criteria

1. The native HDL backends export the IR-native ABI surface.
2. `HeadlessRunner` exposes the standardized runtime / trace surface on top of
   that ABI.
3. The first-wave runners are fully migrated before the `ao486` / `gameboy` /
   `sparc64` conversions.
4. Trace/VCD behavior matches the IR-native contract where the backend reports
   trace support.
5. This PRD status and checklist reflect the final implementation state.

## Risks And Mitigations

1. Risk: existing example runners depend on local `sim_*` signatures.
   Mitigation: keep local compatibility shims while migrating Ruby callers to
   the shared HDL ABI/core.
2. Risk: wide-signal behavior differs by backend.
   Mitigation: align on the IR `SignalValue128` / `sim_signal_wide` contract and
   test wide-signal cases explicitly.
3. Risk: the bespoke second-wave runners hide more behavior in local helpers than
   the first-wave runners.
   Mitigation: defer them until after the shared core and first-wave ABI path are
   green, then parallelize their conversions.
4. Risk: the worktree is already dirty in `ao486`, `gameboy`, and `sparc64`.
   Mitigation: land the shared core and first-wave changes first, then integrate
   second-wave work carefully without reverting unrelated edits.

## Implementation Checklist

- [x] Phase 1: Add failing ABI / trace tests for the shared HDL ABI/core and
      first-wave runners.
- [x] Phase 2: Implement the shared HDL ABI/core layer.
- [x] Phase 3: Convert first-wave runners and headless adapters.
- [ ] Phase 4: Convert second-wave runners and headless adapters.
      Game Boy is complete. AO486 and SPARC64 remain deferred.
- [ ] Phase 5: Run targeted verification and update this PRD status/checklist.
