# Apple II Web Verilator Backend PRD

Status: Completed (2026-03-01)

## Context

The Apple II web benchmark currently compares compiler and arcilator WASM backends. We need a comparable Verilator-based WASM backend and benchmark coverage so users can measure compiler/arcilator/verilator performance under the same headless web execution harness.

## Goals

1. Add a build pipeline that produces `web/assets/pkg/apple2_verilator.wasm`.
2. Add Verilator backend participation to `bench:web:apple2`.
3. Keep benchmark flow resilient when Verilator/WASM toolchain pieces are unavailable.
4. Update tests and docs for the new backend path.

## Non-Goals

1. Full UI integration of a selectable `verilator` backend in the browser app.
2. RISC-V Verilator web backend in this change.
3. Replacing existing native Verilator runner flows.

## Phased Plan

### Phase 1: Verilator WASM Build Task

Red:
- Add failing checks/spec coverage for new build module contract.

Green:
- Implement `WebApple2VerilatorBuild` task module:
  - Apple II Verilog export
  - Verilator C++ generation
  - Emscripten compilation/link to WASM
  - Install artifact to `web/assets/pkg`

Refactor:
- Keep helper organization in module methods for command execution and source generation.

Exit Criteria:
- Module can be loaded, tool checks work, wrapper generation tests pass.

### Phase 2: Benchmark Integration

Red:
- Add/adjust benchmark dispatch expectations where needed.

Green:
- Extend Apple II web benchmark backend discovery to include Verilator artifact/build.
- Ensure benchmark summary handles multi-backend ratio output cleanly.

Refactor:
- Keep backend preparation code paths consistent across compiler/arcilator/verilator.

Exit Criteria:
- `bench:web:apple2` can run compiler/arcilator/verilator when available.

### Phase 3: Build Pipeline + Docs + Validation

Red:
- Add/adjust web build task spec expectations for new backend build step.

Green:
- Wire `WebGenerateTask` to attempt Verilator WASM build.
- Update README/performance docs.
- Run targeted specs and runtime benchmark command.

Refactor:
- Keep warning/fallback behavior consistent with existing optional backends.

Exit Criteria:
- Specs pass and benchmark command reports all available backends, including Verilator.

## Acceptance Criteria

1. `lib/rhdl/cli/tasks/utilities/web_apple2_verilator_build.rb` exists and can build/install `apple2_verilator.wasm` when toolchain is present.
2. `bundle exec rake bench:web:apple2` includes Verilator in backend set when available.
3. Existing backends remain functional.
4. Relevant CLI/task specs pass.
5. Documentation reflects Apple II web benchmark now including Verilator.

## Risks and Mitigations

1. Emscripten/Verilator portability issues:
- Mitigation: explicit tool checks and non-fatal skip behavior with clear warnings.

2. WASI import requirements from em++ output:
- Mitigation: benchmark harness provides WASI stub imports for instantiation.

3. Build time increase:
- Mitigation: compile only when artifact missing and keep as optional backend in web build flow.

## Implementation Checklist

- [x] Phase 1: Add `WebApple2VerilatorBuild` module and tests.
- [x] Phase 2: Integrate Verilator backend into `bench:web:apple2`.
- [x] Phase 2: Update summary ratio handling for multi-backend output.
- [x] Phase 3: Hook Verilator WASM build into `web:build`.
- [x] Phase 3: Update docs.
- [x] Phase 3: Run targeted specs and benchmark command(s).
