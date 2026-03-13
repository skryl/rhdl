# AO486 Pre-Import Patch Profile Migration

## Status

In Progress - 2026-03-11

## Context

AO486 currently injects three different families of behavior after the Verilog import boundary:

1. trace-port instrumentation currently carried by `CpuTracePackage`
2. parity-specific fetch/prefetch rewrites in `CpuParityPackage`
3. DOS-runner fetch/prefetch/memory rewrites in `CpuRunnerPackage`

Those transforms import cleaned CIRCT MLIR into Ruby module/package objects, mutate them, and then lower them back to MLIR/Verilog/IR. The user wants that boundary removed: AO486 behavior changes must live on the Verilog side as staged patch series under `examples/ao486/patches`, with zero structural rewriting after the Verilog phase.

The importer already has opt-in `patches_dir:` staging support. The missing pieces are:

1. named patch profiles under `examples/ao486/patches`
2. importer/profile plumbing so runners and specs can request the correct staged RTL profile
3. migration of current Ruby rewrite behavior into those patch profiles
4. runner/spec cutover so they consume patched imported artifacts directly

## Goals

1. Add named AO486 patch profiles under `examples/ao486/patches`, with parity also carrying the trace surface.
2. Let `SystemImporter` and `CpuImporter` resolve one or more named profiles into deterministic staged patch application before `circt-verilog`.
3. Move AO486 trace/parity/runner RTL modifications out of Ruby package rewrites and into Verilog patch series.
4. Retarget AO486 runners and specs to patched imported artifacts only.
5. End with zero AO486 structural rewrites after the Verilog phase.

## Non-Goals

1. Removing runtime BIOS/DOS memory patching in runner host logic.
2. Changing the user-visible AO486 CLI surface in this PRD.
3. Reworking generic CIRCT import APIs outside AO486-specific import/runners.

## Phased Plan

### Phase 1: Patch Profile Plumbing

Red:

1. Add focused importer specs for named patch profiles resolved from `examples/ao486/patches/<profile>`.
2. Add failing coverage that multiple profiles apply in deterministic order.

Green:

1. Add importer options for `patch_profile:` / `patch_profiles:` in AO486 importers.
2. Resolve named profiles to staged patch files under `examples/ao486/patches`.
3. Preserve existing ad hoc `patches_dir:` support for one-off patch directories.

Exit Criteria:

1. Importers can stage one or more named AO486 profiles without custom absolute paths.
2. Focused importer specs are green.

### Phase 2: Parity Profile Migration

Red:

1. Replace `CpuTracePackage` specs with failing import-time parity-profile coverage for the trace surface.
2. Confirm top/pipeline/write trace ports are absent without the parity profile and present with it.

Green:

1. Add a checked-in parity patch series under `examples/ao486/patches/parity`.
2. Switch trace-oriented and parity-oriented runner/spec helpers to import with the parity profile instead of Ruby package rewriting.

Exit Criteria:

1. Trace outputs and parity behavior come from the parity patch profile only.
2. `CpuTracePackage` is deleted or reduced to a no-op compatibility shell with no structural rewrites.

### Phase 3: Runner Profile Migration And DOS Continuation

Red:

1. Replace `CpuRunnerPackage` coverage with failing runner-profile import/runtime coverage.
2. Capture the Verilator DOS boot baseline on the patched runner profile.

Green:

1. Add runner patch series under `examples/ao486/patches/runner`.
2. Switch DOS/headless runners to the patched runner import path.
3. Delete `CpuRunnerPackage` structural rewrites.
4. Resume Verilator DOS boot debugging on the patched runner flow.

Exit Criteria:

1. DOS/headless runners use patched imported RTL only.
2. No AO486 structural rewrite remains after the Verilog phase.

## Acceptance Criteria

1. `examples/ao486/patches/parity` exists and is used for both the trace surface and parity behavior, and `examples/ao486/patches/runner` remains only if DOS runner validation proves it is still needed.
2. AO486 importer/runners can request named profiles without custom patch directory paths.
3. `CpuTracePackage`, `CpuParityPackage`, and `CpuRunnerPackage` no longer mutate imported modules/packages structurally.
4. AO486 parity and DOS runner tests consume patched imported artifacts directly.
5. Verilator DOS boot debugging continues on the new patched runner flow.

## Risks And Mitigations

1. Risk: source-level Verilog patches drift from the current Ruby-rewrite semantics.
   Mitigation: migrate one profile at a time and keep focused import/runtime checks for each profile.
2. Risk: profile composition order changes behavior unexpectedly.
   Mitigation: define deterministic patch-file ordering and explicit profile ordering tests.
3. Risk: trace/parity/runner profiles need overlapping edits in the same source file.
   Mitigation: keep profiles separate but allow deterministic multi-profile staging when needed.
4. Risk: the migration breaks current DOS boot progress before functional parity is restored.
   Mitigation: keep the active Verilator DOS probes and resume against the runner profile immediately after cutover.

## Implementation Checklist

- [x] Add named AO486 patch-profile plumbing to importers.
- [x] Add focused importer specs for profile resolution and ordering.
- [x] Add parity patch profile and cut over trace/parity runners/specs.
- [x] Add runner patch profile and cut over DOS/headless runners.
- [x] Remove AO486 post-Verilog structural rewrites.
- [ ] Resume Verilator DOS boot debugging on the patched runner flow.

## Update 2026-03-11

1. `SystemImporter` and `CpuImporter` now resolve named `patch_profile:` / `patch_profiles:` values from `examples/ao486/patches`.
2. The old Ruby-side rewrite modules were deleted:
   - `examples/ao486/utilities/import/cpu_trace_package.rb`
   - `examples/ao486/utilities/import/cpu_parity_package.rb`
   - `examples/ao486/utilities/import/cpu_runner_package.rb`
3. Targeted patched-import regression gates are green:
   - `bundle exec rspec spec/examples/ao486/import/trace_patch_profile_spec.rb --format documentation`
   - `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb --format documentation`
   - `bundle exec rspec spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb -e 'matches the selected IR backend, Verilator, and Arcilator on the final memory image for the compact benchmark set' --format documentation`
4. On the patched `runner` profile, the clean Verilator DOS boot no longer dies in early BIOS POST with the former `#UD` around `0xE0AB`.
5. Current Verilator DOS state on the patched runner profile:
   - by `100_000` cycles it reaches the visible `FreeDOS_` banner with `last_irq = 0x08`
   - by `200_000` cycles it is still parked at `FreeDOS_`
   - the live DOS bridge state remains centered on `INT 13h AH=0x02`, `CX=0x000D`, `DX=0x0100`, `ES:BX=0x01C0:0x0000`
