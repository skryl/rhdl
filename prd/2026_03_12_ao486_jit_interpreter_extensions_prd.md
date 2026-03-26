Status: Completed (2026-03-12)

## Context

AO486 native runner support currently exists only in the `ir_compiler` backend.
The shared Ruby simulator wrapper already reserves AO486 runner kind/probe IDs and
the AO486 example code can prefer `:jit` as an IR backend, but the Rust
`ir_jit` and `ir_interpreter` crates do not expose an AO486 extension module or
the corresponding runner FFI wiring.

That leaves the backend surface inconsistent:

1. `ir_compiler` detects AO486 IR and exposes runner memory/disk/probe behavior.
2. `ir_jit` and `ir_interpreter` fall back to generic ticking with no AO486 runner kind.
3. AO486 backend helpers can select `:jit`, but AO486-specific runner features are absent there.

## Goals

1. Add AO486 runner extension support to `ir_jit`.
2. Add AO486 runner extension support to `ir_interpreter`.
3. Keep the AO486 runner ABI aligned across compiler, JIT, and interpreter for:
   detection, memory/ROM/disk access, cycle execution, and AO486 probe metadata.
4. Add targeted specs that fail before the change and pass after it.

## Non-Goals

1. Reworking the AO486 runner contract in Ruby.
2. Adding new AO486 behavior beyond the existing compiler extension surface.
3. Refactoring all backend extensions into a shared Rust crate.
4. Broad AO486 parity/performance tuning outside the touched backends.

## Phased Plan

### Phase 1: Red - targeted multi-backend AO486 specs

1. Add focused specs covering AO486 runner detection and key runner APIs on `:jit`
   and `:interpreter`.
2. Capture the baseline failure showing that the backends do not currently expose
   `runner_kind == :ao486` and AO486 runner probes/memory behavior.

Exit criteria:

1. New specs exist and fail for the current `ir_jit` / `ir_interpreter` implementation.

### Phase 2: Green - JIT backend support

1. Add `extensions/ao486/mod.rs` to `ir_jit`.
2. Wire AO486 detection into `ir_jit/src/extensions/mod.rs` and `ir_jit/src/ffi.rs`.
3. Expose AO486 runner kind, memory/ROM/disk handlers, runner execution, and probe operations.
4. Adjust AO486 runtime code for JIT core signal/value types.

Exit criteria:

1. JIT AO486 specs pass.
2. No regressions in touched JIT runner plumbing.

### Phase 3: Green - interpreter backend support

1. Add `extensions/ao486/mod.rs` to `ir_interpreter`.
2. Wire AO486 detection into `ir_interpreter/src/extensions/mod.rs` and `ir_interpreter/src/ffi.rs`.
3. Expose the same AO486 runner kind, memory/ROM/disk handlers, runner execution, and probe operations.
4. Adjust AO486 runtime code for interpreter core signal/value types.

Exit criteria:

1. Interpreter AO486 specs pass.
2. The interpreter AO486 runner ABI matches the JIT/compiler surface for covered behavior.

### Phase 4: Verification

1. Run targeted AO486 runner specs.
2. Run any narrow native-backend specs needed to confirm the touched FFI paths still load.

Exit criteria:

1. Targeted specs are green.
2. Any skipped or unavailable validation is documented explicitly.

Verification completed:

1. `cargo build --release` succeeded for `lib/rhdl/sim/native/ir/ir_interpreter`.
2. `cargo build --release` succeeded for `lib/rhdl/sim/native/ir/ir_jit`.
3. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_multi_backend_spec.rb` passed with `10 examples, 0 failures`.

## Acceptance Criteria

1. `ir_jit` detects AO486 IR as `runner_kind == :ao486`.
2. `ir_interpreter` detects AO486 IR as `runner_kind == :ao486`.
3. Both backends support AO486 runner memory/ROM/disk operations for the covered test harnesses.
4. Both backends surface AO486 runner probes used by the new specs.
5. PRD checklist and status reflect the final state.

## Risks And Mitigations

1. Risk: The compiler AO486 extension may rely on compiler-only core behavior.
   Mitigation: Keep the port narrow, remove the compiler-only `core.compiled` gate where required, and validate on backend-specific specs.
2. Risk: JIT uses `u64` signals while compiler/interpreter use wider signal types.
   Mitigation: adapt AO486 signal helpers explicitly in each backend port.
3. Risk: FFI constants or probe IDs can drift between backends.
   Mitigation: mirror the compiler AO486 IDs and add spec coverage through Ruby’s shared wrapper methods.

## Implementation Checklist

- [x] Phase 1: Add failing multi-backend AO486 runner specs.
- [x] Phase 2: Add AO486 extension module and FFI wiring in `ir_jit`.
- [x] Phase 3: Add AO486 extension module and FFI wiring in `ir_interpreter`.
- [x] Phase 4: Run targeted validation and record results.
