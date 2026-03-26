# AO486 Verilog Patch Profile Cutover

## Status

In Progress - 2026-03-11

## Context

The current AO486 parity and DOS-runner flows still depend on Ruby-side package rewrites after CIRCT has already imported the Verilog source:

1. `CpuTracePackage`
2. `CpuParityPackage`
3. `CpuRunnerPackage`

That violates the requested import boundary. The AO486 import flow already supports applying staged RTL patch series before `circt-verilog`, and `examples/ao486/patches/` is available again. The goal of this PRD is to make patched Verilog the only source of AO486 trace/parity/runner structural changes so that no AO486 design rewriting happens after the Verilog phase.

## Goals

1. Move AO486 parity/runner structural rewrites to checked-in Verilog patch profiles under `examples/ao486/patches/`, with parity also carrying the trace surface.
2. Make AO486 importers support named patch profiles in addition to raw `patches_dir:`.
3. Retarget IR, Verilator, and Arcilator AO486 runner builds to consume patched imported MLIR directly.
4. Remove production/test dependencies on Ruby-side AO486 package rewrite helpers.
5. Keep AO486 DOS boot debugging on the Verilator runner after the cutover.

## Non-Goals

1. Reworking AO486 runtime BIOS/DOS memory patching done by the host runners.
2. Changing the CPU-top target away from `ao486`.
3. Introducing a new AO486 top or system-level import flow.

## Phased Plan

### Phase 1: Patch Profile Plumbing

Red:
1. Add failing importer coverage for AO486 named patch profiles.
2. Add failing coverage that AO486 runner/parity builders no longer need Ruby package rewrites.

Green:
1. Add named AO486 patch-profile resolution for `parity` and `runner`.
2. Keep explicit `patches_dir:` support for ad hoc staged patch series.
3. Thread patch profiles through `CpuImporter` and the AO486 runner build paths.

Exit Criteria:
1. Importers can resolve `examples/ao486/patches/<profile>/`.
2. Production AO486 build paths no longer select `CpuTracePackage`, `CpuParityPackage`, or `CpuRunnerPackage`.

### Phase 2: Verilog Patch Series

Red:
1. Add failing import/runtime checks that require trace ports and parity/runner fetch behavior from patched source-only imports.
2. Confirm current unpatched imports do not satisfy those checks.

Green:
1. Add checked-in patch series under:
   - `examples/ao486/patches/parity/`
   - `examples/ao486/patches/runner/`
2. Encode the current AO486 trace/parity/runner structural changes entirely in those patch series.
3. Make the parity profile carry the trace semantics and determine whether the runner profile can be eliminated or must remain separate.

Exit Criteria:
1. Patched-import MLIR already contains the required trace and fetch-path behavior.
2. No AO486 design mutation happens after import from patched Verilog.

### Phase 3: Runner And Spec Cutover

Red:
1. Add failing runner/spec coverage that expects patched-import artifacts instead of post-import package transforms.
2. Confirm old helper surfaces are no longer used by production AO486 paths.

Green:
1. Retarget `IrRunner`, `VerilatorRunner`, and `ArcilatorRunner` to patched-import MLIR.
2. Update AO486 helper/spec code to build from patch-profiled imports.
3. Remove or delete obsolete AO486 post-import rewrite helpers once callers are gone.

Exit Criteria:
1. AO486 specs no longer rely on `CpuTracePackage`, `CpuParityPackage`, or `CpuRunnerPackage`.
2. Headless/backends consume the same patched-import boundary.

### Phase 4: Verification And Verilator DOS Resume

Red:
1. Reproduce the current Verilator DOS divergence on the new patched-import boundary if it still exists.

Green:
1. Run targeted AO486 importer/package replacement tests.
2. Run targeted AO486 parity/runtime tests.
3. Resume Verilator DOS boot debugging on the patch-based runner flow.

Exit Criteria:
1. Patch-profiled import and parity surfaces are green.
2. Verilator DOS debugging is operating on the patch-based flow only.

## Acceptance Criteria

1. AO486 named patch profiles exist under `examples/ao486/patches/`.
2. AO486 import and runner flows use patched Verilog as the only source of trace/parity/runner structural changes.
3. There is no AO486 design rewrite step after the Verilog phase in production/test execution paths.
4. Targeted AO486 importer, parity, and runner tests are green on the new flow.

## Risks And Mitigations

1. Risk: the current Ruby rewrite logic is larger than a manageable hand-written patch series.
   Mitigation: generate the initial patch series mechanically from the current rewrite outputs, then cut callers over and delete the rewrite dependency.
2. Risk: parity and runner variants drift from each other during patch migration.
   Mitigation: keep named profiles explicit and verify each through focused AO486 runtime checks.
3. Risk: the Verilator DOS divergence is masked by the migration work.
   Mitigation: keep a reproducible Verilator DOS smoke probe before and after cutover.

## Implementation Checklist

- [x] Add named AO486 patch-profile resolution and focused importer specs.
- [x] Generate/check in parity patch series.
- [x] Generate/check in runner patch series.
- [x] Retarget AO486 runners to patch-profiled imports.
- [x] Update AO486 specs/helpers to the patch-profiled boundary.
- [x] Remove obsolete AO486 post-import rewrite helpers from production/test paths.
- [ ] Run targeted AO486 validation and resume Verilator DOS debugging.

## Update - 2026-03-11

Completed in this pass:

1. Restored checked-in AO486 patch profiles under `examples/ao486/patches/` and regenerated the trace/parity/runner RTL deltas from the former rewrite outputs.
2. Retargeted AO486 runner construction so patched imported MLIR is consumed directly:
   - `IrRunner.runtime_bundle` now imports with `patch_profile: :runner`
   - `VerilatorRunner.runtime_bundle` now imports with `patch_profile: :runner`
   - `IrRunner.build_from_cleaned_mlir`, `VerilatorRunner.build_from_cleaned_mlir`, and `ArcilatorRunner.build_from_cleaned_mlir` now treat the input MLIR as already patched
3. Retargeted the AO486 trace/parity specs to import with the appropriate patch profile instead of mutating imported packages afterward.
4. Removed the AO486 post-import rewrite helper files from the active code path:
   - `cpu_trace_package.rb`
   - `cpu_parity_package.rb`
   - `cpu_runner_package.rb`

Targeted validation completed sequentially:

1. `bundle exec rspec spec/examples/ao486/import/cpu_trace_package_spec.rb -e 'adds stable retire-trace ports to the imported ao486 package' --format documentation`
2. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb --format documentation`
3. `bundle exec rspec spec/examples/ao486/import/cpu_parity_runtime_spec.rb -e 'drives deterministic reset-vector PC byte groups on the parity package' --format documentation`
4. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb --format documentation`
5. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/integration/verilator_runner_boot_smoke_spec.rb --format documentation`

Verilator DOS status on the new boundary:

1. The old early Verilator `#UD` around `0xE0AB` is gone on the patch-profiled runner path.
2. Verilator now reaches the visible `FreeDOS_` milestone and later DOS disk-read path rather than dying in early POST.
3. The remaining DOS blocker has moved later into the shared bootloader/runtime path instead of the old Ruby rewrite layer.
