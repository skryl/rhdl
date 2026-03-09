# Status

Completed - March 9, 2026

## Context

AO486 CPU-top top-level import specs were not practical on the compiler backend.

The March 9, 2026 investigation showed three concrete issues:

1. Compiler-targeted CIRCT runtime JSON expanded shared expression DAGs into very large trees, driving Ruby memory into multi-GB territory.
2. The compact `expr_ref` serializer was assigning unstable IDs, so compiler payloads could point a top-level expression at the wrong nested node.
3. Even after fixing payload correctness, the compiler backend was expanding every pooled `expr_ref` back into inline Rust, which recreated a giant generated source file and multi-minute `rustc` runs.

## Goals

1. Make the AO486 top-level import trio practical under `:compiler`.
2. Reduce compiler cold-start time and memory for the AO486 pure-core import path.
3. Preserve reset/tick semantics on the compiler backend for the targeted specs.

## Non-Goals

1. Switching the broader AO486 runtime parity suite to compiler-first.
2. Closing the separate AO486 runtime parity PRD.
3. Replacing JIT for longer parity-oriented AO486 runs.

## Phased Plan

### Phase 1: Bound The Hot Path

#### Red

1. Reproduce compiler-backed AO486 setup with stage timing and memory checkpoints.
2. Identify whether the blow-up came from import, flatten, runtime JSON, or `rustc`.

#### Green

1. Confirmed import/flatten were not the dominant problem.
2. Confirmed runtime JSON expansion and compiler source generation were the real cost centers.

#### Exit Criteria

1. We have concrete timings for AO486 compiler-backed setup.

### Phase 2: Fix Compiler Payload Correctness

#### Red

1. AO486 compiler-backed `cpu_importer_spec` failed initial reset/tick expectations.
2. Compact compiler payloads could mis-resolve `expr_ref` IDs.

#### Green

1. Added compact compiler runtime payload support in `runtime_json.rb`.
2. Fixed `expr_ref` slot reservation so nested serialization cannot shift IDs.
3. Added focused regressions for compact DAG serialization and compiler tick behavior.

#### Exit Criteria

1. Compiler-backed AO486 reset/tick behavior is correct on the targeted top-level specs.

### Phase 3: Shrink Compiler Cold Start

#### Red

1. AO486 compiler codegen still emitted enormous inline Rust for pooled expressions.
2. `rustc` cold compile time and memory were too high for practical top-level spec use.

#### Green

1. Compiler codegen now emits each pooled `expr_ref` once at first use instead of recursively inlining the full DAG every time.
2. Generic tick helpers are always generated for compiled cores, not only extension-backed ones.
3. Large combinational evaluation is chunked even on compact `expr_ref` payloads.
4. Rust compile flags now favor lower cold-start cost (`debuginfo=0`, `embed-bitcode=no`, fewer codegen units).
5. The AO486 top-level trio uses the compiler-preferred backend path while the broader runtime helper remains JIT-first.

#### Exit Criteria

1. AO486 top-level compiler-backed specs run without runaway `rustc` time or source-size failures.

## Acceptance Criteria

1. The AO486 top-level trio is green with compiler preferred:
   - `cpu_importer_spec.rb`
   - `cpu_parity_package_spec.rb`
   - `cpu_trace_package_spec.rb`
2. Compiler cold-start no longer hits pathological source-size or multi-minute compile behavior for that trio.
3. Focused compiler regression coverage is green.

## Risks And Mitigations

1. Compiler runtime semantics could drift from the proven paths.
   - Mitigation: add focused reset/tick and wide-expression regressions.
2. Broad AO486 runtime parity specs may still behave better on JIT.
   - Mitigation: keep `cpu_runtime_ir_backend` JIT-first and limit compiler preference to the top-level trio.
3. Compiler codegen changes could regress other compact-payload users.
   - Mitigation: keep shared runtime-json and compiler unit specs green.

## Validation

Green:

1. `cargo build --release` in `lib/rhdl/sim/native/ir/ir_compiler`
2. `bundle exec rspec spec/rhdl/codegen/circt/runtime_json_spec.rb`
3. `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_runtime_tick_spec.rb spec/rhdl/sim/native/ir/ir_compiler_wide_internal_expr_spec.rb spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb`
4. `AO486_IR_BACKEND=compiler bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb`
5. `AO486_IR_BACKEND=compiler bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb`
6. `AO486_IR_BACKEND=compiler bundle exec rspec spec/examples/ao486/import/cpu_trace_package_spec.rb`
7. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb spec/examples/ao486/import/cpu_parity_package_spec.rb spec/examples/ao486/import/cpu_trace_package_spec.rb`

Observed results:

1. Cold AO486 compiler setup reached `sim_init` in about `20.97s` total from importer start, with `sim_json` at about `14.06s`.
2. The combined top-level trio completed in `1 minute 35.28 seconds`, green.

## Implementation Checklist

- [x] Phase 1: Bound The Hot Path
- [x] Phase 2: Fix Compiler Payload Correctness
- [x] Phase 3: Shrink Compiler Cold Start
