# PRD: Full Live-UX Worker Architecture (Sim + VCD + Memory/PC + Schematic)

**Status:** Proposed

## Context

The current web simulator performs a large amount of live update work on the
main thread during run mode:

1. Simulation stepping and run-loop orchestration.
2. Trace capture and VCD parsing.
3. Watch/breakpoint evaluation and view refreshes.
4. Memory panel reads, PC-follow, disassembly generation, and highlight logic.
5. Schematic build/layout/activity updates.

On larger runners (notably xv6), this causes UI stalls and long periods of
unresponsiveness when opening schematic views and while running with active
panels.

This PRD defines a split-worker architecture where workers own live compute and
the main thread is limited to DOM/render/input duties.

## Goals

1. Move all live run-time UX compute off the main thread:
   - I/O display status updates
   - signal/VCD updates
   - memory + PC-follow + disassembly updates
   - schematic build/layout/activity updates
   - watch/breakpoint live evaluation
2. Preserve existing UX behavior and controls.
3. Eliminate browser hangs during run and schematic open on large runners.
4. Enforce responsiveness with measurable acceptance tests.

## Non-Goals

1. Redesigning simulator UX layout or controls.
2. Replacing ELK or waveform renderer libraries.
3. Changing runner artifact formats or preset semantics.
4. Introducing a compatibility bridge as primary architecture (this plan uses a
   direct async rewrite).

## Key Decisions and Defaults

1. Worker topology: **Split workers**
   - `sim_runtime_worker`
   - `schematic_compute_worker`
2. Update payload model: **Delta snapshots**
3. API migration strategy: **Full async rewrite**
4. Live update cadence: **Tiered cadence**
   - ~60Hz I/O and status
   - ~30Hz schematic and waveform
   - ~10-15Hz memory/disasm (with temporary boost on active interaction)
5. Responsiveness target: **Main-thread stall <= 100ms**
6. Responsiveness test coverage: **xv6 + apple2**

## Public Interfaces / Contracts

### Worker Commands (high-level)

1. `sim:init`
2. `sim:run`
3. `sim:pause`
4. `sim:step`
5. `sim:trace:set`
6. `sim:watch:set`
7. `sim:breakpoint:set`
8. `sim:memory:view`
9. `sim:memory:write`
10. `sim:panel:focus`
11. `sim:cadence:set`
12. `schematic:build`
13. `schematic:activity`
14. `schematic:cancel`

### Worker Events (high-level)

1. `sim:snapshot:delta`
2. `io:snapshot:delta`
3. `watch:snapshot:delta`
4. `trace:snapshot:delta`
5. `memory:snapshot:delta`
6. `schematic:snapshot:delta`
7. `worker:error`

### Runtime Surface Changes

1. Main-thread direct `runtime.sim` usage removed from live UX paths.
2. New clients added:
   - `runtime.simClient`
   - `runtime.schematicClient`
3. Main-thread controllers become command senders + delta consumers.

## Phased Plan

### Phase 0: Protocol and Worker Lifecycle Foundation

Red:
1. Add failing protocol tests for request ID correlation, stale response drops,
   cancellation, and delta merge behavior.
2. Add failing tests for worker restart/failure handling.

Green:
1. Add shared protocol/type constants and validators.
2. Add worker lifecycle manager (spawn, health check, restart, teardown).
3. Add deterministic delta merge helpers.

Exit criteria:
1. Protocol contract tests pass.
2. Worker lifecycle tests pass.

### Phase 1: Move Sim Loop + Status + I/O Derivation to Worker

Red:
1. Add failing tests proving run loop no longer steps simulation on main thread.
2. Add failing parity tests for run/pause/step behavior.

Green:
1. Move run-loop compute into `sim_runtime_worker`.
2. Move throughput sampling and breakpoint check cadence into worker.
3. Emit status and I/O deltas from worker; main thread only applies updates.

Exit criteria:
1. Main thread no longer performs simulation stepping during run.
2. Run/pause/step behavior parity is preserved.

### Phase 2: Move Trace + VCD Parse + Watch Updates to Worker

Red:
1. Add failing tests showing main-thread parser ingestion is no longer used.
2. Add failing tests for worker-driven watch table updates.

Green:
1. Move trace capture scheduling to worker.
2. Move live VCD parsing to worker.
3. Move watch value derivation and breakpoint polling into worker.
4. Keep VCD export command-based.

Exit criteria:
1. Trace/live VCD updates are worker-owned.
2. Watch and breakpoint behavior matches current UX semantics.

### Phase 3: Move Memory + PC Follow + Disassembly to Worker

Red:
1. Add failing tests for worker-driven `followPc` behavior.
2. Add failing tests for memory byte highlight parity.

Green:
1. Move memory panel data reads and windowing to worker.
2. Move PC-follow centering, access detection, and highlight lifetimes to worker.
3. Move disassembly derivation to worker.
4. Emit memory panel deltas; main thread renders only.

Exit criteria:
1. Main thread no longer reads live memory for panel refresh.
2. Memory/disassembly/follow-PC behavior parity passes tests.

### Phase 4: Move Schematic Compute to Worker

Red:
1. Add failing tests for cancellation and stale-apply behavior across tab/focus
   switches.
2. Add failing tests for trace-on/trace-off activity update correctness with
   worker-driven signal deltas.

Green:
1. Move schematic build/layout/index/activity compute to
   `schematic_compute_worker`.
2. Integrate worker results with main-thread canvas/WebGL rendering path.
3. Add strict job-ID gating and cancellation semantics.

Exit criteria:
1. Schematic open on xv6 no longer blocks main thread.
2. Schematic animation still follows trace enabled/disabled state.

### Phase 5: Full Async Rewrite Completion

Red:
1. Add a failing guard test that catches direct live-path `runtime.sim.*` usage
   on main thread.

Green:
1. Rewrite remaining direct users in sim, memory, watch, explorer, editor, and
   shell live-update paths to use worker commands/deltas.
2. Keep non-live utility flows routed through worker command APIs.

Exit criteria:
1. No direct main-thread `runtime.sim` usage remains in live update flows.
2. Guard test passes and protects regressions.

### Phase 6: Responsiveness Hardening and Final Gates

Red:
1. Add failing integration responsiveness tests with instrumentation for:
   - xv6 large runner flow
   - apple2 medium runner flow

Green:
1. Implement cadence scheduler + delta coalescing/backpressure.
2. Ensure active interaction boosts cadence where needed.
3. Validate no long main-thread stalls during run and tab switching.

Exit criteria:
1. Main-thread stall remains <= 100ms in acceptance scenarios.
2. No browser hangs under combined live panel activity.

## Acceptance Criteria (Full Completion)

1. During run, live update compute is worker-owned for:
   - status/I/O display
   - trace/VCD updates
   - watch/breakpoint updates
   - memory/PC-follow/disassembly updates
   - schematic compute updates
2. Main thread only performs DOM updates, rendering, and input handling for
   live UX flows.
3. Existing run/pause/step, trace controls, and panel semantics remain intact.
4. xv6 and apple2 responsiveness gates pass with stall cap <= 100ms.
5. Regression tests cover worker protocol integrity, cancellation, stale-drop,
   and panel behavior parity.

## Risks and Mitigations

1. Risk: Large async rewrite causes command-order bugs.
   Mitigation: strict message IDs, monotonic sequence checks, and stale-drop
   tests.
2. Risk: Event flood from worker to main thread.
   Mitigation: tiered cadence, delta coalescing, and bounded queue/backpressure
   policy.
3. Risk: Worker crash leaves UI stale.
   Mitigation: worker health watchdog, restart path, and explicit degraded
   status messages.
4. Risk: Cross-worker race (sim vs schematic).
   Mitigation: job IDs tied to tick/version counters and apply-only-if-current
   guards.

## Implementation Checklist

- [ ] Phase 0: Add protocol contract tests and worker lifecycle manager.
- [ ] Phase 1: Move run loop and status/I/O derivation to `sim_runtime_worker`.
- [ ] Phase 2: Move trace/VCD parsing and watch updates to worker.
- [ ] Phase 3: Move memory/PC-follow/disassembly derivation to worker.
- [ ] Phase 4: Move schematic compute to `schematic_compute_worker`.
- [ ] Phase 5: Complete full async rewrite of main-thread live paths.
- [ ] Phase 6: Add responsiveness instrumentation and pass final perf gates.

