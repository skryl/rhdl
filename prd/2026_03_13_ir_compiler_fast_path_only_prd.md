Status: In Progress

Context

The IR compiler backend still exposes and silently uses non-compiled fallback modes:
- runner-facing `compile_mode: :auto`
- runner-facing `compile_mode: :runtime_only`
- compiler-core runtime-only fallback selection inside the native compiler backend

That behavior violates the desired contract for the compiler backend. The compiler backend must either:
- produce a compiled fast path, or
- fail loudly and push callers toward `:jit` / other backends

Goals

- Remove runner-facing `:auto` / `:runtime_only` compiler modes from the IR compiler path.
- Make the native IR compiler backend fail instead of silently selecting runtime-only fallback.
- Update SPARC64 compile-path specs to use explicit rustc compilation.
- Keep existing non-compiler backends (`:jit`, `:interpret`) unchanged.

Non-Goals

- Solving all remaining compiled fast-path coverage gaps in this PRD.
- Changing backend selection semantics for `backend: :auto` outside compiler-mode handling.
- Reworking unrelated netlist / Verilator / Arcilator runner policies.

Phased Plan

Phase 1: Contract Cutover
- Red:
  - Add/update runner specs to reject `compile_mode: :auto` and `:runtime_only`.
  - Add/update compiler-core specs to expect loud failure when compile would need runtime-only fallback.
- Green:
  - Remove SPARC64 runner support for `:auto` / `:runtime_only`.
  - Remove compiler-core runtime-only selection from the compile path.
  - Make compiler compile requests fail with an explicit error when the fast path is unsupported.
- Exit:
  - No SPARC64 compile runner path silently selects runtime-only.
  - Compiler backend compile requests are compile-or-fail.

Phase 2: Spec Realignment
- Red:
  - Existing SPARC64 compile-path integration specs still request `:auto`.
- Green:
  - Update affected SPARC64 integration specs to request explicit `:rustc`.
  - Update runner specs and compiler specs to match the new contract.
- Exit:
  - SPARC64 compile-path spec surface reflects rustc-only policy.

Acceptance Criteria

- `compile_mode: :auto` and `compile_mode: :runtime_only` are no longer accepted for the SPARC64 IR compiler runner.
- Native IR compiler compile requests no longer silently enable runtime-only fallback.
- Compile backends either produce compiled code or raise a clear error.
- Updated targeted specs are green.

Risks and Mitigations

- Risk: existing tests or flows rely on silent runtime-only fallback.
  - Mitigation: convert those to explicit failure expectations or move them to `:jit`.
- Risk: SPARC64 compile integration becomes loudly red before wide fast-path support lands.
  - Mitigation: document that as intentional policy enforcement and isolate the next blocker clearly.

Latest Checkpoint

1. SPARC64 runner surface is now rustc-only for compile mode:
   - `examples/sparc64/utilities/runners/ir_runner.rb` rejects `:auto` and `:runtime_only`
   - `examples/sparc64/utilities/runners/headless_runner.rb` defaults compile mode to `:rustc` and rejects removed modes for `mode: :ir, sim: :compile`
2. SPARC64 integration specs are now wired to explicit rustc compile mode:
   - `spec/examples/sparc64/integration/runtime_parity_spec.rb`
   - `spec/examples/sparc64/integration/runtime_correctness_spec.rb`
   - `spec/examples/sparc64/integration/startup_smoke_spec.rb`
3. Compiler-core compile entry no longer silently selects runtime-only:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/ffi.rs` now errors if `RHDL_IR_COMPILER_FORCE_RUNTIME_ONLY` is set
   - compiler compile requests now fail when `compile_fast_path_blocker(...)` reports unsupported fallback requirements
4. Compiler-core runtime-only branch removal is partially landed:
   - the runtime-only setter/call path is gone from compile entry
   - dead `runtime_only` state branches were removed from the core compile/evaluate path
   - internal naming was shifted away from `requires_runtime_only` to `has_overwide_tick_helper_state`
5. Targeted validation is green:
   - `bundle exec rspec spec/examples/sparc64/runners/ir_runner_spec.rb spec/examples/sparc64/runners/headless_runner_spec.rb --order defined`
   - `cargo test --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml reports_fast_path_blockers_for_runtime_fallback_assigns -- --nocapture`
6. Native compiler dylib loading was repaired on Darwin:
   - `lib/rhdl/sim/native/ir/simulator.rb` now prefers Cargo release cdylibs (`target/release/lib*.dylib`) over the staged `lib/*.dylib` copies when they exist
   - that fixes a local compiler-backend load regression where `Fiddle.dlopen` of the staged compiler dylib aborted the process before compile even started
   - focused validation is green:
     - `bundle exec rspec spec/rhdl/sim/native/ir/simulator_load_spec.rb --order defined`
7. Native compiler failure reporting is loud again:
   - `lib/rhdl/sim/native/ir/simulator.rb` now passes through the native `sim_exec(SIM_EXEC_COMPILE)` error string instead of collapsing all failures to a generic message
   - focused validation is green:
     - `bundle exec rspec spec/rhdl/sim/native/ir/simulator_load_spec.rb --order defined`
8. Current real SPARC64 blocker after the contract change:
   - `HeadlessRunner.new(mode: :ir, sim: :compile, fast_boot: true, compile_mode: :rustc)` now fails immediately and loudly instead of silently degrading
   - current native blocker text is:
     - `compiled fast path requires runtime fallback for 5912 combinational assigns`
     - first targets:
       - `sparc_0__ffu__cpx_vld__bridge`
       - `sparc_0__ffu__cpx_req__bridge`
       - `sparc_0__ffu__cpx_fpu_data__bridge`
       - `sparc_0__ffu__cpx_fpexc__bridge`
       - `sparc_0__ffu__cpx_fcmp__bridge`
       - `sparc_0__ffu__cpx_fccval__bridge`
       - `sparc_0__ff_cpx__cpx_spc_data_cx3`
       - `sparc_0__ifu__wseldp__icd_wsel_fetdata_s1__bridge`
   - runtime payload analysis on the current `s1_top.runtime.json` shows the blocker is structurally concentrated:
     - total assigns: `120677`
     - direct wide-target assigns: `279`
     - wide-target kinds: `signal=175`, `expr_ref=97`, `literal=7`
   - the remaining work is therefore not policy cleanup anymore; it is compiled fast-path support for structural `129..256` bit packet transport on the real SPARC64 design
9. Structural `129..256` transport support is now partially landed in the compiled fast path:
   - focused compiler reds are green:
     - `spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb -e 'captures and slices a 145-bit packet register on the compiler backend'`
     - `spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb -e 'captures and slices a 256-bit packet register on the compiler backend'`
     - `spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb -e 'supports slices above bit 127 on the compiler backend'`
     - `spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb -e 'preserves wide bridge nets into a 145-bit sequential capture on the compiler backend'`
   - the compiled evaluator now carries fixed high-word transport for structural `129..256` bit signals and no longer rejects those packet-style probes outright
10. Fast-boot SPARC64 now emits and reuses importer-produced runtime JSON artifacts:
   - `examples/sparc64/utilities/integration/import_loader.rb` now builds fast-boot trees with `emit_runtime_json: true`
   - `examples/sparc64/utilities/runners/ir_runner.rb` now accepts importer-produced `runtime_json_path` artifacts from `import_report.json` even when there is no Ruby serializer signature
   - this avoids regenerating runtime JSON from the raised Ruby tree when a direct importer artifact is available
11. Fresh SPARC64 compile blocker after the importer-runtime-json handoff:
   - on the fresh fast-boot import tree `tmp/sparc64_import_trees/7b3d899db4e9f721c630c492b6904dda18742aa56a130960efeb7735ba67235f`
   - the direct importer runtime JSON no longer contains `rt_tmp_13_1440`
   - the compiled constructor now fails on only `76` remaining combinational assigns
   - first targets:
     - `sparc_0__lsu__stb_cam.stb_ld_full_raw`
     - `sparc_0__lsu__stb_cam.stb_ld_partial_raw`
     - `sparc_0__lsu__stb_cam.stb_cam_hit_ptr`
     - `sparc_0__lsu__stb_cam.stb_cam_hit`
     - `sparc_0__lsu__stb_cam.stb_cam_mhit`
     - `sparc_1__lsu__stb_cam.stb_ld_full_raw`
     - `sparc_1__lsu__stb_cam.stb_ld_partial_raw`
     - `sparc_1__lsu__stb_cam.stb_cam_hit_ptr`
   - the active remaining work is now the narrow `stb_cam` output reduction logic, not stale `1440`-bit shadows or generic wide packet transport
12. Compiler fast path now supports narrow slices from signals wider than 256 bits:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` now carries a read-only overwide signal pointer table into generated Rust
   - compiled code can now lower narrow slices from `>256`-bit sequential state without routing those assigns to runtime fallback
   - focused validation is green:
     - `spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb -e 'captures narrow slices from a >256-bit register on the compiler backend'`
13. The previous `stb_cam` blocker set is gone:
   - the fresh SPARC64 compiled constructor on `tmp/sparc64_import_trees/0fffcd5e858aefc0cab72ff34a0ab98850a48786a9f0dcf04259156a8ce5b95d/s1_top.runtime.json` no longer fails on the old `76` assign set
   - the next remaining blocker narrowed to just two FPU assigns:
     - `fpu_inst__fpu_mul__fpu_mul_frac_dp__i_m5stg_frac_pre3__din`
     - `fpu_inst__fpu_mul__fpu_mul_frac_dp__i_m5stg_frac_pre4__din`
14. Wide `129..256` shift-right is now compiled directly:
   - the compiled wide tier now lowers `<<` and `>>` for `129..256`-bit expressions instead of rejecting them
   - that clears the two remaining fast-path blockers above
15. Current SPARC64 state after the wide-slice and wide-shift fixes:
   - the fresh compiled constructor no longer fails fast on unsupported combinational assigns
   - it now proceeds into a real rustc compile of the full generated SPARC64 unit
   - the active bottleneck has moved from semantic fallback blockers to compile-time scaling of the generated Rust source
16. Focused validation after the latest compiler changes is green:
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb --order defined`
   - `bundle exec rspec spec/examples/sparc64/runners/ir_runner_spec.rb spec/examples/sparc64/runners/headless_runner_spec.rb --order defined`
17. Policy-aligned spec update:
   - the old `130`-bit memory-read compiler probe now asserts loud compile failure instead of expecting fallback-backed success
   - this keeps the focused suite aligned with the repo-wide `compile or fail` policy
18. Large narrow concat codegen no longer always emits a single giant inline expression:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` now materializes large narrow concats into `let mut concat_*` builders
   - focused validation is green:
     - `spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb -e 'materializes large distinct narrow concat patterns on the compiler backend'`
19. Narrow compare/mux and slice codegen now use compact helpers:
   - generated Rust now emits:
     - `bool_to_u128(...)`
     - `mux_u128(...)`
     - `slice_u128(...)`
     - `signal_slice_u128(...)`
   - focused validation is green:
     - `spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb -e 'uses compact helpers for narrow compare and mux patterns on the compiler backend'`
20. Real SPARC64 emitted-source shape improved, but rustc compile time is still the blocker:
   - fresh AOT emission from `tmp/sparc64_import_trees/0fffcd5e858aefc0cab72ff34a0ab98850a48786a9f0dcf04259156a8ce5b95d/s1_top.runtime.json` now produces:
     - `tmp/sparc64_codegen_probe.rs`
     - about `84.83 MiB`
     - `522627` lines
   - relative to the earlier `~89.45 MiB` emitted unit, helper compaction materially reduced source size while preserving the compile-or-fail backend contract
   - the worst individual assignment lines are still too large:
     - current max line length is about `2.46M` characters
     - earlier baseline was about `2.70M`
   - selective materialization now hits the intended small set of pathological roots:
     - hot narrow roots like `e876212`, `e26522`, `e1229923`, `e1435952`, and `e1588053` are emitted as temps instead of being fully re-inlined at their final store sites
   - direct `rustc` probing on the emitted file is improved but still not good enough:
     - after about `2m28s`, `rustc` was still live
     - resident set stayed around `3.57 GiB`
     - no output dylib was produced before the probe was stopped
   - so the active blocker remains compile-time scaling of the generated Rust source, not semantic fast-path coverage
21. Current remaining hotspot shape:
   - the largest remaining expressions are no longer raw `if` ladders; they are huge narrow packet/compare trees dominated by:
     - repeated `bool_to_u128(...)`
     - repeated `mux_u128(...)`
     - repeated `slice_u128(...)`
     - repeated `<<`-based narrow bit packing
   - the next likely win is a dedicated lowering for those repeated narrow pack trees rather than more generic helper substitution
22. Narrow single-bit materialization tightened the real SPARC64 hot chain materially:
   - the width-1 selective materialization threshold was lowered from `32768` to `8192`
   - this did not break the focused compiler/SPARC64 suite
   - on the real emitted `tmp/sparc64_codegen_probe.rs`, the worst STB-CAM subchain temps dropped sharply:
     - `e40511`: about `1.87M` chars -> about `35` chars
     - `e890201`: about `1.89M` chars -> about `38` chars
     - `e1435953`: about `1.90M` chars -> about `41` chars
     - `e1588054`: about `1.90M` chars -> about `41` chars
   - the remaining largest lines are now about `477k` chars, down from the prior `~1.9M` subchain lines
23. Direct rustc profiling after the width-1 change shows a materially better large-design shape:
   - `codegen-units=256` on the emitted SPARC64 probe now enters a low-memory late phase instead of staying in multi-gigabyte front-end pressure:
     - about `2.34 GiB` RSS at `00:48`
     - about `184 MiB` RSS at `01:27`
     - about `341 MiB` RSS at `02:54`
     - about `106 MiB` RSS at `04:08`
   - the compile still did not finish within the interactive budget, but the profile is materially better than the earlier `3.5+ GiB` sustained front-end regime
24. Large-design rustc profile comparison:
   - `codegen-units=64` is worse than `256` for the current SPARC64 emitted unit
   - on the same probe file:
     - `64` CGUs held around `3.0 GiB` RSS at `00:40` and stayed around `3.0 GiB` at `01:17`
     - `256` CGUs reached a much lower front-end peak and transitioned into a low-memory late phase
   - so the current large-design profile should stay on `codegen-units=256` for now
25. Additional profiling and source-shape checkpoints:
   - lowering the width-1 materialization threshold from `8192` to `4096` reduced the largest emitted lines further, but it made the direct `rustc` front-end profile worse, so that experiment was reverted
   - the current width-1 threshold is back at `8192`
   - on the current emitted probe file:
     - file size is about `84.85 MiB`
     - line count is about `523546`
     - the old width-1 STB-CAM temp chains remain tiny:
       - `e40511 = 35 chars`
       - `e890201 = 38 chars`
       - `e1435953 = 41 chars`
       - `e1588054 = 41 chars`
     - the largest remaining lines are about `345k` chars
   - however, a fresh direct `rustc` probe on this latest emitted shape still held around `3.55 GiB` RSS through about `01:55`, so the source-shape improvement is real but not yet sufficient to make compile time acceptable
26. More profile checks:
   - `codegen-units=512` is also worse than `256` on the same SPARC64 probe file:
     - about `3.55 GiB` RSS at `00:51`
   - `target-cpu=generic` is worse than `target-cpu=native` on the same probe file:
     - about `3.56 GiB` RSS at `00:46`
   - so the current best-known large-design profile remains:
     - `opt-level=0`
     - `codegen-units=256`
     - `target-cpu=native`

Implementation Checklist

- [x] Phase 1 red tests updated
- [x] Phase 1 green implementation landed
- [x] Phase 1 exit criteria validated
- [x] Phase 2 red tests updated
- [x] Phase 2 green implementation landed
- [ ] Phase 2 exit criteria validated
- [ ] Acceptance criteria validated
