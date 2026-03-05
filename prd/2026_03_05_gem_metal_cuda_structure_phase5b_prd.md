# GEM Metal CUDA-Structure Mirror (Phase 5B) PRD

## Status
Completed (2026-03-05)

## Context
The initial CUDA-to-Metal migration established functional parity and end-to-end VCD parity, but Metal still executes a mostly scalar kernel path internally. The next step is to mirror CUDA kernel structure more closely while maintaining strict per-change parity and practical iteration speed.

The prior migration PRD remains the source of baseline history:
- `prd/2026_03_05_gem_cuda_to_metal_prd.md`

## Goals
1. Mirror CUDA launch geometry and execution structure in Metal incrementally.
2. Preserve bit-exact parity at every change.
3. Keep all required validation capped to <=50k cycles for practical iteration.
4. Keep `FlattenedScriptV1` ABI unchanged.
5. Add repeatable perf snapshots for progress tracking.

## Non-Goals
1. Script format redesign or ABI churn.
2. >50k-cycle mandatory gates in this phase.
3. Any temporary parity regressions for performance.

## Phased Plan

### 5B.1 Launch Geometry + Multi-Stage Dependency Guard
Red:
1. Add failing synthetic multi-stage parity case with cross-stage dependency.

Green:
1. Switch Metal launch geometry to one threadgroup per logical block (CUDA-shaped geometry).
2. Keep correctness via lane-0 execution while preserving current semantics.
3. Validate new multi-stage parity case plus existing parity suites.

Exit Criteria:
1. Multi-stage synthetic parity passes.
2. Existing tiny and SRAM/duplicate parity tests pass.
3. End-to-end tiny VCD parity test passes.

### 5B.2 Boomerang Lane-Parallel Mirror
Red:
1. Add failing hierarchy-focused parity case stressing `hier[0..12]` writeout behavior.

Green:
1. Port boomerang hierarchy to lane-parallel/threadgroup-memory execution mirroring CUDA organization.
2. Keep bit-exact hook timing and output bits.

Exit Criteria:
1. New hierarchy parity case passes.
2. Existing parity suites remain green.

### 5B.3 SRAM/Duplicate/Clock-Enable Lane Mirror
Red:
1. Add failing stress case for consecutive-cycle SRAM read/write ordering plus duplicate and clken masking interactions.

Green:
1. Mirror CUDA-style lane role split for SRAM/duplicate/clken sections.
2. Preserve read-before-write semantics and commit ordering.

Exit Criteria:
1. New SRAM stress case passes.
2. Existing parity suites remain green.

### 5B.4 Runtime Submission Stabilization
Red:
1. Add stats/guard assertions for logical vs GPU dispatch accounting and timing fields.

Green:
1. Keep single-stage `cycle_count` fast path.
2. Keep chunked multi-stage submission.
3. Preserve dispatch/timing instrumentation visibility from Rust and smoke binaries.

Exit Criteria:
1. Instrumentation assertions pass in parity tests.
2. No parity regressions.

### 5B.5 Workload Gates + Re-Baseline
Red:
1. Add/update reproducible benchmark harness table for tiny + 8bit representative workload at 5k/50k.

Green:
1. Run required benchmark gates.
2. Publish current table and trend in PRD.

Exit Criteria:
1. 5k/50k benchmark entries are recorded.
2. No unexplained regressions against previous snapshot.

## Acceptance Criteria
1. 5B.1-5B.5 exit criteria are all satisfied.
2. Metal remains bit-exact against CPU reference on required suites.
3. CUDA backend behavior is unchanged.
4. Performance reporting is reproducible at 5k/50k.

## Risks and Mitigations
1. Risk: CUDA warp idioms do not map directly to Metal SIMD execution.
   Mitigation: enforce parity-first lane-level red/green tests.
2. Risk: structural mirroring may regress throughput short-term.
   Mitigation: keep per-phase perf snapshots and regression notes.
3. Risk: real-workload gates can be too slow for tight loops.
   Mitigation: keep mandatory gates at <=50k cycles.

## Implementation Checklist
- [x] 5B.1 Red: add multi-stage synthetic dependency parity test.
- [x] 5B.1 Green: switch launch geometry to threadgroup-per-block and validate parity.
- [x] 5B.2 Red: add boomerang hierarchy stress parity case.
- [x] 5B.2 Green: implement lane-parallel boomerang mirror.
- [x] 5B.3 Red: add SRAM ordering/duplicate/clken stress case.
- [x] 5B.3 Green: implement lane-parallel SRAM/duplicate/clken mirror.
- [x] 5B.4 Red: instrumentation guard assertions in parity suite.
- [x] 5B.4 Green: keep stable submission/stats paths with parity.
- [x] 5B.5 Red/Green: tiny + 8bit representative benchmark table (5k/50k) updated.

## Execution Log
2026-03-05:
1. Added synthetic multi-stage dependency parity case:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - `metal_matches_reference_on_multistage_sram_dependency_case`
2. Added synthetic script builders for stage-level SRAM dependency:
   - `build_sram_stage_script`
   - `build_multistage_sram_dependency_script`
3. Updated Metal kernel launch mapping to CUDA-shaped geometry:
   - `external/GEM/msrc/kernel_v1.metal`
   - kernel now uses `threadgroup_position_in_grid` + `thread_index_in_threadgroup`; lane 0 executes current block logic.
4. Updated native Metal host submission to dispatch threadgroups with fixed 256-thread threadgroup size:
   - `external/GEM/csrc/kernel_v1_metal.mm`
   - uses `dispatchThreadgroups(..., threadsPerThreadgroup=256)`
   - adds explicit guard when pipeline threadgroup capacity < 256.
5. Validation:
   - `cargo test --features metal --test metal_parity_smoke -- --nocapture` passed (`3` tests).
   - `cargo test --features metal --test metal_vcd_e2e -- --nocapture` passed (`1` test).
6. Current tiny benchmark snapshots (post-change):
   - 5k cycles: `logical_dispatches=5000 gpu_dispatches=1 total_ms=4234.148 cycles_per_sec=1180.88`
   - 50k cycles: `logical_dispatches=50000 gpu_dispatches=1 total_ms=41657.575 cycles_per_sec=1200.26`
7. 8bit complex representative gate attempt:
   - attempted `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb:80`
   - run was terminated due impractical runtime for this execution slice; remaining 8bit representative gate work is tracked under 5B.5.
8. Added 5B.2 hierarchy stress parity coverage:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - new synthetic builder `build_hierarchy_stress_script`
   - new test `metal_matches_reference_on_hierarchy_stress_case`
9. Added 5B.3 SRAM ordering + duplicate + clken stress coverage:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - new synthetic builder `build_sram_ordering_duplicate_clken_stress_script`
   - new test `metal_matches_reference_on_multicycle_sram_duplicate_clken_stress_case`
10. Reworked Metal kernel inner path to lane-parallel SRAM/duplicate/clken processing:
   - `external/GEM/msrc/kernel_v1.metal`
   - removed lane-0 serialized loops for these sections
   - added threadgroup permutation scratch (`tg_sram_duplicate`) and per-lane commit/update path
11. Validation after kernel + tests update:
   - `cargo test --features metal --test metal_parity_smoke -- --nocapture` passed (`5` tests)
   - `cargo test --features metal --test metal_vcd_e2e -- --nocapture` passed (`1` test)
12. Updated tiny benchmark snapshots (new kernel):
   - 5k cycles: `logical_dispatches=5000 gpu_dispatches=1 encode_ms=0.013 wait_ms=54.329 total_ms=85.339 cycles_per_sec=58590.12`
   - 50k cycles: `logical_dispatches=50000 gpu_dispatches=1 encode_ms=0.017 wait_ms=371.940 total_ms=402.406 cycles_per_sec=124252.77`
13. Added 8bit representative benchmark entries (compiler vs gem_gpu):
   - command: `RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake 'bench:native[cpu8bit,5000]'`
     - Compiler run: `0.080s` (5000 cycles)
     - GemGPU run: `16.247s` (5000 cycles)
     - Ratio: `GemGPU vs Compiler = 0.005x`
   - command: `RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake 'bench:native[cpu8bit,50000]'`
     - Compiler run: `0.684s` (50000 cycles)
     - GemGPU run: `163.171s` (50000 cycles)
     - Ratio: `GemGPU vs Compiler = 0.004x`
