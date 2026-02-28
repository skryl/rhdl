# PRD: Eliminate `any` Types from Web Simulator

**Status**: Proposed
**Date**: 2026-02-28

---

## Context

The web simulator (`web/`) was migrated from `.mjs` to TypeScript with `strict: true`
enabled. To pass the type checker, 2,396 `any` annotations were added mechanically.
The codebase now compiles but has zero meaningful type safety — every boundary is `any`.

No type definition files, interfaces, or enums exist anywhere in the project.

### Current `any` Inventory

| Location | Count |
|----------|-------|
| `app/` (source) | 1,466 |
| `test/` (tests) | 930 |
| **Total** | **2,396** |

**By pattern:**

| Pattern | Count | % |
|---------|-------|---|
| Parameter `: any` | 1,886 | 79% |
| Variable `const/let: any` | 220 | 9% |
| `any[]` arrays | 191 | 8% |
| `as any` casts | 162 | 7% |
| `catch (err: any)` | 104 | 4% |
| `Record<string, any>` | 16 | 1% |
| `[key: string]: any` index sigs | 12 | <1% |

**By source component (app/):**

| Component | Count | Heaviest file |
|-----------|-------|---------------|
| explorer | 216 | model_utils.ts (26) |
| sim | 183 | wasm_ir_simulator.ts (71) |
| terminal | 148 | mirb_runner_service.ts (38) |
| core | 110 | controllers/registry.ts (31) |
| apple2 | 99 | snapshot.ts (15) |
| shell | 98 | dashboard_layout_manager.ts (42) |
| watch | 42 | vcd_panel.ts (18) |
| runner | 35 | io_config.ts (12) |
| riscv | 34 | riscv_disasm.ts (28) |
| editor | 26 | bindings.ts (26) |
| memory | 23 | panel.ts (7) |

**By test directory:**

| Directory | Count |
|-----------|-------|
| test/components/ | 488 |
| test/integration/ | 203 |
| test/core/ | 92 |

---

## Goals

1. Eliminate all `any` types from `app/` source code.
2. Eliminate all `any` types from `test/` that can be meaningfully typed.
3. Establish shared type infrastructure that makes future code self-documenting.
4. Maintain zero `tsc --noEmit` errors throughout.
5. No runtime behavior changes — types only.

## Non-Goals

- Refactoring runtime architecture (e.g., replacing factory functions with classes).
- Adding generics or advanced type-level programming beyond what's needed.
- Achieving 100% elimination in tests — some dynamic mocks are legitimately `any`.
- Changing the Redux-like store to a typed library (e.g., Zustand, Redux Toolkit).

---

## Phased Plan

### Phase 0: Foundation Types

**Goal**: Create the shared type files that all subsequent phases depend on.

**Files to create:**

1. **`app/types/state.ts`** — Full application state shape
   - `AppState` root interface
   - Per-slice interfaces: `ShellState`, `SimState`, `RunnerState`, `MemoryState`,
     `Apple2State`, `WatchState`, `TerminalState`, `ComponentsState`
   - `ReduxAction<T>` generic and action type string literals
   - `StoreDispatchers` interface (15+ setter functions)

2. **`app/types/runtime.ts`** — Runtime context and WASM bridge
   - `RuntimeContext` interface
   - `ThroughputMetrics` interface
   - `BackendDef` interface and `BackendId` union type
   - `WasmExports` interface (WASM instance export signatures)
   - Enums: `SimExecOp`, `SimSignalOp`, `SimTraceOp`, `RunnerMemOp`,
     `RunnerMemSpace`, `RunnerProbe`

3. **`app/types/services.ts`** — Service and controller contracts
   - Per-domain controller interfaces: `ShellDomainController`, `SimDomainController`,
     `Apple2DomainController`, `RunnerDomainController`, `WatchDomainController`,
     `ComponentsDomainController`
   - `ControllerRegistry` return type
   - `ControllerRegistryOptions` (the ~60-param config object)
   - `ListenerGroup` interface

4. **`app/types/dom.ts`** — DOM reference shapes
   - Per-component `DomRefs` interfaces
   - `MergedDomRefs` aggregate type

5. **`app/types/models.ts`** — Data model shapes
   - `ComponentNode`, `SignalNode` (explorer tree)
   - `Breakpoint`, `WatchEntry` (watch/debug)
   - `IoConfig`, `MemoryConfig`, `DisplayConfig` (runner)
   - `IrMetadata`, `SignalInfo` (IR parsing)
   - `WaveformPalette`, `Theme` (theming)
   - `RunnerPreset` (runner config)

6. **`app/types/index.ts`** — Barrel re-export

**Estimated lines**: 600–800 across all type files.

**Red/green**:
- Red: `grep -rc ': any' app/ --include='*.ts' | awk -F: '{s+=$2}END{print s}'` → 1,466.
- Green: Phase complete when all type files compile and count stays at 1,466
  (no source changes yet, just type definitions).

**Exit criteria**: All type files created, `tsc --noEmit` passes, barrel exports work.

---

### Phase 1: Core Layer

**Goal**: Type the core module — state, store, runtime, bootstrap.

**Scope** (~110 `any`):

| File | `any` count | Approach |
|------|-------------|----------|
| `core/state/store.ts` | 3 | Use `AppState`, `ReduxAction` |
| `core/state/reducer.ts` | 2 | Use `AppState`, `ReduxAction` |
| `core/state/actions.ts` | 1 | Type `mutator` callback |
| `core/state/store_bridge.ts` | 17 | Use `StoreDispatchers`, `AppState` |
| `core/state/fallback_redux.ts` | 1 | Use `AppState` |
| `core/runtime/context.ts` | 1 | Use `RuntimeContext` |
| `core/controllers/registry.ts` | 31 | Use `ControllerRegistryOptions`, return `ControllerRegistry` |
| `core/controllers/registry_lazy_getters.ts` | 2 | Type `requireFn` |
| `core/controllers/startup.ts` | 6 | Use `ControllerRegistryOptions` subset |
| `core/services/startup_initialization_service.ts` | 9 | Type config object |
| `core/services/startup_binding_registration_service.ts` | 3 | Type config object |
| `core/bindings/listener_group.ts` | 4 | Use `ListenerGroup` |
| `core/bindings/ui_registry.ts` | 3 | Type params |
| `core/bootstrap.ts` | 2 | Use `RuntimeContext` |
| `core/lib/*.ts` | 15 | Type utility function params/returns |

**Red/green**:
- Red: `grep -rc ': any' app/core/ --include='*.ts'` → 110.
- Green: count → 0.

**Exit criteria**: Zero `any` in `app/core/`, `tsc --noEmit` passes, tests pass.

---

### Phase 2: State Slices

**Goal**: Type all component state slices using the `AppState` sub-interfaces from Phase 0.

**Scope** (~30 `any` across 8 slice files):

| File | Key changes |
|------|-------------|
| `components/shell/state/slice.ts` | `ShellState`, typed action creators |
| `components/sim/state/slice.ts` | `SimState` |
| `components/runner/state/slice.ts` | `RunnerState` |
| `components/memory/state/slice.ts` | `MemoryState` |
| `components/apple2/state/slice.ts` | `Apple2State` |
| `components/watch/state/slice.ts` | `WatchState` |
| `components/terminal/state/slice.ts` | `TerminalState` |
| `components/explorer/state/slice.ts` | `ComponentsState` |

**Red/green**:
- Red: `grep -rc ': any' app/components/*/state/ --include='*.ts'` → ~30.
- Green: count → 0.

**Exit criteria**: Zero `any` in all `state/slice.ts` files.

---

### Phase 3: Sim + WASM Runtime

**Goal**: Type the simulator runtime — the densest single file and the WASM bridge.

**Scope** (~183 `any`):

| File | `any` count | Approach |
|------|-------------|----------|
| `sim/runtime/wasm_ir_simulator.ts` | 71 | Use `WasmExports`, enums, typed method signatures; remove index signature |
| `sim/runtime/live_vcd_parser.ts` | 8 | Explicit property types (Map, number, string) |
| `sim/runtime/backend_defs.ts` | ~5 | Use `BackendDef` interface |
| `sim/controllers/lazy_getters.ts` | ~40 | Type the large options object |
| `sim/controllers/domain.ts` | ~10 | Use `SimDomainController` |
| `sim/services/*.ts` | ~49 | Type service factory configs and returns |

**Red/green**:
- Red: `grep -rc ': any' app/components/sim/ --include='*.ts'` → 183.
- Green: count → 0.

**Exit criteria**: Zero `any` in `app/components/sim/`.

---

### Phase 4: Shell + Terminal + Editor

**Goal**: Type UI chrome components — shell layout, terminal services, editor bindings.

**Scope** (~272 `any`):

| Component | Count | Key files |
|-----------|-------|-----------|
| shell | 98 | dashboard_layout_manager.ts (42), domain.ts, lazy_getters.ts |
| terminal | 148 | mirb_runner_service.ts (38), workers (29), session_service.ts |
| editor | 26 | bindings.ts (26) |

**Approach**:
- `DashboardPanel`, `DashboardRootConfig` for layout manager DOM typing.
- `MirbWorkerState`, `MirbWorkerMessage` for worker communication.
- Type terminal history entries, line buffer, UART state.
- Type vim/mirb session state in editor bindings.

**Red/green**:
- Red: combined count → 272.
- Green: count → 0.

**Exit criteria**: Zero `any` in shell/, terminal/, editor/.

---

### Phase 5: Explorer + Watch + Memory

**Goal**: Type the component inspection and debugging tools.

**Scope** (~281 `any`):

| Component | Count | Key files |
|-----------|-------|-----------|
| explorer | 216 | model_utils.ts (26), graph controllers, renderers, schematic |
| watch | 42 | vcd_panel.ts (18), event_logger |
| memory | 23 | dump_assets.ts, panel.ts |

**Approach**:
- `ComponentNode`, `SignalNode`, `SchematicBundle` for explorer tree/graph.
- Canvas renderer param types (`CanvasRenderingContext2D`, coordinates as `number`).
- `Breakpoint`, `WatchEntry` for watch component.
- Memory dump row types.

**Red/green**:
- Red: combined count → 281.
- Green: count → 0.

**Exit criteria**: Zero `any` in explorer/, watch/, memory/.

---

### Phase 6: Apple2 + RISC-V + Runner

**Goal**: Type the system-specific components and runner configuration.

**Scope** (~168 `any`):

| Component | Count | Key files |
|-----------|-------|-----------|
| apple2 | 99 | snapshot.ts (15), services (60+), domain.ts |
| riscv | 34 | riscv_disasm.ts (28) |
| runner | 35 | io_config.ts (12), presets.ts |

**Approach**:
- `IoConfig` hierarchy for runner normalization functions.
- `RunnerPreset` type for preset definitions.
- Apple2 snapshot serialization types.
- RISC-V disassembly lookup tables as `Record<number, string>`.
- Apple2 audio/ROM/display service param types.

**Red/green**:
- Red: combined count → 168.
- Green: count → 0.

**Exit criteria**: Zero `any` in apple2/, riscv/, runner/. **Zero `any` in all of `app/`.**

---

### Phase 7: Test Types

**Goal**: Eliminate `any` from test files using the source types created in Phases 0–6.

**Scope** (~930 `any`):

| Category | Count | Approach |
|----------|-------|----------|
| Function params | 518 | Import source types; use `Parameters<>` utility |
| `any[]` arrays | 152 | `CallLog` tuple type, `Error[]`, typed arrays |
| `as any` casts | 102 | Replace with `as Partial<T>` or real interface subset |
| `catch (err: any)` | 104 | Change to `catch (err: unknown)` with narrowing |
| `Record<string, any>` | 6 | Use actual shape interfaces |

**Sub-phases by directory:**

| Sub-phase | Directory | Count | Approach |
|-----------|-----------|-------|----------|
| 7a | test/core/ | 92 | Import `AppState`, `ControllerRegistry`, `StoreDispatchers` |
| 7b | test/components/sim/ | 148 | Import `WasmIrSimulator` types, `SimState` |
| 7c | test/components/apple2/ | 104 | Import `Apple2State`, service types |
| 7d | test/components/explorer/ | 63 | Import `ComponentNode`, graph types |
| 7e | test/components/shell/ | 56 | Import `ShellState`, layout types |
| 7f | test/components/remaining/ | 125 | runner, watch, memory, terminal, source, riscv |
| 7g | test/integration/ | 203 | `catch (err: unknown)`, Playwright types, browser API types |

**Shared test helpers to create:**
- `test/helpers/types.ts` — `CallLog`, `MockService<T>`, `TestHarness<T>`

**Red/green**:
- Red: `grep -rc ': any' test/ --include='*.ts'` → 930.
- Green: count → target (see acceptance criteria).

**Exit criteria**: `any` count in `test/` ≤ 50 (residual dynamic mocks).

---

## Acceptance Criteria

| Criterion | Target |
|-----------|--------|
| `any` in `app/` | **0** |
| `any` in `test/` | **≤ 50** (documented residual) |
| `tsc --noEmit` | 0 errors |
| `bun test` | No new failures |
| `bun run build` | Succeeds |
| Residual `any` | Each justified with `// any: <reason>` comment |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Circular type dependencies between components | Medium | High | Use `app/types/` as single source of truth; components import from there, not from each other |
| Over-typing factory configs breaks flexibility | Medium | Medium | Start with wide types (unions), narrow incrementally; keep `Partial<T>` where configs are optional |
| WASM interface types drift from C code | Low | High | Generate `WasmExports` from C header or WASM introspection if possible; otherwise document manual sync |
| Large options objects resist typing | High | Low | Accept intermediate `Pick<ControllerRegistryOptions, 'dom' | 'state' | ...>` per call site |
| Test mocks become brittle with strict types | Medium | Medium | Use `Partial<T>` and `MockService<T>` helpers; keep test-only flexibility |
| Phase scope creep from discovering architectural issues | Medium | Medium | Log issues but don't fix architecture; types-only changes per non-goal |

---

## Implementation Checklist

- [ ] **Phase 0**: Foundation types (`app/types/`)
  - [ ] `state.ts` — AppState, slice interfaces, ReduxAction, StoreDispatchers
  - [ ] `runtime.ts` — RuntimeContext, WasmExports, enums
  - [ ] `services.ts` — Domain controller interfaces, ControllerRegistry
  - [ ] `dom.ts` — DomRefs interfaces
  - [ ] `models.ts` — Data model types
  - [ ] `index.ts` — Barrel export
- [ ] **Phase 1**: Core layer (110 → 0 `any`)
- [ ] **Phase 2**: State slices (30 → 0 `any`)
- [ ] **Phase 3**: Sim + WASM runtime (183 → 0 `any`)
- [ ] **Phase 4**: Shell + Terminal + Editor (272 → 0 `any`)
- [ ] **Phase 5**: Explorer + Watch + Memory (281 → 0 `any`)
- [ ] **Phase 6**: Apple2 + RISC-V + Runner (168 → 0 `any`)
- [ ] **Phase 7**: Test types (930 → ≤50 `any`)
  - [ ] 7a: test/core/
  - [ ] 7b: test/components/sim/
  - [ ] 7c: test/components/apple2/
  - [ ] 7d: test/components/explorer/
  - [ ] 7e: test/components/shell/
  - [ ] 7f: test/components/remaining/
  - [ ] 7g: test/integration/
