# Status

Completed - March 9, 2026

## Context

`RHDL::Sim::Native::IR.sim_json` can already emit compact CIRCT runtime JSON with pooled `expr_ref` nodes and a streaming writer path, but only the compiler backend currently consumes that format. The interpreter and JIT backends still normalize CIRCT payloads into the older inline-only expression shape, which blocks a repo-wide switch to the cheaper serializer path.

## Goals

1. Let interpreter, JIT, and compiler all consume compact CIRCT runtime JSON with `expr_ref` pooling.
2. Route backend-aware `sim_json` generation through the streaming writer path instead of building the full payload in Ruby memory first.
3. Preserve backend behavior and existing CIRCT runtime semantics.

## Non-Goals

1. Redesigning the CIRCT runtime JSON schema again.
2. Reworking Game Boy import/raise topology in this pass.
3. Broad benchmark work beyond the targeted runtime serialization/parsing path.

## Phased Plan

### Phase 1: Interpreter/JIT Compact Payload Support

#### Red

1. Confirm interpreter and JIT cannot currently consume payloads containing `expr_ref`/`exprs`.
2. Add targeted backend coverage that would fail without compact payload support.

#### Green

1. Teach interpreter and JIT CIRCT normalization to resolve pooled `expr_ref` nodes from module-level `exprs`.
2. Add native backend regression coverage for compact payload parsing and execution.

#### Exit Criteria

1. Interpreter and JIT can initialize and evaluate from compact CIRCT runtime JSON payloads.

### Phase 2: Streaming `sim_json` Rollout

#### Red

1. Confirm backend-aware `sim_json` still allocates the full payload for non-compiler backends.
2. Add targeted tests that assert backend-generated JSON remains valid after the switch.

#### Green

1. Route backend-aware `sim_json` generation through `RuntimeJSON.dump_to_io`.
2. Use compact pooled payloads for all IR backends now that all consumers support them.

#### Exit Criteria

1. `sim_json(..., backend: ...)` no longer builds the full runtime payload in Ruby memory for interpreter/JIT/compiler call sites.

### Phase 3: Validation

#### Red

1. Run targeted runtime JSON and backend simulator specs sequentially.
2. Recheck at least one consumer path per backend class.

#### Green

1. Keep targeted simulator/backend parity specs green.
2. Update the PRD checklist/status to match actual completion.

#### Exit Criteria

1. Targeted specs pass for interpreter, JIT, and compiler consumption of streamed compact CIRCT runtime JSON.

## Acceptance Criteria

1. Interpreter, JIT, and compiler all accept compact `expr_ref` CIRCT runtime payloads.
2. Backend-aware `sim_json` uses the streaming writer path.
3. Targeted specs covering payload generation and backend execution are green.

## Risks And Mitigations

1. `expr_ref` resolution could change backend evaluation semantics.
   - Mitigation: add backend-parity tests around generated payloads and runtime behavior.
2. JIT/interpreter dependency analysis could miss nested pooled expressions.
   - Mitigation: wire pooled-expression resolution into width and dependency helpers, not just runtime eval.
3. Changing all backends to compact payloads could surface latent parser bugs in runtime-only paths.
   - Mitigation: validate each backend sequentially with targeted simulator specs before widening further.

## Implementation Checklist

- [x] Phase 1: Interpreter/JIT Compact Payload Support
- [x] Phase 2: Streaming `sim_json` Rollout
- [x] Phase 3: Validation
