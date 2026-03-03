# Arc -> ArcToGPU -> MLIR GPU Gap (CPU8bit Slice)

**Status:** Completed
**Date:** 2026-03-03

## Context

RHDL already supports native 8-bit CPU execution through IR backends, but it lacks an end-to-end integration path for an ArcToGPU-enabled execution mode in the native runner flow. We need an incremental path that is useful immediately while preserving clear seams for the real ArcToGPU backend landing.

This PRD tracks the staged implementation for the `examples/8bit` first target.

## Goals

1. Add a first-class `:arcilator_gpu` mode to 8-bit native execution.
2. Make prerequisite/tooling checks explicit (MLIR/SPIR-V/Metal path).
3. Add benchmark wiring for 8-bit native GPU-path comparisons.
4. Keep cycle execution semantics stable for parity validation.

## Non-Goals

1. Implement the full ArcToGPU lowering inside CIRCT in this repo.
2. Web simulator integration for this backend in this phase.
3. Large-system migration (Apple II, RISC-V) before 8-bit stabilization.

## Phased Plan

### Phase 1: FastHarness ArcToGPU Mode Shell

**Red:** No `:arcilator_gpu` mode; no clear capability failures.
**Green:** `FastHarness.new(sim: :arcilator_gpu)` exists, uses runner-backed memory, and fails with actionable errors when ArcToGPU prerequisites are missing.

Exit criteria:
1. New runner-backed memory adapter is in place.
2. `:arcilator_gpu` mode validates runner kind and capability checks.
3. Specs cover success path and expected failure paths.

### Phase 2: Dependency Surface and Benchmark Integration

**Red:** `deps:check` does not report MLIR/SPIR-V/Metal prerequisites; no 8-bit benchmark scope for GPU path.
**Green:** Dependency checks include ArcToGPU prerequisites, `deps:check_gpu` fails fast for missing GPU toolchain, and `bench:native[cpu8bit,...]` benchmarks compiler vs `:arcilator_gpu`.

Exit criteria:
1. `DepsTask` reports `mlir-opt`, `spirv-cross`, and Metal tool presence (macOS).
2. `deps:check_gpu` fails fast when ArcToGPU prerequisites/capabilities are missing.
3. `BenchmarkTask` supports `type: :cpu8bit`.
4. `Rakefile` exposes `bench:native[cpu8bit,<cycles>]`.
5. Rake/spec dispatch coverage is green.

### Phase 3: Real ArcToGPU Artifact Execution

**Red:** `:arcilator_gpu` still routes through existing compiler runner ABI bridge.
**Green:** `:arcilator_gpu` executes with a true ArcToGPU-generated native artifact path.

Exit criteria:
1. Harness no longer relies on compiler backend shim for GPU mode.
2. Build/invoke path for ArcToGPU artifacts is documented and testable.
3. Parity checks verify cycle-exact behavior on representative 8-bit programs.

## Acceptance Criteria

1. Users can instantiate 8-bit FastHarness with `sim: :arcilator_gpu`.
2. Missing ArcToGPU prerequisites produce explicit, actionable messages.
3. `bundle exec rake deps:check` reports ArcToGPU-related tool status.
4. `bundle exec rake deps:check_gpu` fails fast when ArcToGPU toolchain is incomplete.
5. `bundle exec rake bench:native[cpu8bit]` is available and functional.
6. Targeted specs for new routing and checks are green.

## Risks and Mitigations

1. Risk: ArcToGPU features vary across local arcilator builds.
   Mitigation: Gate with explicit capability checks and clear failure text.
2. Risk: Benchmark behavior could be misleading if programs halt early.
   Mitigation: Use an explicit infinite-loop workload for fixed-cycle runs.
3. Risk: Platform-specific tool detection can be flaky.
   Mitigation: Keep checks command-based and treat missing optional tools as non-fatal.

## Implementation Checklist

- [x] Phase 1: Add `:arcilator_gpu` mode in 8-bit FastHarness.
- [x] Phase 1: Add runner-backed 64K memory adapter.
- [x] Phase 1: Add capability-gating specs for fast harness mode.
- [x] Phase 2: Extend dependency checks for ArcToGPU/Metal prerequisites.
- [x] Phase 2: Add strict fail-fast ArcToGPU toolchain task (`deps:check_gpu`).
- [x] Phase 2: Add `BenchmarkTask` CPU8bit benchmark mode.
- [x] Phase 2: Add `bench:native[cpu8bit]` Rake wiring and specs.
- [x] Phase 3: Replace compiler-bridge execution with dedicated arcilator GPU runner artifact path (gated by tool/capability detection).
- [x] Phase 3: Add cycle-exact parity suite specifically for ArcToGPU path (gated/pending when ArcToGPU toolchain is unavailable).
