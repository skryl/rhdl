# GEM Metal CUDA Parity (Phase 5C) PRD

## Status
Completed (2026-03-05)

## Context
Phase 5B completed kernel-structure mirroring and baseline parity gates, but CUDA-implementation parity still needs stronger coverage for edge cases that are sensitive to script layout and ordering semantics.

## Goals
1. Expand parity coverage for CUDA-sensitive control/data paths.
2. Keep Metal bit-exact with CPU reference under complex script shapes.
3. Avoid workload/perf tuning in this phase.

## Non-Goals
1. Throughput optimization.
2. ABI or script format redesign.

## Phased Plan

### 5C.1 Multipart + Stage/Part Ordering
Red:
1. Add parity tests with multipart block scripts (`is_last_part` chaining) and mixed global-read/stage payloads.

Green:
1. Fix Metal kernel/script cursor behavior if ordering diverges.

Exit Criteria:
1. Multipart parity tests pass consistently.

### 5C.2 SRAM/CLKEN Boundary Semantics
Red:
1. Add parity tests covering multiple SRAM banks, boundary-indexed `num_ios`, and duplicate/clken interactions.

Green:
1. Fix any read-before-write or output materialization mismatch.

Exit Criteria:
1. New boundary tests pass.

### 5C.3 Randomized CUDA-Shape Parity Fuzz
Red:
1. Add deterministic randomized synthetic script parity sweep over CUDA-shape sections.

Green:
1. Resolve all discovered mismatches with minimal kernel changes.

Exit Criteria:
1. Randomized sweep passes for fixed seed set.
2. Existing parity and VCD tests remain green.

## Acceptance Criteria
1. 5C.1-5C.3 exit criteria are met.
2. `metal_parity_smoke` and `metal_vcd_e2e` pass.
3. No workload benchmark/perf changes are required for completion.

## Risks and Mitigations
1. Risk: synthetic scripts miss real regressions.
   Mitigation: combine targeted boundary cases with deterministic fuzz.
2. Risk: parity fixes introduce regressions in prior passing suites.
   Mitigation: rerun full Metal parity + VCD checks after each green step.

## Implementation Checklist
- [x] 5C.1 Red/Green complete.
- [x] 5C.2 Red/Green complete.
- [x] 5C.3 Red/Green complete.

## Execution Log
2026-03-05:
1. Created parity-focused Phase 5C PRD.
2. Added multipart parity case and helper script builder:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - `build_multipart_sram_dependency_script`
   - `metal_matches_reference_on_multipart_sram_dependency_case`
3. Added multi-SRAM boundary parity case and helper script builder:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - `build_multi_sram_boundary_script`
   - `metal_matches_reference_on_multi_sram_boundary_case`
4. Added deterministic randomized CUDA-shape parity sweep:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - `ScriptRng`, `build_random_cuda_part`, `build_random_cuda_case`
   - `metal_matches_reference_on_randomized_cuda_shape_cases` (12 fixed seeds)
5. Hardened randomized script generation to respect CUDA-script invariants:
   - hooks beyond `num_ios` forced disabled
   - SRAM address tuples constrained to in-range `[0, 8191]`
   - randomized multi-block race source removed (single-block randomized sweep)
6. Validation:
   - `cargo test --features metal --test metal_parity_smoke -- --nocapture` passed (`8` tests)
   - `cargo test --features metal --test metal_vcd_e2e -- --nocapture` passed (`1` test)
7. Added manifest-driven real-script corpus parity gate:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - new parser/helpers: `parse_baseline_manifest_cases`, `build_script_from_artifacts`
   - new test: `metal_matches_reference_on_manifest_baseline_corpus`
   - baseline corpus currently resolves to one checked-in entry (`tiny_v1`), and will auto-expand as new manifest entries are added.
8. Re-validation after adding corpus gate:
   - `cargo test --features metal --test metal_parity_smoke metal_matches_reference_on_manifest_baseline_corpus -- --nocapture` passed (`1` test)
   - `cargo test --features metal --test metal_parity_smoke -- --nocapture` passed (`9` tests)
   - `cargo test --features metal --test metal_vcd_e2e -- --nocapture` passed (`1` test)
9. Added deterministic multi-block/multi-stage disjoint parity case:
   - `external/GEM/tests/metal_parity_smoke.rs`
   - new helpers: `build_sram_stage_script_part_with_offsets`, `build_multiblock_multistage_disjoint_script`
   - new test: `metal_matches_reference_on_multiblock_multistage_disjoint_case`
10. Re-validation after multi-block parity addition:
   - `cargo test --features metal --test metal_parity_smoke metal_matches_reference_on_multiblock_multistage_disjoint_case -- --nocapture` passed (`1` test)
   - `cargo test --features metal --test metal_parity_smoke -- --nocapture` passed (`10` tests)
   - `cargo test --features metal --test metal_vcd_e2e -- --nocapture` passed (`1` test)
