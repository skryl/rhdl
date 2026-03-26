# SPARC64 `s1_top` Integration Runtime Parity PRD

## Status

In Progress - 2026-03-09

## Context

The SPARC64 import/unit suite is now broad enough to validate individual imported modules, but it does not yet prove that an imported SPARC64 system behaves correctly at runtime on real programs.

The next gate is higher-level parity on the imported `s1_top` system across five execution artifacts:

1. staged Verilog executed with Verilator
2. staged Verilog lowered through `circt-verilog` and executed with Arcilator
3. imported RHDL executed on the native IR compiler backend
4. imported RHDL re-emitted through `to_mlir` and executed with Arcilator
5. imported RHDL re-emitted through `to_verilog` and executed with Verilator

Unlike the AO486 fetch-only parity harness, this suite must run memory-resident SPARC64 programs through the backend memory ABI rather than a ROM-only stub. The current native runner ABI already supports this pattern for other systems, but `s1_top` parity now needs one shared runtime contract exercised through both original staged sources and RHDL re-exported sources.

The integration suite should follow the repository's existing benchmark pattern and run three compact but non-trivial programs:

1. `prime_sieve`
2. `mandelbrot`
3. `game_of_life`

Each program must live in DRAM, execute through the real `s1_top` Wishbone master interface, and report completion through a stable mailbox contract. The boot path may use a flash-resident shim, but the benchmark itself must be memory-backed and runtime-loaded through the runner ABI.

## Current Execution Notes

1. Phase 1 is implemented and validated locally:
   - native compiler `:sparc64` runner detection is in place
   - sparse flash/DRAM load/read/write APIs are wired through the normalized runner ABI
   - acknowledged Wishbone trace and unmapped-access probes are exposed through the compiler backend
2. Phase 2 is largely implemented and validated locally:
   - `HeadlessRunner`, `IrRunner`, `VerilogRunner`/`VerilatorRunner`, the benchmark registry, and the split boot/program image builder all exist
   - focused runner specs are green
   - the staged Verilator wrapper now mirrors the boot image to low DRAM again and exposes flash bytes through `read_memory`
   - the staged `s1_top` fast-boot source edits now flow through the SPARC64 importer `patches_dir:` path instead of ad hoc staged-tree text rewriting, and the focused importer/bundle specs are green
3. The importer-managed fast-boot import path now stages `os2wb/s1_top.v` correctly without duplicating a basename-level `s1_top.v` copy:
   - the duplicate-top regression is covered in the SPARC64 importer spec
   - the patched import tree now gets through Verilog->CIRCT->RHDL generation cleanly
4. The current staged-Verilog Phase 3 blocker is still the boot shim itself:
   - the importer-managed fast-boot patch series was tightened so the synthetic WAKEUP CPX packet is no longer suppressed in the staged bundle
   - the staged-bundle regression is green with the current patch-set shape, but the real sequential Verilator smoke spec is still red
   - the low-address boot line now reaches the staged wrapper with the expected instruction words, and the current fast-boot tree no longer fails on patch application, importer staging, or malformed runtime export
   - the remaining red is specific to IFU startup control: the shim line is re-fetched from low alias `0x0/0x8/0x10/0x18`, but control-transfer out of that line still does not redirect fetch into the DRAM benchmark image
   - focused code review of the IFU path points to two structural issues still open:
     - the `0001` startup patch was originally stretching `start_on_rst` into a long mode rather than a one-shot pulse, which risks violating the normal `load_bpc`/`load_pcp4` exclusivity around branch redirection
     - even after narrowing that pulse, the boot-shim line is still not handing off, which leaves the uncached fast-boot IFILL semantics themselves as the likely remaining control-path blocker
   - a competing debug mode that mirrors the full program at low alias `0` does fetch the real program bytes, but it still stores to address `0` instead of `MAILBOX_STATUS`; focused code review suggests that mode is fighting the hardcoded fast-boot PC rewrite patches rather than exposing a generic LSU effective-address bug
5. The staged fast-boot path has now been simplified away from executing uncached boot-PROM code:
   - the fast-boot reset vector now targets DRAM directly at `PROGRAM_BASE`
   - the benchmark image builder now prefixes four `nop` instructions so the first useful `_start` instruction lands where the current reset path actually begins decoding
   - the always-on thread-0 next-thread override was narrowed to the startup pulse only
   - focused staged-bundle and image-builder specs are green with this shape
6. The current staged-Verilog blocker is no longer control-transfer into DRAM:
   - direct probes now show the core executing real DRAM program instructions, including the benchmark `sethi` prologue
   - the remaining red is early architectural state after reset: address-building still collapses into a store at address `0`, so mailbox completion never occurs
   - focused code review and explorer traces point at remaining thread / AGP / current-thread canonicalization around `sparc_ifu_fcl`, `sparc_ifu_swl`, and `tlu_tcl`, not at the memory ABI or runtime export path
6a. Current unblocker work-in-progress:
   - hard thread-selection and AGP forcing in fast-boot patches `0011` (`sparc_ifu_fcl`), `0012` (`tlu_tcl`), and `0013` (`sparc.v`) has been relaxed to remove forced `thread0` defaults
6b. The staged-Verilog runner now has a real benchmark-execution smoke gate:
   - `HeadlessRunner(mode: :verilog)` completes `prime_sieve` through the normal memory-backed benchmark loader and reaches the expected mailbox value
   - the new focused integration smoke is green with no unmapped accesses
   - parity remains deferred; this checkpoint only locks “one runner executes a real program end to end”
7. The current IR-side blocker is no longer just cold compile latency:
   - compiler-backed `S1Top` currently fails before simulation starts because the imported design still contains real over-`128`-bit state, starting with `145`-bit CPX literals in `os2wb` and reaching widths of `1440` bits in LSU paths
   - `IrRunner` now raises that blocker explicitly instead of surfacing a later compact-JSON parse failure
7a. The raw-width blocker was narrower than it looked:
   - `IrRunner` was checking the raw flattened CIRCT IR, but the actual compiler input first goes through runtime normalization with `compact_exprs: true`
   - after that normalization, the imported `S1Top` runtime payload still contains over-`128`-bit state but no longer contains non-zero over-`128`-bit literals
   - the runner width gate has now been aligned with that normalized runtime payload, and the focused SPARC64 runner spec covering a raw-overwide-but-runtime-safe slice/mux path is green
7b. The current IR-side functional blocker is now post-reset runtime behavior:
   - on the compiler backend `:auto` path, the imported `S1Top` now releases the reset chain correctly (`cluster_grst_l`, `ifu__grst_l`, and `rstff_q` all go high)
   - however by cycle `500` the IR run still shows zero acknowledged Wishbone traffic and zero mailbox progress, while the staged Verilator run has already emitted `122` acknowledged low-address writes starting at cycle `134`
   - normalized runtime expressions for `os2wb_inst__cpx1_ready`, `os2wb_inst__wb_cycle`, and `os2wb_inst__wb_addr` are not constant-folded to zero and stay within the native `128`-bit ceiling (`max_width: 124`), so the remaining blocker now points at runtime evaluation of bridge/local state rather than exporter literal lowering
7c. Runtime primitive semantics and stale generated bridge wiring have been tightened on the checked-in import tree:
   - the imported `T1-common/u1` cell shims for `buf`, `minbuf`, `inv`, `nand`, `nor`, `aoi`, `muxi`, and `soffm2` now implement real compiler-backed runtime behavior, with focused runtime specs green
   - the most obvious stale importer-output bridge bugs in `lsu_qctl1`, `sparc_ifu_ifqctl`, and `sparc_ifu_fcl` have been patched away from hardwired zero outputs, with focused wiring regressions green
   - despite those fixes, the checked-in import tree still shows zero acknowledged Wishbone traffic and zero mailbox progress by cycle `200` on compiler-backed `prime_sieve`
7d. A cleaner fresh-import-tree path is now partially unblocked:
   - compiler runtime-only support now parses and evaluates over-`128`-bit negative literals from runtime JSON, covered by a focused compiler spec
   - after that fix, the fresh importer-generated `S1Top` no longer dies on overwide literal parsing, but it still fails before simulation because the compiler runtime-only path rejects over-`128`-bit memories
   - the remaining fresh-tree blocker is narrow and concrete: two `130`-bit FIFO memories in `os2wb`
     - `cpu__os2wb_inst__pcx_fifo_inst__mem`
     - `cpu__os2wb_inst__pcx_fifo_inst1__mem`
7e. Shared importer memory recovery improved again on the real `s1_top` path:
   - the shared CIRCT importer now rewrites dead packed shadow regs that only alias an existing `seq.firmem` into literal-address `MemoryRead`s
   - that behavior is covered by a new focused importer spec
   - on the real `s1_top.core.mlir`, `bw_r_scm` no longer leaves behind the synthetic `1440`-bit `rt_tmp_13_1440` state
   - the remaining over-`128`-bit signals are now the true `145`/`151`/`155`-bit datapaths and packet registers, not the old packed-memory artifact
7f. The forced compiled runner path has improved, but it is not green yet:
   - `HeadlessRunner.new(mode: :ir, sim: :compile, compile_mode: :rustc)` now constructs successfully on the current tree instead of failing immediately during setup
   - benchmark image load also succeeds on that forced compiled path
   - a full forced-compile startup probe still ran for multiple minutes without reaching a completion result, so the blocker has shifted from immediate compile rejection to runtime throughput / longer-path validation
7g. The compiler backend now has a smaller fixed-width overwide path for `129..256` bits:
   - the compiler runtime layer now uses a fixed `Wide256` representation for `129..256`-bit values instead of heap-allocating `Vec<u64>` limbs for every operation in that band
   - the existing `<=128` `u128` path remains unchanged
   - widths above `256` still use the old generic multiword fallback
   - targeted compiler specs are green for `130`, `139`, `145`, and `256`-bit packet/memory/runtime cases, along with the focused SPARC64 runner unit specs
   - a broad SPARC64 startup smoke rerun was still inconclusive, so this is a backend-internal improvement checkpoint rather than a proven end-to-end speed win yet
7h. The same `129..256` signal access path now works across interpreter, JIT, and compiler backends:
   - interpreter and JIT now share the same runtime-value representation and word-addressable signal access surface used by the compiler path for `>128`-bit signals
   - the Ruby native IR wrapper now routes `>128`-bit poke/peek through per-word FFI instead of truncating to the legacy two-word `sim_signal_wide` API
   - focused native IR specs are green for `128`-bit round-trip behavior on interpreter/JIT and `256`-bit slice access on interpreter/JIT/compiler
8. Cold compile latency remains a secondary IR-side issue for imported `S1Top`:
   - compiler codegen was reduced from roughly `70 MB / 1.13M` lines to roughly `48 MB / 840k` lines by removing dead generic tick-helper emission and chunked evaluate duplication for large plain cores
   - a cold `rustc` compile for that generated unit still runs for multiple minutes, so the compiler-backed integration path is not yet practical for the slow suite without further work
8a. A new SPARC64 Arcilator compile probe now exists, and the shared ARC-prep path is through:
   - `examples/sparc64/utilities/runners/arcilator_runner.rb` drives the imported `s1_top.core.mlir` through ARC preparation and Arcilator lowering as a compile-focused runner
   - focused unit coverage for that probe runner is green
   - the first known FPU scan feedback edge is still cut by `0023-fast-boot-break-fpu-scan-loop.patch` under `NO_SCAN`
   - the decisive follow-up fix was shared tooling, not another SPARC-only patch:
     - `lib/rhdl/codegen/circt/tooling.rb` now runs `circt-opt --canonicalize --cse` on flattened HWSeq before `--convert-to-arcs`
     - that cleanup collapses the dead scan-only combinational loop that was still surviving into flattened `s1_top`
   - on the current fast-boot `s1_top` import tree, ARC preparation now succeeds and Arcilator emits LLVM IR/state output
   - observed real probe timing on the current tree:
     - ARC prep: about `3.8s`
     - Arcilator lowering: about `3.9s`
   - that means the imported SPARC64 MLIR now compiles through the Arcilator path instead of failing earlier than the Rust compiler path
8b. The SPARC64 Arcilator probe now also has a minimal JIT execution path:
   - `examples/sparc64/utilities/runners/arcilator_runner.rb` accepts `jit: true`
   - in that mode it links the emitted Arcilator LLVM IR with a tiny `s1_top` smoke wrapper through `llvm-link` and runs it with `lli --jit-kind=orc-lazy`
   - the current path is intentionally minimal: it clocks `sys_clock_i`, drives reset / Wishbone return inputs low, and reports the top-level Wishbone outputs after the requested cycle count
   - focused runner specs are green for the new JIT build and smoke path
   - observed real probe timing on the current tree for `32` cycles / `4` reset cycles:
     - ARC prep: about `3.8s`
     - Arcilator lowering: about `3.8s`
     - JIT link: about `0.16s`
     - smoke output: `JIT_OK cycles=32 reset_cycles=4 wbm_cycle_o=0 wbm_strobe_o=0 wbm_we_o=0 wbm_addr_o=0 wbm_data_o=0 wbm_sel_o=0`
8c. The SPARC64 Wishbone/memory runtime contract is now partially shared between Verilator and Arcilator:
   - `examples/sparc64/utilities/runners/shared_runtime_support.rb` now owns the shared Ruby-side `sim_*` FFI binding, image-loading behavior, mailbox helpers, Wishbone trace decode, and unmapped-access decode
   - `examples/sparc64/utilities/runners/verilator_runner.rb` now uses that shared adapter layer instead of carrying its own duplicate Ruby runtime bindings
   - `examples/sparc64/utilities/runners/arcilator_runner.rb` now has a real compile-mode runtime path built on the same `sim_*` contract:
     - Arcilator still emits LLVM IR/state from imported `s1_top`
     - the runner then compiles a SPARC64 runtime wrapper plus the emitted LLVM IR into a shared library
     - that shared library exposes `sim_create`, `sim_reset`, `sim_load_flash`, `sim_load_memory`, `sim_run_cycles`, trace copy, and fault copy like the Verilator path
   - direct compile-mode runtime probes are now working:
     - image load succeeds
     - `run_cycles(20)` succeeds
     - `run_until_complete(max_cycles: 500, batch_cycles: 100)` succeeds as a timeout result and records acknowledged Wishbone traffic (`trace_len: 7`) with no unmapped accesses
   - JIT is still smoke-only; it does not yet expose the full SPARC64 runtime contract used by the parity suite
8d. The SPARC64 native runner now advances both clock phases instead of only the main rising edge:
   - a new focused regression in `spec/rhdl/sim/native/ir/sparc64_runner_extension_spec.rb` drives a Wishbone read from a state bit clocked by `sys_clock_i ^ 1`
   - that regression was red on all three native backends (`interpreter`, `jit`, `compiler`): the request never became visible and `done` stayed `0`
   - `lib/rhdl/sim/native/ir/ir_interpreter/src/extensions/sparc64/mod.rs`, `lib/rhdl/sim/native/ir/ir_jit/src/extensions/sparc64/mod.rs`, and `lib/rhdl/sim/native/ir/ir_compiler/src/extensions/sparc64/mod.rs` now drive each SPARC64 cycle as:
     - low phase via `tick_forced`
     - high phase via `tick_forced`
   - the compiler core now exposes `tick_forced` with the same old-clock semantics already used by the interpreter/JIT runtimes
   - the focused SPARC64 runner-extension suite is green again across all three backends, which is the first verified fix for the imported `bw_r_scm` style inverted-clock path
   - this has not yet been validated end-to-end on full `prime_sieve` execution: a real `S1Top` `runtime_only` probe still needed about `30s` just for runner construction/image load and did not reach a useful `600`-cycle checkpoint quickly enough to call the complex-program path green
8e. The SPARC64 IR runner now reuses cached runtime JSON from the import tree instead of regenerating it every time:
   - `examples/sparc64/utilities/runners/ir_runner.rb` now prefers `import_report.json -> artifacts.runtime_json_path`
   - if that artifact is missing but the runner has an import tree, it emits `.mixed_import/<top>.runtime.json` once with `RuntimeJSON.dump_to_io(..., compact_exprs: true)` and records it back into `import_report.json`
   - focused coverage was added in `spec/examples/sparc64/runners/ir_runner_spec.rb`
   - on the current cached `s1_top` import tree:
     - `load_component_class`: about `1.2s`
     - `to_flat_circt_nodes`: about `4.2s`
     - `sim_json`: about `15.9s`
     - `Simulator.new`: about `6.8s`
   - after seeding the cached runtime JSON, the same `IrRunner.new(... backend: :interpret ...)` path dropped to about `7.5s` startup on the same import tree instead of about `28s`
8f. Real SPARC64 runtime probing is now narrowed to a post-`454` IFQ divergence:
   - on the cached compiler `runtime_only` path, the real `prime_sieve` run still takes about `42.7s` per `100` cycles, so full benchmark completion is not practical yet for tight debug loops
   - direct `100`-cycle checkpoints now show:
     - `100..400`: both native IR and Verilator remain in the initial `PC=0x8000` / no-request state
     - `500`: native IR is at `fetch_pc_f=0x8004`, thread state `[1,0,0,0]`, `ifu_lsu_pcxreq_d=0`
     - `500`: Verilator is already at `fetch_pc_f=0x8008`, `wm_imiss=1`, `req_valid_d=1`, `req_pending_d=1`, `ifu_lsu_pcxreq_d=1`, `nextreq_valid_s=1`
   - a tighter single-cycle comparison around `450..455` shows the native and Verilator paths actually agree on the first `mil0` request/accept pulse:
     - both go `milstate 0 -> 12` at `451`
     - both pulse `lsu_ifu_pcxpkt_ack_d` at `453`
     - both drop back to `milstate 8` at `454`
   - that means the remaining divergence is no longer the earlier `mil0` accept transition; it is the later IFQ request-valid / pending path that reasserts by `500` in Verilator and stays dead in native IR
8g. A real runtime-export bug on wide bridge nets was found and fixed in the shared runtime JSON path:
   - isolated imported `SparcIfuIfqdp` was red on all three native backends: driving `lsu_ifu_cpxpkt_i1[144]=1` through the LSU bypass path still left `ifd_ifc_cpxvld_i2=0`
   - the flattened CIRCT IR for `SparcIfuIfqdp` was correct, but `RuntimeJSON` pruned the over-`128`-bit `ifq_bypmux_dout` / `ifq_bypmux__dout` bridge chain out of the emitted runtime module while leaving `ifqop_reg__din` pointing at that bridge net
   - `lib/rhdl/codegen/circt/runtime_json.rb` now preserves raw live refs for targets wider than the native simplification ceiling instead of inlining through them and dropping their bridge assigns
   - focused coverage was added in:
     - `spec/rhdl/codegen/circt/runtime_json_spec.rb`
     - `spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb`
   - after that fix, the isolated `SparcIfuIfqdp` path is green again on `interpreter`, `jit`, and `compiler`: bit `144` is captured into `ifqop_reg_q` and `ifd_ifc_cpxvld_i2` rises as expected
8h. The SPARC64 runtime JSON cache is now versioned, and the refreshed full-system probe moves the remaining mismatch earlier:
   - `examples/sparc64/utilities/runners/ir_runner.rb` now records a `runtime_json_export_signature` in `import_report.json` and regenerates `.mixed_import/<top>.runtime.json` when the exporter changes instead of silently reusing stale runtime JSON
   - focused cache-invalidation coverage was added in `spec/examples/sparc64/runners/ir_runner_spec.rb`
   - after refreshing the cached `s1_top.runtime.json`, the compiler `runtime_only` path improved from about `42.7s` to about `38.2s` per `100` cycles on the current `prime_sieve` probe
   - a corrected staged-Verilog comparison now shows:
     - Verilator stays quiet through `400` cycles and first moves at `500`
     - compiler `runtime_only` also stays quiet through `400`, so the earlier `100..300` “PC mismatch” was based on probing a non-exported native signal name
   - at `500`, the real remaining mismatch is:
      - Verilator: `wm_imiss=1`, `mil0_state=12`, `ifu_lsu_pcxreq_d=1`
      - compiler `runtime_only`: `wm_imiss=0`, `mil0_state=12`, `ifu_lsu_pcxreq_d=1`
   - isolated imported `SparcIfuThrcmpl` is green on all three native backends for the minimal “set and hold `wm_imiss[0]` on thread-0 imiss” case, so the next bug is upstream of the wait-mask completion block rather than in that block itself
8i. The corrected exported-signal comparison closes the old early-boot parity branch:
   - the earlier native-vs-Verilator `fetch_pc_f` mismatch was partly a bad probe: `sparc_0__ifu__fdp__fetch_pc_f` is not exported by the native runtime model, so the earlier `0` samples there were not meaningful
   - the correct native PC surface is `sparc_0__ifu__fdp__fdp_erb_pc_f` / `pcf_reg_q`
   - on the refreshed compiler `runtime_only` path, the directly comparable IFU/FDP/compl signals now line up with staged Verilog at the sampled checkpoints:
     - `500`: `fdp_erb_pc_f=32776`, `mil0_state=12`, `ifq_dtu_thrrdy=0`, `ifq_dtu_pred_rdy=0`, `ifd_ifc_cpxvld_i2=0`, `ifu_lsu_pcxreq_d=1`, `compl_wm_imiss=1`, `compl_completion=0`
   - `600`: `fdp_erb_pc_f=65556`, `mil0_state=8`, `ifq_dtu_thrrdy=0`, `ifd_ifc_cpxvld_i2=0`, `ifu_lsu_pcxreq_d=0`, `compl_wm_imiss=1`, `compl_completion=0`
   - `700`: `fdp_erb_pc_f=65572`, `mil0_state=8`, `ifq_dtu_thrrdy=0`, `ifd_ifc_cpxvld_i2=0`, `ifu_lsu_pcxreq_d=0`, `compl_wm_imiss=1`, `compl_completion=0`
   - the sampled Verilator checkpoints match those values on the same conceptual surfaces, so the old “native diverges before first IFQ refill” diagnosis is no longer supported by the corrected probes
   - the next blocker is back at higher level: proving a full benchmark correctness/parity cell completes on the refreshed compiler path without relying on stale runtime JSON caches
8j. `compile_mode: :auto` is now behaving like a real full native compile path again, and that compile step is currently too expensive for interactive use:
   - after the runtime JSON cache invalidation fix, `HeadlessRunner(mode: :ir, sim: :compile, compile_mode: :auto)` blocks inside native `Simulator#compile` during runner construction instead of immediately behaving like the old cached runtime-only path
   - the refreshed SPARC64 auto compile is generating a new cached Rust source under `/var/folders/.../T/rhdl_cache/`, but the matching cached dylib is not being materialized quickly enough to make constructor time reasonable
   - a direct manual `rustc` of the current refreshed `s1_top` source (`rhdl_ir_f657a73cb3ca8ce9...rs`, about `26 MiB`) with the backend’s current flags (`opt-level=2`, `codegen-units=64`, `target-cpu=native`) was still running after about `2m55s` before being interrupted
   - that means the current blocker for higher-level `compile_mode: :auto` benchmark correctness/parity is no longer the early IFU parity bug; it is the cost of the full native compile itself on the refreshed `s1_top` payload
8k. The native compiler now uses an adaptive rustc profile for very large generated units, but SPARC64 auto compile cache misses are still expensive:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` now switches generated units above `8 MiB` onto a cheaper rustc profile:
     - `opt-level=0`
     - `codegen-units=256`
     - `target-cpu=native`
   - smaller generated units keep the existing profile:
     - `opt-level=2`
     - `codegen-units=64`
     - `target-cpu=native`
   - focused Rust unit coverage was added in the `ir_compiler` crate and is green, and the Ruby-side compiler/runner specs remain green after rebuilding `native:build[ir_compiler]`
   - on the current refreshed SPARC64 cache-miss source, a direct manual compile with the cheaper profile still took about `1m28s`, which is materially better than the earlier roughly `2m55s` `opt-level=2` compile but still not cheap enough for interactive iteration
   - a clean `HeadlessRunner(mode: :ir, sim: :compile, compile_mode: :auto)` run now emits the new adaptive-profile cache key (`rhdl_ir_ffd67aff6897ce78...rs`), so the heuristic is active on the real SPARC64 path even though the full compile is still too slow to wait out casually
8l. `compile_mode: :auto` is now practical again for refreshed SPARC64 startup because it prefers runtime-only for very large plain designs:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` now routes large plain cores onto runtime-only automatically when `ir.exprs.len() > 100_000` and tick helpers are not required
   - explicit `compile_mode: :rustc` still preserves the real full native compile path for cases where we want to force it
   - after rebuilding `native:build[ir_compiler]`, a clean `HeadlessRunner(mode: :ir, sim: :compile, compile_mode: :auto)` constructor on refreshed `s1_top` is back down to about `6.5s` instead of blocking in native `Simulator#compile`
   - that restores the usable auto startup path for SPARC64 integration work, even though the first real `prime_sieve` execution batch is still too slow to complete a useful correctness run within this turn’s budget
8m. The runtime-only hot path also had avoidable per-cycle allocation overhead, and that cleanup is now in:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` no longer clones `comb_assigns`, `runtime_comb_assigns`, `seq_exprs`, or `reset_values` on the runtime-only evaluation/reset path just to iterate them
   - this is the exact path that `compile_mode: :auto` now uses for large SPARC64 plain cores, so the cleanup targets the real execution mode rather than the cold full-compile path
   - the native compiler was rebuilt after that change, and the existing focused runner/compiler checks remained green
   - I was not able to get a clean post-change `run100_s` timing sample out of the exec wrapper before ending this pass, so the optimization is in place but the exact before/after runtime-only speedup for SPARC64 is still unmeasured
8n. The SPARC64 compiler runtime-only path is now materially faster, but it is still not enough to finish a benchmark:
   - `lib/rhdl/sim/native/ir/ir_compiler/src/core.rs` now memoizes reused compact-expression `expr_ref` ids per top-level runtime evaluation root instead of recomputing the same DAG fragments repeatedly inside large mux trees
   - the compiler IR now rewrites parsed `Signal { name }` nodes into internal `SignalIndex { idx }` nodes once up front, so the runtime evaluator no longer hashes signal-name strings on every leaf access
   - narrow `<=128` signal / next-reg / memory reads now stay on a direct `u128` fast path instead of round-tripping through split-word reconstruction
   - `lib/rhdl/sim/native/ir/ir_compiler/src/runtime_value.rs` now fast-parses small decimal literal text directly before falling back to the generic digit-by-digit arbitrary-width path
   - focused coverage added/kept green:
     - `core::tests::runtime_only_expr_ref_cache_resets_between_evaluations`
     - `runtime_value::tests::parses_small_unsigned_text_via_fast_path`
     - `runtime_value::tests::parses_small_signed_text_via_fast_path`
     - `spec/rhdl/sim/native/ir/ir_wide_signal_spec.rb`
     - `spec/examples/sparc64/runners/ir_runner_spec.rb`
     - `spec/examples/sparc64/runners/headless_runner_spec.rb`
   - measured SPARC64 `prime_sieve` compile/auto runtime-only probe on the same cached `s1_top` import tree:
     - before this round of runtime-only work: about `35.93s` per `100` cycles
     - after the current optimizer set: about `10.26s` per `100` cycles
     - `1000` cycles now take about `119.26s`
   - the full-program blocker remains:
     - `1000` cycles still leave `mailbox_status=0`, `mailbox_value=0`, `trace_len=81`, and `unmapped=0`
     - that is a real speedup, but still too slow to treat runtime-only as the end-state backend for complex-program completion
   - the forced full-compile path is still the other half of the problem:
     - a fresh `compile_mode: :rustc` constructor probe still emitted a generated Rust unit of about `26 MiB`
     - the matching `rustc` process (`opt-level=0`, `codegen-units=256`) was still compiling after more than `9` minutes before being stopped
   - the next real step is no longer IFU parity debugging; it is shrinking or hybridizing the compiled surface enough that the forced native compile path becomes practical again
8o. SPARC64 Arcilator now has a real JIT runtime contract, but compile/JIT are not yet in parity on the first real benchmark packet transition:
   - `examples/sparc64/utilities/runners/arcilator_runner.rb` now starts an `lli` subprocess in JIT mode and drives it through a command loop instead of the old smoke-only one-shot wrapper
   - the JIT command loop now supports:
     - `RESET`
     - `CLEAR_MEMORY`
     - `LOAD_FLASH`
     - `LOAD_MEMORY`
     - `READ_MEMORY`
     - `WRITE_MEMORY`
     - `RUN`
     - `TRACE`
     - `FAULTS`
     - `SMOKE`
     - `QUIT`
   - that means `sim: :jit` now exposes the same SPARC64 runner contract shape as ARC compile for image loading, cycle stepping, mailbox reads, Wishbone trace capture, and unmapped-access reporting
   - focused runner coverage in `spec/examples/sparc64/runners/arcilator_runner_spec.rb` is green, including:
     - JIT runtime-contract image loading
     - JIT trace/fault parsing
     - real imported `s1_top` Arcilator JIT build/start
   - first real ARC compile vs ARC JIT `prime_sieve` compare on `s1_top`:
     - traces match through cycle `931`
     - first mismatch is at cycle `938`
     - ARC compile: `read addr=0x10000 sel=0xFF data=0x0100000001000000`
     - ARC JIT: `write addr=0x10000 sel=0x80 data=0x0`
   - that mismatch is stable:
     - same with `run_until_complete(... batch_cycles: 100)`
     - same with one-shot `run_cycles(1000)`
     - same across `lli --jit-kind=mcjit`, `orc`, and `orc-lazy`
     - same when forcing `lli` to one compile thread
   - the first ARC compile/JIT mismatch therefore appears to be a backend semantic difference, not a Ruby command-protocol bug
   - importantly, it lands in the same general window as the current ARC-vs-Verilator divergence:
     - ARC compile vs Verilator first mismatch also lands at cycle `938`
     - Verilator there performs the expected `write addr=0x10138 sel=0x80 data=0x0101010101010101`
   - current working hypothesis:
     - all three paths are exposing the same underlying packet-path problem around `os2wb` / LSU PCX transmit state
     - the new JIT support is useful immediately because it gives a second native execution signal on that exact transition window
8p. ARC compile and ARC JIT now agree on the benchmark trace, and the remaining parity bug is back to ARC vs Verilator:
   - `examples/sparc64/utilities/runners/arcilator_runner.rb` now runs both ARC modes through the same subprocess runtime protocol instead of mixing:
     - shared-library/Fiddle execution for `sim: :compile`
     - `lli` command-loop execution for `sim: :jit`
   - current split:
     - `sim: :compile` uses `lli --jit-kind=orc`
     - `sim: :jit` uses `lli --jit-kind=orc-lazy`
   - that unifies the runtime protocol and execution surface enough that the real `prime_sieve` `1000`-cycle compare is now green between ARC compile and ARC JIT:
     - `trace_len = 81` on both
     - no first mismatch
     - neither completes by `1000` cycles, but they now agree on the entire acknowledged Wishbone trace through that point
   - the first remaining ARC-vs-Verilator mismatch on the same `prime_sieve` run is now:
     - cycle `938`
     - ARC: `write addr=0x10000 sel=0x80 data=0x0`
     - Verilator: `write addr=0x10138 sel=0x80 data=0x0101010101010101`
   - targeted ARC debug snapshots around the enqueue window now show:
     - the first ARC internal split that mattered used to be compile vs JIT in `sparc_0/lsu/qdp1/pcx_xmit_ff/q`; that is gone after the subprocess unification
     - the remaining ARC-vs-Verilator bug is upstream of `os2wb` bus drive and visible in the slot-1 FIFO packet contents before cycle `938`
   - current most-specific localization:
     - by cycle `920`, the ARC `core0_pcx_xmit_ff_q` packet already encodes address `0x10000`
     - by cycle `921`, that packet is written into `pcx_fifo` slot `1`
     - by cycle `938`, ARC consumes that slot and emits the wrong write
     - Verilator’s matching packet path at the same conceptual point carries address `0x10138`
   - so the next real fix target is now cleanly narrowed to the LSU `qdp1` store-packet producer path, not the ARC runner plumbing and not `os2wb` FIFO dequeue semantics
8q. The first wrong value is now localized before `qdp1`, in the LSU store-buffer CAM write-data path:
   - added tighter debug surfaces in:
     - `examples/sparc64/utilities/runners/arcilator_runner.rb`
     - `examples/sparc64/utilities/runners/verilator_runner.rb`
   - direct cycle-aligned probes now show that ARC/IR and Verilator are reading the same store-buffer entry at the bad window:
     - cycle `920`
     - ARC compile: `stb_cam_r0_addr = 0`, `stb_data/local_dout` and `stb_cam/rt_tmp_8_45` already encode the bad `0x10000` packet source
     - Verilator: `stb_cam_hit_ptr = 0`, `stb_data_rd_ptr = 0`, but `qdp1` sees the correct `stb_rdata_ramc = 4115` and address nibble `8`, which yields `0x10138`
   - the same bad store-buffer contents are visible on the native IR path too:
     - a real `HeadlessRunner(mode: :ir, sim: :compile, compile_mode: :auto)` probe reaches cycle `920`
     - `sparc_0__lsu__stb_cam__rt_tmp_8_45 = 2097280`
     - `sparc_0__lsu__stb_data__local_dout = 4722366482869645213696`
     - `sparc_0__lsu__qdp1__pcx_xmit_ff_q` matches the ARC packet shape rather than Verilator
   - that rules out:
     - ARC compile vs ARC JIT runtime protocol
     - `os2wb` FIFO dequeue semantics
     - store-buffer read-pointer selection
   - the decisive write-side split is one cycle earlier:
     - ARC compile at cycle `917` writes CAM entry `0` with `alt_wsel = 0`, `hi30 = 0`, `lo15 = 128`, `wdata = 128`
     - Verilator at cycle `917` for the same store-buffer entry shows:
       - `stb_cam_stb_addr = 0`
       - `stb_cam_wdata_ramc = 2107264`
       - `stb_cam_wr_data = 64`
       - `lsu_tlb_pgnum_crit = 64`
   - the next concrete fix target is therefore upstream of `stb_cam` itself:
     - the normal `stb_cam_data` page-number path is already wrong on the imported/native side
     - focus moves to the LSU/DTLB `tlb_pgnum_crit` producer path feeding `stb_cam`
8r. The current first bad full-system state is now localized earlier than `stb_cam`, in the EXU-to-LSU VA path feeding `dctldp`:
   - kept the ARC path on syntax-only cleanup with only a final Ruby compatibility step before `arcilator`
   - added ARC-only probes for:
     - `sparc_0/lsu/dctldp/va_stgm/q`
     - `sparc_0/exu/bypass/rs1_data_dff/q`
     - `sparc_0/exu/bypass/rs2_data_dff/q`
     - `sparc_0/exu/ecl/c_used_dff/q`
     - `sparc_0/exu/alu/addsub/sub_dff/q`
   - focused cycle comparison now shows:
     - cycle `916`
       - staged Verilog: `core0_store.lsu_ldst_va_m_buf = 65848`
       - ARC compile: `sparc_0/lsu/dctldp/va_stgm/q = 0`
     - cycle `917`
       - staged Verilog: `core0_store.lsu_ldst_va_m_buf = 65600`
       - ARC compile: `sparc_0/lsu/dctldp/va_stgm/q = 65600`
   - that means the bad `0x10000` store packet later observed at cycle `938` is fallout from a stale value already captured into `va_stgm`
   - current ARC-side EXU probes at the same window are:
     - `rs1_data_dff = 65600`
     - `rs2_data_dff = 0`
     - `c_used_dff = 0`
     - `sub_dff = 0`
   - so the remaining unknown is narrowed to the EXU address-formation path between those bypass/control flops and the value that lands in `sparc_0/lsu/dctldp/va_stgm/q`
   - the relevant flattened ARC chain is:
     - `%4359 = arc.call @s1_top_arc_4355(...)`
     - `%4360 = arc.call @s1_top_arc_4356(...)`
     - `%3725 = arc.call @s1_top_arc_3721(%4359)`
     - `%sparc_02Flsu2Fdctldp2Fva_stgm2Fq = seq.firreg %3725 clock %11040`
   - a wrapper experiment to add extra low-phase `eval()` settle passes in the Arcilator runtime had no effect on `va_stgm` and was reverted
   - focused suites still green after keeping only the Arcilator-side probes:
     - `bundle exec rspec spec/examples/sparc64/runners/arcilator_runner_spec.rb --order defined`
     - `bundle exec rspec spec/examples/sparc64/runners/verilator_runner_spec.rb --order defined`
8s. The current first concrete data divergence is one stage earlier again, in `sparc_0/exu/bypass/rs1_data_dff/q`:
   - cycle-aligned runner probes now show:
     - `914`: Verilator `byp_alu_rs1_data_e = 65596`, ARC `rs1_data_dff = 65596`
     - `915`: Verilator `byp_alu_rs1_data_e = 65848`, ARC `rs1_data_dff = 0`
     - `916`: Verilator `byp_alu_rs1_data_e = 65600`, ARC `rs1_data_dff = 65600`
   - later-stage ARC source probes rule out the M/W/W2/dfill/ldxa bypass registers as the source of the missing `65848` value:
     - on the bad window, `dff_rd_data_e2m`, `dff_rd_data_m2w`, `dff_rd_data_g2w`, `dfill_data_dff`, and `stgg_eldxa` are all `0`
   - a focused Verilator rs1-path probe shows that the good baseline is alternating between:
     - RF-selected rs1 input
     - special `dbrinst` / PC-selected rs1 input
   - the currently relevant snapshot is:
     - `914`: D-stage rs1 path selects RF with `irf_byp_rs1_data_d = 0`
     - `915`: D-stage rs1 path selects the `dbrinst` / PC path with `ifu_exu_pc_d = 65600`
   - even with that additional visibility, the most useful invariant is:
     - ARC and Verilator agree on `thr_rd_w_neg = 3` on the bad window
     - ARC still produces `rs1_data_dff = 0` where Verilator reaches `65848`
   - so the remaining fault is now narrowed away from LSU capture and away from a trivial thread-select mismatch, and into the EXU rs1 D-stage input path or the IRF read value feeding it

## Goals

1. Add a new native `:sparc64` runner extension for imported `s1_top`.
2. Add SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner` support under `examples/sparc64/utilities/runners`.
3. Add a real SPARC64 integration benchmark loader that builds separate flash boot and DRAM program images.
4. Add a new integration suite under `spec/examples/sparc64/integration`.
5. Compare all five SPARC64 execution artifacts on exact acknowledged Wishbone transaction traces and final program outcomes.
6. Keep all development and verification sequential rather than parallel to avoid overwhelming the local machine.

## Non-Goals

1. Board-level `W1` parity.
2. Full DDR3, flash, UART, or ethernet peripheral emulation.
3. OS boot or firmware boot validation.
4. CLI/task surface expansion for SPARC64 in this phase.
5. Weak parity that ignores timing or transaction ordering.

## Public Interface / API Additions

1. New native runner kind:
   - `:sparc64`
2. New SPARC64 runner stack:
   - `examples/sparc64/utilities/runners/headless_runner.rb`
   - `examples/sparc64/utilities/runners/ir_runner.rb`
   - `examples/sparc64/utilities/runners/verilator_runner.rb`
3. New SPARC64 integration support:
   - benchmark/image builder utilities
   - shared mailbox/result contract
   - shared acknowledged Wishbone event trace type
4. New integration spec tree:
   - `spec/examples/sparc64/integration`

## Runtime Contract

1. Top under test is `s1_top`.
2. The native IR parity path is compiler-only.
3. The complex-program parity matrix is:
   - staged Verilog -> Verilator
   - staged Verilog -> `circt-verilog` -> Arcilator
   - imported RHDL -> native IR compiler
   - imported RHDL -> `to_mlir` -> Arcilator
   - imported RHDL -> `to_verilog` -> Verilator
4. The staged Verilog paths use the importer-emitted staged `s1_top` closure, not the raw reference tree directly.
5. The runner memory model exposes:
   - sparse byte-addressable DRAM
   - sparse read-only flash
   - exact byte-lane reads/writes using Wishbone `sel`
   - deterministic one-cycle registered ACK timing
   - unmapped-access detection as a hard failure
6. Benchmarks use:
   - flash boot image at the reset-fetch region
   - DRAM benchmark image at a fixed program base
   - mailbox success/failure reporting in DRAM
7. Core policy:
   - park core 1
   - run the benchmark on core 0 only
8. Standard mailbox ABI:
   - `MAILBOX_STATUS = 0x0000_1000`
   - `MAILBOX_VALUE = 0x0000_1008`
   - success writes `1` to status
   - failure writes `0xFFFF_FFFF_FFFF_FFFF` to status

## Phased Plan (Red/Green)

### Phase 1: Native `:sparc64` Runner Extension

#### Red

1. Add failing native runner-extension specs for imported `s1_top`.
2. Capture the baseline failure that `runner_kind` is not `:sparc64` and that runner memory APIs are unavailable.
3. Add failing support checks for:
   - flash load
   - DRAM load
   - DRAM read/write
   - unmapped access reporting
   - one-cycle acknowledged Wishbone service

#### Green

1. Add `:sparc64` runner-kind detection to the interpreter, JIT, and compiler native backends.
2. Implement a SPARC64 native extension that drives `s1_top` through the existing normalized runner ABI.
3. Back the runner with:
   - sparse flash bytes
   - sparse DRAM bytes
   - Wishbone byte-lane masking
   - deterministic one-cycle ACK behavior
4. Surface unmapped accesses and runner-state failures through the normalized runner result/probe path.

#### Exit Criteria

1. Imported `s1_top` reports `runner_kind == :sparc64`.
2. Flash and DRAM can be loaded and observed through the runner ABI.
3. A simple memory transaction on `s1_top` completes through the native runner path with deterministic ACK timing.

### Phase 2: SPARC64 Runner Stack And Program/Image Builder

#### Red

1. Add failing runner specs for new SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner`.
2. Add failing builder specs for separate flash boot and DRAM benchmark images.
3. Add failing checks for the shared mailbox ABI and benchmark registry.

#### Green

1. Add `HeadlessRunner` with a shared operational contract:
   - load benchmark
   - reset
   - run until completion or timeout
   - read/write memory
   - expose acknowledged Wishbone trace
   - expose mailbox status/value
2. Add `IrRunner` around imported `S1Top` on the compiler backend.
3. Add `VerilatorRunner` around the staged `s1_top` closure with the same operational contract.
4. Add a SPARC64 benchmark/image builder that:
   - assembles SPARC V9 source with `llvm-mc`
   - links boot and DRAM images separately with `ld.lld --image-base=0`
   - extracts binary payloads with `llvm-objcopy`
5. Add shared benchmark definitions for:
   - `prime_sieve`
   - `mandelbrot`
   - `game_of_life`

#### Exit Criteria

1. Both IR and Verilator SPARC64 runners expose the same benchmark-loading and execution contract.
2. The benchmark builder emits separate flash and DRAM images.
3. The benchmark registry is stable and loadable from specs.

### Phase 3: Boot Handoff And Memory-Resident Benchmark Execution

#### Red

1. Add a failing startup smoke spec that proves the flash boot shim transfers control into DRAM.
2. Add a failing multicore policy spec that requires core 1 to remain parked while core 0 runs the benchmark.
3. Add failing mailbox completion specs for one minimal smoke program.

#### Green

1. Implement a shared flash-resident SPARC64 boot shim.
2. Make the shim hand off to the DRAM-resident benchmark entrypoint.
3. Enforce the parked-secondary-core policy before benchmark execution proceeds.
4. Add one minimal benchmark smoke path that reaches mailbox success through real DRAM execution.

#### Exit Criteria

1. `s1_top` can boot from flash, jump into DRAM, and complete a minimal program.
2. Core 1 remains parked according to the suite policy.
3. Mailbox completion works end to end through both backends.

### Phase 4: Integration Parity And Correctness Benchmarks

#### Red

1. Add failing integration parity specs for:
   - `prime_sieve`
   - `mandelbrot`
   - `game_of_life`
2. Add failing correctness specs that require:
   - expected mailbox result
   - no unmapped accesses
   - minimum transaction count
   - exact acknowledged Wishbone event equality across the five-artifact matrix

#### Green

1. Implement a shared acknowledged Wishbone event trace:
   - `cycle`
   - `op`
   - `addr`
   - `sel`
   - `write_data`
   - `read_data`
2. Run each benchmark on all five execution artifacts with identical images and timeout/cycle budgets.
3. Treat staged Verilog -> Verilator as the canonical baseline and require exact ordered event-trace equality, including cycle numbers, for the other four artifact paths.
4. Require benchmark-specific mailbox values:
   - `prime_sieve => 0xA0`
   - `mandelbrot => 0xFFF0`
   - `game_of_life => 0x2`

#### Exit Criteria

1. All three benchmarks pass exact five-artifact parity.
2. All three benchmarks pass mailbox correctness checks.
3. No benchmark performs an unmapped access.

### Phase 5: Sequential Regression Closure

#### Red

1. Add failing regression/task-level checks that capture the intended SPARC64 integration scope in the normal suite.

#### Green

1. Run the focused sequential integration suite.
2. Run the broader sequential SPARC64 suite.
3. Update the PRD and checklists to reflect the actual shipped state.

#### Exit Criteria

1. `spec/examples/sparc64/integration` is green sequentially.
2. `bundle exec rake spec:sparc64` is green sequentially.
3. PRD status and checklist match reality.

## Acceptance Criteria

1. A new native `:sparc64` runner extension exists and is covered.
2. SPARC64 `HeadlessRunner`, `IrRunner`, and `VerilatorRunner` exist and share one runtime contract.
3. The benchmark builder emits separate flash boot and DRAM program images.
4. The new `spec/examples/sparc64/integration` suite runs `prime_sieve`, `mandelbrot`, and `game_of_life`.
5. Each benchmark is DRAM-resident and completes through the mailbox ABI.
6. The five execution artifacts match on exact acknowledged Wishbone transaction traces for all three programs.
7. Sequential SPARC64 regression gates are green.

## Risks And Mitigations

1. Risk: `s1_top` startup behavior is more complex than the current parked-core assumption.
   - Mitigation: lock startup behavior first with Phase 3 smoke specs before building all three benchmarks.
2. Risk: SPARC toolchain/image layout becomes brittle.
   - Mitigation: keep the builder minimal, deterministic, and covered with focused specs for separate boot/DRAM images.
3. Risk: Verilator and compiler diverge because of memory-service timing rather than core behavior.
   - Mitigation: share one explicit one-cycle ACK memory model and require exact event-trace parity.
4. Risk: Runtime execution is too slow for the full benchmark set.
   - Mitigation: keep benchmark workloads compact, cache builds where appropriate, and develop only with sequential focused commands.

## Testing Gates

1. `bundle exec rspec spec/examples/sparc64/integration --order defined`
2. `bundle exec rspec spec/examples/sparc64/import/unit/parity_helper_spec.rb --order defined`
3. `bundle exec rake spec:sparc64`

## Latest Findings

### 2026-03-12

1. The cycle-`938` ARC/Verilator divergence was traced to an importer-level staging bug, not ARC runtime semantics.
2. `SystemImporter` was force-stubbing `T1-common/srams/bw_r_rf32x152b.v`, which turned the LSU DFQ SRAM into a black-box `hw.module` with only `in` ports in `s1_top.core.mlir`.
3. That stub caused `qdp2.dfq_rdata` to be wired to `%c0_i152` in the imported MLIR, zeroing DFQ state on the ARC path.
4. `bw_r_rf32x152b.v` is now staged as a real source, with bundle-level regression coverage in the SPARC64 importer and staged-Verilog specs.
5. A clean re-import now produces:
   - `hw.module private @bw_r_rf32x152b(out dout : i152, out so : i1, ...)`
   - `%qdp2 ... dfq_rdata: %dfq.dout : i152`
6. On the fixed ARC path, the old late-window DFQ mismatch is gone:
   - cycle `960`: `dfq_vld=724`, `dfq_data_top=2168872`, `ifqop_cpxreq=17`
   - cycle `961`: `dfq_vld=724`, `dfq_inv=2049`, `dfq_data_top=2166826`, `ifqop_cpxreq=17`
   - cycle `973`: ARC now emits the read at `addr=65600` that previously only Verilator produced
7. The fixed ARC runner now progresses far beyond the old stop point and reaches at least `5000` cycles with:
   - `boot_handoff_seen=true`
   - `secondary_core_parked=true`
   - `unmapped_accesses=[]`
8. Remaining importer/staging risk: the forced-stub list still includes `bw_r_icd`, `bw_r_idct`, `bw_r_rf16x32`, `bw_r_rf16x160`, `bw_r_dcd`, and `bw_r_frf`, all of which currently appear in raw imported MLIR as black-box modules.

### 2026-03-12 Late Update

1. The next importer audit focused on the cache/tag SRAM stubs:
   - `bw_r_dcd`
   - `bw_r_icd`
   - `bw_r_idct`
   - `bw_r_rf16x32`
2. A temporary `s1_top`-only real-source override was tested but not kept enabled, because it exposed two more blockers before it was safe to ship broadly.
3. The raw `circt-verilog` experiment on that temporary `s1_top` branch showed real cache SRAM interfaces in `s1_top.core.mlir`, for example:
   - `@bw_r_dcd(out dcache_rdata_wb : i64, ...)`
   - `@bw_r_icd(out icd_wsel_fetdata_s1 : i136, ...)`
   - `@bw_r_idct(out rdtag_w0_y : i33, ...)`
   - `@bw_r_rf16x32(out dout : i4, ...)`
4. The raw instance sites also carried real result values instead of empty black-box calls, so the importer-side black-hole behavior is understood and reproducible on that branch.
5. Two follow-on blockers were exposed immediately:
   - `W1` shared cleanup/raise path still fails after `circt-verilog` succeeds, with:
     - `Import step: Cleanup imported CIRCT core MLIR`
     - `diagnostics: ["stack level too deep"]`
   - the broader `s1_top` raw-cache ARC path fails in `--convert-to-arcs` because the syntax-only cleanup path still leaves `llhd.constant_time` in the flattened HW/Seq MLIR
6. The current ARC-prep failure is:
   - `failed to legalize operation 'llhd.constant_time'`
   - on the raw-cache import branch under `.arcilator_build/s1_top_1364e206c59e/arc/s1_top.flattened.hwseq.mlir`
7. Practical status:
   - `bw_r_rf32x152b` importer fix is active and useful today
   - broader cache unstubbing is proven in raw import experiments
   - but it is not active in the importer today because ARC syntax cleanup and shared cleanup/raise are not ready for it yet

### 2026-03-12 Night Update

1. The next active importer fix is `bw_r_dcd`: it is no longer force-stubbed in `SystemImporter`.
2. Bundle-level regressions now require `bw_r_dcd.v` to be staged as a real source and absent from the SPARC64 hierarchy stub file.
3. A clean fast-boot `s1_top` import with real `bw_r_dcd` succeeds through:
   - `circt-verilog`
   - imported-core cleanup
   - parse/import
   - runtime JSON export
   - raise
4. The cleaned imported MLIR now carries the real D-cache interface:
   - `@bw_r_dcd(out dcache_rdata_wb : i64, out dcache_rparity_wb : i8, ...)`
   - `%dcache ... -> (so: i1, dcache_rdata_wb: i64, dcache_rparity_wb: i8, ...)`
5. This removes the old D-cache black-hole on the active ARC path.
6. Practical parity impact:
   - ARC compile now reaches the old `cycle 938` landmark with the expected write
     - `write addr=65848 sel=128 data=72340172838076673`
   - ARC compile and staged Verilog match exactly through `20000` cycles on `prime_sieve`
   - both complete `prime_sieve` together at `35000` cycles with identical trace length `5629`
   - mailbox result matches the expected value `0xA0`
7. The real spec gate is now green for one complex benchmark:
   - `bundle exec rspec spec/examples/sparc64/integration/runtime_parity_spec.rb -e 'matches exact acknowledged Wishbone traces for prime_sieve on ARC compile' --order defined --tag slow`
8. Remaining active parity work has moved to the next benchmarks and the next still-stubbed cache/tag modules:
   - `bw_r_icd`
   - `bw_r_idct`
   - `bw_r_rf16x32`
   - `bw_r_rf16x160`
   - `bw_r_frf`
9. Follow-up suite results on the same importer state are now green for the full ARC backend family:
   - `bundle exec rspec spec/examples/sparc64/integration/runtime_parity_spec.rb -e 'on ARC compile' --order defined --tag slow`
   - `bundle exec rspec spec/examples/sparc64/integration/runtime_parity_spec.rb -e 'on ARC jit' --order defined --tag slow`
10. That means all three complex programs currently pass exact Verilator parity on:
   - ARC compile
   - ARC JIT
11. The native IR compile path also improved on the same import tree:
   - direct `prime_sieve` compare now matches Verilator through the first `1000` cycles
   - but it remains much slower than ARC, so IR is now a separate performance/parity follow-up rather than the active ARC blocker
12. Shared cleanup review after the ARC green run:
    - the ARC-only fallback in `arc_prepare.rb` is still semantically risky because it rewrites a matched LLHD process into a plain `seq.compreg` without proving full hold/false-path/reset equivalence
    - the shared importer memory-recovery paths in `import.rb` are still semantic transforms, not syntax cleanup, especially:
      - `seq.firreg` array-to-memory recovery
      - packed-vector memory recovery
    - `ImportCleanup` still treats “no remaining `llhd.` text” as success, which is useful structurally but does not prove semantic equivalence
13. Native IR runtime-only follow-up on the fixed `bw_r_dcd` import tree:
    - baseline compiler `auto` timing on `prime_sieve`:
      - construct: `~6.7s`
      - load images: `~0.03s`
      - first `1000` cycles: `~161.6s`
    - `compiler_mode: :rustc` is now viable but still not competitive:
      - construct: `~141.0s`
      - first `100` cycles: `~18.2s`
    - JIT is not a practical alternative for this full-system path either.
14. Two runtime-only compiler-core optimizations are now in place in `ir_compiler/src/core.rs`:
    - reused tick scratch buffers and precomputed clock-domain slots
    - reused one compact-expr cache epoch per sweep instead of per top-level expression
    - cached parsed literal `RuntimeValue`s inside the compiler IR
15. Updated timing after those changes on the same fixed import tree:
    - construct: `~6.4s`
    - load images: `~0.03s`
    - first `1000` cycles: `~136.3s`
16. Practical conclusion:
    - the native IR path is still too slow for full benchmark parity closure
    - but the runtime-only hot path has improved by roughly `15%` on the real SPARC64 system model
    - the next IR step should be profiler-guided rather than another blind micro-optimization round
17. Shared importer follow-up on the fixed ARC tree:
    - `recover_packed_shadow_memory_aliases` in `import.rb` now recognizes opposite-phase packed shadow snapshots, not just literal self-hold shadows
    - `simplify_expr` now simplifies `IR::MemoryRead.addr`, which was the missing piece for the real `bw_r_scm` snapshot pattern
    - new regression coverage is green in `spec/rhdl/codegen/circt/import_spec.rb`:
      - `rewrites opposite-phase packed shadow snapshots back into firmem reads`
18. Real SPARC64 impact of that importer fix:
    - importing `tmp/sparc64_dcd_fix_import/.mixed_import/s1_top.core.mlir` no longer leaves `bw_r_scm` with a `rt_tmp_13_1440` register
    - direct raise of `bw_r_scm` from the same core MLIR no longer emits `rt_tmp_13_1440`
    - runtime JSON generated from the corrected imported modules now reports `w1440: 0`
19. Native IR timing after refreshing the runtime JSON on the same `tmp/sparc64_dcd_fix_import` tree:
    - construct remains practical at about `6.6s` to `6.9s`
    - first `100` cycles of `prime_sieve` remain roughly flat at about `13.5s`
    - so removing the old `1440`-bit shadow fixes a real importer artifact, but it is not the dominant runtime-only cost anymore
20. A direct `RuntimeValue::slice` optimization for wide values was tried and then reverted:
    - focused Rust coverage passed, but real SPARC64 `prime_sieve` timing regressed to about `15.0s` to `15.6s` per `100` cycles
    - the tree is back on the importer fix only; the slice fast path is not part of the current state
21. Current native IR conclusion:
    - the remaining runtime-only cost is dominated by the dense `129` to `145` bit expression population rather than the old `1440` shadow artifact
    - the next useful IR step should target the hot `RuntimeValue` operations with profiler-backed evidence, not more importer cleanup on `bw_r_scm`
22. Normalized-Verilog follow-up:
    - exporting `s1_top.normalized.v` from the fixed `s1_top.core.mlir` succeeds and `verilator --lint-only` accepts it
    - but the real SPARC64 `VerilogRunner` cannot use that path today because the wrapper depends on staged-RTL `public-flat` internals that do not exist in the normalized export
    - practical result: normalized Verilog is not currently a usable SPARC64 parity path
23. Native IR runtime experiment status:
    - a direct `RuntimeValue::concat` fast path for wide values was tried against the `129` to `145` bit hot path
    - focused Rust tests passed, but real `prime_sieve` timing regressed to about `14.9s` to `15.0s` per `100` cycles
    - that optimization was reverted; the current tree does not include it
24. ARC compile runner backend switch:
    - SPARC64 `ArcilatorRunner` compile mode now builds a native runtime executable instead of shelling out to `lli --jit-kind=orc`
    - object generation uses `llc`
    - JIT mode remains on the `lli` bitcode path
25. AArch64 native-codegen parity fix:
    - plain AOT native ARC codegen reintroduced the old cycle-`938` packet mismatch against Verilator on `prime_sieve`
    - both `llc` and direct `clang++` native builds showed the same failure, so the problem was not specific to `llc` alone
    - forcing AArch64 O0 GlobalISel off in the `llc` object compile step (`--aarch64-enable-global-isel-at-O=-1`) restored parity on the fixed import tree
    - direct fixed-tree validation is now green for ARC compile vs staged Verilator on:
      - `prime_sieve`
      - `mandelbrot`
      - `game_of_life`
    - the fresh-import slow ARC compile smoke still fails earlier during ARC prep on a separate combinational-loop issue, so the task is not fully closed at the default-import path yet

## Implementation Checklist

- [x] PRD created
- [x] Phase 1 red: native SPARC64 runner-extension specs added
- [x] Phase 1 green: native `:sparc64` runner extension implemented
- [x] Phase 1 exit criteria validated
- [x] Phase 2 red: SPARC64 runner and builder specs added
- [x] Phase 2 green: `HeadlessRunner`, `IrRunner`, `VerilatorRunner`, and benchmark builder implemented
- [x] Phase 2 exit criteria validated
- [x] Phase 3 red: boot handoff, parked-core, and mailbox smoke specs added
- [ ] Phase 3 green: boot shim and minimal DRAM benchmark flow implemented
- [ ] Phase 3 exit criteria validated
- [x] Phase 4 red: benchmark parity/correctness specs added
- [ ] Phase 4 green: `prime_sieve`, `mandelbrot`, and `game_of_life` five-artifact parity is green
- [ ] Phase 4 exit criteria validated
- [ ] Phase 5 red: regression/task-level checks added
- [ ] Phase 5 green: sequential SPARC64 regression closure complete
- [ ] Acceptance criteria validated
