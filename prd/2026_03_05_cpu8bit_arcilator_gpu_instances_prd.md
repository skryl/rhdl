# CPU8bit ArcilatorGPU Multi-Instance PRD

## Status
Completed (2026-03-05)

## Context
The CPU8bit `:arcilator_gpu` runner currently executes exactly one logical CPU instance. The native benchmark surface already knows how to report instance-adjusted throughput when a runner exposes `runner_parallel_instances`, but the CPU8bit ArcilatorGPU path does not provide any instance-count control or reporting today.

Apple II and RISC-V already have explicit Metal/ArcilatorGPU instance knobs. CPU8bit should expose the same capability with a backend-specific environment variable and benchmark-visible instance count.

## Goals
1. Add configurable CPU8bit ArcilatorGPU multi-instance execution.
2. Keep the existing `FastHarness` API unchanged.
3. Expose instance-adjusted throughput automatically in `bench:native[cpu8bit,...]`.
4. Avoid rebuilds when only the requested instance count changes.

## Non-Goals
1. Re-architecting the CPU8bit ArcilatorGPU pipeline into a new backend.
2. Changing benchmark result formatting beyond existing instance-aware reporting.
3. Adding per-instance external memory APIs in Ruby.

## Phased Plan

### Phase 1: Red Tests
Red:
1. Add failing runner specs for CPU8bit ArcilatorGPU instance-count normalization and env fallback.
2. Add failing harness spec proving `parallel_instances` reflects the runner count for `:arcilator_gpu`.

Green:
1. Add the minimum runner API surface needed for the new tests to pass.

Exit Criteria:
1. Tests fail before implementation and pass after runner wiring lands.

### Phase 2: Native Runner Support
Red:
1. Instance count is ignored by the native CPU8bit ArcilatorGPU wrapper.

Green:
1. Add `instances` / env normalization in the CPU8bit runner.
2. Update the generated native wrapper so one simulation context owns `N` mirrored CPU states and memories.
3. Keep instance 0 as the externally visible state while mirroring loads/writes/resets across all instances.

Exit Criteria:
1. The runner reports `runner_parallel_instances`.
2. Multi-instance execution does not require a rebuild when only the count changes.

### Phase 3: Verification and Docs
Red:
1. No documented user-facing way to request multi-instance CPU8bit ArcilatorGPU runs.

Green:
1. Update benchmark docs with the new env vars.
2. Run targeted specs and a CPU8bit ArcilatorGPU smoke benchmark if the toolchain is available.

Exit Criteria:
1. Docs mention the new CPU8bit ArcilatorGPU instance knob.
2. Targeted specs are green.

## Acceptance Criteria
1. `RHDL_CPU8BIT_ARCILATOR_GPU_INSTANCES` configures the CPU8bit ArcilatorGPU runner.
2. `RHDL_BENCH_ARCILATOR_GPU_INSTANCES` works as a benchmark-wide fallback.
3. `FastHarness#parallel_instances` reports the configured count for CPU8bit ArcilatorGPU.
4. `bench:native[cpu8bit,...]` shows instance-adjusted throughput automatically when instances > 1.
5. Targeted CPU8bit runner and harness specs are green.

## Risks and Mitigations
1. Risk: Mirroring memory/state across instances could drift from existing single-instance semantics.
   Mitigation: Keep instance 0 as the externally visible state and mirror writes/loads uniformly.
2. Risk: Instance-count changes could incorrectly force native rebuilds.
   Mitigation: Pass instance count at runtime rather than baking it into the generated artifact.
3. Risk: Multi-instance execution may not increase throughput materially.
   Mitigation: Keep the feature focused on correctness/reporting first and verify with a smoke benchmark.

## Implementation Checklist
- [x] Phase 1: Add red tests for CPU8bit ArcilatorGPU instance env parsing and harness reporting.
- [x] Phase 2: Add CPU8bit ArcilatorGPU instance normalization and reporting.
- [x] Phase 2: Update the native wrapper to execute mirrored multi-instance contexts.
- [x] Phase 3: Update docs for CPU8bit ArcilatorGPU instance env vars.
- [x] Phase 3: Run targeted specs and smoke verification.
