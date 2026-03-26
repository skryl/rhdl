# SPARC64 W1 Runtime Unit Suite PRD

## Status

In Progress - 2026-03-09

Execution notes:
1. Phase 1 and Phase 2 infrastructure are implemented and covered with targeted specs.
2. Phase 3 staged-Verilog checks now normalize the full dependency closure, preserve the requested source file as the semantic-compare primary input, and fall back to source-local comparison when the full closure itself is not CIRCT-importable.
3. Phase 4 raised-RHDL checks now correctly allow outputless sink-style modules to remain structural/no-op and allow active-low async-reset cells to remain behavioral when the current sequential DSL cannot express them directly.
4. Phase 5 parity plumbing now compiles the original Verilog with `FPGA_SYN`, infers single-parameter module specializations for Verilator wrappers, and resolves parity-only dependency leaves from the full reference tree.
5. The SPARC64 test-session runtime import now runs with `emit_runtime_json: false`, which removes the mixed-import runtime JSON artifact work from the shared `W1` temp import and resolves the runtime-import timeout that previously blocked `WB/wb_conbus_top.v`.
6. Representative real covered sources such as `T1-common/common/swrvr_clib.v`, `T1-common/common/cmp_sram_redhdr.v`, `T1-common/common/cluster_header.v`, and `WB/wb_conbus_top.v` are green end to end.
7. The `_1`-style generated identifier bug in raised RHDL is fixed in the shared CIRCT raise path, which cleared the `cluster_header.v` runtime-export failure and exposed the remaining `Top/W1.v` blocker as a board-level compiler runtime export timeout rather than a broken raise artifact.
8. The known `Top/W1.v` board-level parity blocker is now bounded by a dedicated compiler runtime export timeout in the SPARC64 parity helper, so it pends in about 60 seconds instead of exhausting the 480-second per-example timeout.
9. Shared CIRCT flattening now reuses cached unprefixed child templates for repeated identical instances and uses set-backed net/reg membership checks instead of repeated linear scans; the new regression lives in `spec/rhdl/codegen/circt/circt_core_spec.rb`.
10. Runtime JSON normalization now reuses a simplification cache across the whole module instead of starting from a fresh simplification cache for every top-level assign/process expression; shared `runtime_json` specs remain green.
11. After those shared-code optimizations, representative SPARC64 unit specs remain green and `Top/W1.v` still specifically pends at the board-level compiler runtime export timeout, which means the remaining Phase 5 blocker is not in source staging or raised-RHDL shape.
12. Direct `W1` runtime-export timing now shows flattening is no longer the issue: `to_flat_circt_nodes` finishes in about 5 seconds, while `RuntimeJSON.normalize_modules_for_runtime([flat])` still exceeds 90 seconds on the board-level flat module.
13. The current board-level hot path is inside runtime JSON assign normalization, not the runtime-sensitive-name prepass: the flat `W1` module has 282,730 assigns, 8,966 processes, and 154,424 nets; only 13,565 signal names are currently marked runtime-sensitive, yet the assign-normalization loop still exceeds a 30-second cutoff.
14. `RuntimeJSON.dump` now prunes against the simplified reachable graph instead of the raw assign graph, which preserved `WB/wb_conbus_top.v` parity while cutting away dead-wide work earlier in the board export path.
15. The `dump` path now caches simplified signal-reference discovery directly instead of materializing simplified IR only to re-walk it for liveness; on `W1`, reachable-assign discovery dropped from timing out past 30 seconds to about 10 seconds.
16. The `dump` path now dedupes identical same-target live assigns before normalization. On `W1`, that reduces the live assign loop from 186,790 assigns to 103,084 unique assign targets; sampled and aggregate checks showed 70,122 duplicate targets with zero divergent expressions.
17. The runtime JSON focused regressions now cover the dead-wide prune path and duplicate-live-assign collapse path, and representative parity coverage like `WB/wb_conbus_top.v` remains green after those optimizations.
18. The remaining `Top/W1.v` board blocker is now in the normalize/serialize half of runtime export rather than live-target discovery: current direct probes show `runtime_live_assign_targets` at about 10 seconds on `W1`, but `normalize_module_for_runtime` still exceeds a 30-second cutoff and the overall board export still misses the 60-second parity-helper timeout.
19. The mirrored SPARC64 unit suite now lives under `spec/examples/sparc64/import/unit` to align with the repository's other import-backed unit suites.
20. `T1-common/u1/u1.V` is now part of the mirrored import/unit coverage set, and the shared staged-Verilog semantic comparer now rewrites simple gate primitives plus escaped identifiers like `\vdd!` so that source file imports from `u1.V` run green end to end.
21. `sparc_tlu_penc64.v` now normalizes to an explicit priority chain before CIRCT import, which clears the last hard `import/unit` parity failure that surfaced after `sparc_tlu_dec64.v`.
22. The suite no longer has a known hard parity failure in `import/unit`, and the parallel importer integration spec has additional timeout headroom for `pspec:sparc64`, but the PRD remained open because shared IR-compiler parity still pended on wide-signal coverage and board-level runtime-export timeouts such as `W1`, `S1Top`, and `bw_r_scm`.
23. The shared IR compiler now carries runtime signal values up to 128 bits, exports the wide-signal FFI that the Ruby wrapper already expects, and preserves wide internal packed-bus slices in compiler-generated code. The former JIT-routed `import/unit` cases at 65..128 bits now resolve to `:compiler`; targeted compiler regressions and a 35-example former-JIT SPARC64 batch are green. The remaining Phase 5 blocker is now the >128-bit / board-level runtime-export path rather than the old 64-bit compiler ceiling.
24. The latest full sequential `spec/examples/sparc64/import/unit` sweep advanced to a parity-harness red instead of a source-import parity red. Shared fixes since then now keep explicit-width sequential locals masked in simulation, keep LLHD sensitivity-loop mux cells like `dp_mux2es` combinational instead of spuriously clocking them on `sel`, and rank real reset pins like `arst_l` above reset-enable controls like `rst_tri_en` when building deterministic parity vectors. The targeted `os2wb_dual`, `sparc_exu_alu`, `swrvr_dlib`, and full `parity_helper_spec` checks are green again, but the full sequential sweep still needs another end-to-end rerun before Phase 5 can be marked green.
25. The SPARC64 parity helper no longer goes through `to_circt_runtime_json` for native-IR runtime export. It now builds flat CIRCT nodes once and serializes them through the same compact `RHDL::Sim::Native::IR.sim_json` path used by the native IR simulator more broadly, so compiler-backed and JIT-backed SPARC64 parity runs share one standard runtime payload shape. The full `parity_helper_spec`, plus representative compiler-backed (`sparc_exu_alu`) and Ruby-fallback (`os2wb_dual`) source specs, are green on that path.
26. A full sequential `spec/examples/sparc64/import/unit` sweep now runs to completion in 63 minutes 44 seconds with 443 examples and 1 failure. The only remaining red is `os2wb/s1_top.v`, where native-IR parity still falls back because `S1Top` runtime export exceeds the 60-second timeout and the fallback Verilator parity run then exceeds the 480-second example timeout. The suite is therefore down to a single board-level-style parity blocker rather than broad import/unit instability.
27. The `S1Top` native-IR runtime-export blocker is now fixed in shared `RuntimeJSON` logic. The main changes were: stop using stale 64-bit simplification thresholds after the backend widened to 128 bits, cache equivalent slice rewrites across fresh `IR::Slice` objects, and push slices down through signals/concats/muxes/resizes before fully simplifying the base expression. Direct `S1Top` export probing now shows `to_flat_circt_nodes` in about `3.0s`, `runtime_live_assign_targets` in about `5.5s`, `normalize_module_for_runtime` in about `6.8s`, and compact serialization in about `2.8s`; the targeted `spec/examples/sparc64/import/unit/os2wb/s1_top_spec.rb` is green again in about `7m45s`.

## Context

The SPARC64 importer now supports importing the board-level `W1` top from the reference tree and preserving the source-relative output layout in the raised Ruby tree. That gives us a usable whole-design import, but it still leaves a major validation gap: there is no source-backed unit suite that proves the importer handled each emitted module correctly.

The new suite needs to validate the import through the exact path users care about:

1. import the default `W1` top
2. inspect the staged Verilog that the importer actually feeds to CIRCT
3. inspect the raised RHDL that the importer actually emits
4. compare the imported RHDL behavior against the original Verilog behavior

The suite should not build a committed secondary import corpus. It should import `W1` once at test time into a temp directory, run all unit checks from that runtime import, and clean up afterward.

## Goals

1. Add a SPARC64 unit suite under `spec/examples/sparc64/import/unit`.
2. Mirror the original `examples/sparc64/reference` source layout in the unit spec tree.
3. Import the default `W1` top exactly once per RSpec process into a temp workspace/output tree.
4. Cover only modules that are both:
   - in the default `W1` source closure
   - directly emitted as source-backed imported classes by that `W1` import
5. For each covered module, prove the staged Verilog remains semantically close to the original source.
6. For each covered module, prove the raised RHDL uses the highest DSL level currently available.
7. For each covered module, prove the imported RHDL matches the original Verilog under deterministic behavioral parity checks.
8. Keep the suite in the normal `spec` run and add focused `spec:sparc64` / `pspec:sparc64` scopes.

## Non-Goals

1. Importing every SPARC64 file or module individually.
2. Covering modules that do not get emitted from the default `W1` import.
3. Creating a committed `examples/sparc64/unit_import` tree.
4. Replacing the existing SPARC64 importer integration spec.

## Public Interface / API Additions

1. New unit spec tree:
   - `spec/examples/sparc64/import/unit/`
2. New SPARC64 spec scopes:
   - `bundle exec rake spec:sparc64`
   - `bundle exec rake pspec:sparc64`
3. New shared SPARC64 spec support:
   - one-time runtime import fixture
   - emitted-module coverage inventory
   - staged-Verilog semantic checker
   - raised-RHDL DSL checker
   - IR compiler vs Verilator parity harness

## Phased Plan (Red/Green)

### Phase 1: Runtime Import Fixture And Coverage Inventory

#### Red

1. Add failing support specs for a shared SPARC64 runtime-import session.
2. Add failing checks that require:
   - one `W1` import per RSpec process
   - temp workspace/output paths available to the suite
   - generated Ruby tree loadable from the temp output
   - temp directories removed during teardown
3. Add failing inventory specs that derive the default `W1` source closure and intersect it with directly emitted source-backed imported classes.

#### Green

1. Implement shared `spec/support/sparc64` helpers that:
   - create temp workspace/output dirs
   - run `RHDL::Examples::SPARC64::Import::SystemImporter` once with default `W1`
   - keep the runtime artifacts available for all SPARC64 unit specs
   - delete the temp trees in suite teardown even on failure
2. Load the generated Ruby tree from the temp output with dependency-tolerant retries.
3. Build a coverage inventory keyed by:
   - original source file
   - original module name
   - staged Verilog path
   - generated Ruby path
   - loaded Ruby class
4. Exclude anything not directly source-backed in the emitted `W1` result, including specialization-only variants and stub-only helper outputs.

#### Exit Criteria

1. The suite performs one runtime `W1` import per RSpec process.
2. Covered modules are discoverable by original source file and original module name.
3. The temp import tree is reliably cleaned up after the test run.

### Phase 2: Mirrored Spec Layout And Coverage Lock

#### Red

1. Add failing checks for a mirrored spec tree under `spec/examples/sparc64/import/unit/...`.
2. Add failing checks that the checked-in spec inventory exactly matches the runtime emitted-source-backed `W1` inventory.

#### Green

1. Generate and check in one spec file per covered original source file, mirroring the reference directory structure.
2. Encode the expected covered module list in each mirrored spec file.
3. Make the shared helper fail loudly on coverage drift:
   - missing modules
   - extra modules
   - source-file regrouping
4. Add `spec:sparc64` and `pspec:sparc64` Rake scopes while keeping the suite in the default spec run.

#### Exit Criteria

1. The mirrored SPARC64 unit spec tree is present and stable.
2. The suite rejects unexpected changes in the emitted source-backed `W1` coverage set.

### Phase 3: Staged Verilog Semantic-Closeness Checks

#### Red

1. Add failing staged-Verilog specs that compare each covered source file’s original Verilog with the staged normalized Verilog produced by the runtime import.
2. Make the suite fail when staging changes the imported module semantics.

#### Green

1. Reuse the semantic-signature approach from `spec/rhdl/import/import_paths_spec.rb` to compare original and staged Verilog after CIRCT import normalization.
2. Run the semantic-closeness check once per covered source file and memoize it for all modules in that file.
3. Treat staged-source semantic drift as a hard failure before any RHDL or parity checks run.

#### Exit Criteria

1. Every covered source file proves the staged Verilog is semantically close to the original.
2. No stage-time normalization regression can slip through to later phases.

### Phase 4: Raised RHDL Highest-DSL Checks

#### Red

1. Add failing checks that reject degraded raise diagnostics, placeholder outputs, raw-Verilog fallbacks, or under-raised generated Ruby.
2. Add representative failures for:
   - sequential modules
   - behavioral combinational modules
   - structural wrapper modules

#### Green

1. Enforce suite-level zero degrade diagnostics for:
   - `raise.behavior`
   - `raise.expr`
   - `raise.memory_read`
   - `raise.case`
   - `raise.sequential`
2. Enforce zero placeholder-output diagnostics for the runtime import.
3. For each covered module, require:
   - generated Ruby file exists and loads successfully
   - `verilog_module_name` matches the original module
   - no raw fallback placeholder output
4. Validate the strongest available DSL surface by module shape:
   - sequential modules use `SequentialComponent`, `include RHDL::DSL::Sequential`, `sequential clock:`, and `behavior do`
   - behavioral combinational modules use `behavior do`
   - structural modules may stay structural only when they are genuine wiring/instance shells

#### Exit Criteria

1. Every covered module proves the importer raised it to the highest currently available DSL level.
2. Raise regressions fail before behavioral parity runs.

### Phase 5: Behavioral Parity Against Original Verilog

#### Red

1. Add failing parity support specs for deterministic vector generation, IR compiler execution, Verilator execution, and wide-port packing/unpacking.
2. Add failing integration coverage for representative `W1`-imported modules across board, CPU, helper, and multi-module source files.

#### Green

1. Build a shared parity harness that:
   - runs the imported RHDL class through `to_circt_runtime_json` on backend `:compiler`
   - compiles the original Verilog source plus its `W1` dependency closure with Verilator
   - applies the same deterministic vectors to both implementations
2. Support ports wider than 64 bits with multiword pack/unpack logic on the Verilator side.
3. Use a single deterministic smoke policy:
   - stable defaults for all inputs
   - common-name heuristics for clock and reset
   - bounded combinational vectors
   - bounded reset and functional cycles for sequential modules
4. Cache Verilator builds under `tmp/` keyed by module name, dependency digest, and harness version.

#### Exit Criteria

1. Every covered module matches the original Verilog on the deterministic parity trace.
2. The suite is stable enough to remain in the default spec run.

## Acceptance Criteria

1. `spec/examples/sparc64/import/unit` exists and mirrors the covered portion of the reference source tree.
2. The suite imports the default `W1` top once per RSpec process into temp storage and deletes that tree afterward.
3. Coverage is limited to the modules directly emitted as source-backed imported classes from the default `W1` import.
4. Every covered source file passes the staged-Verilog semantic-closeness gate.
5. Every covered module passes the raised-RHDL highest-DSL gate.
6. Every covered module passes IR compiler vs Verilator behavioral parity.
7. `bundle exec rake spec:sparc64` and `bundle exec rake pspec:sparc64` exist and run the SPARC64 suite.
8. Existing touched SPARC64 importer coverage remains green.

## Risks And Mitigations

1. Risk: the runtime import takes long enough to make the default suite noisy.
   - Mitigation: import once per process, cache Verilator builds, and memoize per-source semantic checks.
2. Risk: emitted coverage drifts as the importer improves.
   - Mitigation: lock the mirrored spec inventory to the emitted source-backed `W1` set and fail loudly on drift.
3. Risk: some modules are structurally raised and do not fit a simple `behavior do` rule.
   - Mitigation: classify modules by generated shape and only require structural output where it is genuinely appropriate.
4. Risk: wide ports and large buses make Verilator parity harnesses brittle.
   - Mitigation: centralize pack/unpack, mask all comparisons by declared width, and add focused support tests for wide-port handling.

## Implementation Checklist

- [x] Phase 1 red: add failing runtime-import lifecycle and inventory specs
- [x] Phase 1 green: implement one-time runtime import support and emitted coverage inventory
- [x] Phase 2 red: add failing mirrored-spec inventory checks
- [x] Phase 2 green: check in mirrored per-source SPARC64 unit specs and Rake scopes
- [x] Phase 3 red: add failing staged-Verilog semantic-closeness checks
- [x] Phase 3 green: staged Verilog checks pass for every covered source file
- [x] Phase 4 red: add failing raised-RHDL highest-DSL checks
- [x] Phase 4 green: raised-RHDL checks pass for every covered module
- [x] Phase 5 red: add failing IR compiler vs Verilator parity support checks
- [ ] Phase 5 green: parity checks pass for every covered module
- [ ] Regression: touched SPARC64 importer and Rake interface coverage are green
- [x] PRD status and checklist updated to match the current state
