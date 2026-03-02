# PRD: Eliminate `any` Types from Web Simulator

**Status**: In Progress
**Date**: 2026-02-28
**Last Updated**: 2026-03-01

---

## Context

The web simulator (`web/`) was migrated from `.mjs` to TypeScript with `strict: true`
enabled. To pass the type checker, 2,396 `any` annotations were added mechanically.
The codebase compiles, but type safety is still largely absent at critical boundaries.

No type definition files, interfaces, or enums currently exist in `web/app/`.

## Canonical Measurement Method

All phase gates and acceptance checks use **occurrence count of `\bany\b`** in `.ts` files,
not line-count of `: any`.

Canonical commands (run from `web/`):

- App count: `rg -o --glob '*.ts' '\\bany\\b' app | wc -l`
- Test count: `rg -o --glob '*.ts' '\\bany\\b' test | wc -l`
- Total count: `rg -o --glob '*.ts' '\\bany\\b' app test | wc -l`

This avoids false progress from patterns that miss `as any`, `any[]`, `Record<string, any>`,
and index signatures.

## Current `any` Inventory (2026-03-01)

| Location | Count |
|----------|-------|
| `app/` (source) | 1,466 |
| `test/` (tests) | 930 |
| **Total** | **2,396** |

**By source component (`app/`):**

| Component | Count |
|-----------|-------|
| explorer | 370 |
| sim | 249 |
| terminal | 205 |
| shell | 144 |
| apple2 | 139 |
| core | 127 |
| watch | 58 |
| runner | 48 |
| riscv | 48 |
| memory | 36 |
| editor | 34 |
| source | 8 |

**By test directory:**

| Directory | Count |
|-----------|-------|
| `test/components/` | 612 |
| `test/integration/` | 222 |
| `test/core/` | 96 |

---

## Goals

1. Eliminate all `any` types from `app/` source code.
2. Eliminate all `any` types from `test/` that can be meaningfully typed.
3. Establish shared type infrastructure that makes future code self-documenting.
4. Maintain zero `tsc --noEmit` errors throughout.
5. No runtime behavior changes — types only.

## Non-Goals

- Refactoring runtime architecture (e.g., replacing factory functions with classes).
- Adding advanced type-level programming beyond what is required for safety/readability.
- Achieving 100% elimination in tests — some dynamic mocks are legitimately `any`.
- Replacing the current state/store approach with a different library.

---

## Phased Plan

### Phase 0: Foundation Types

**Goal**: Create shared type files that all subsequent phases depend on.

**Files to create:**

1. **`app/types/state.ts`**
   - `AppState` root interface
   - Per-slice interfaces: `ShellState`, `SimState`, `RunnerState`, `MemoryState`,
     `Apple2State`, `WatchState`, `TerminalState`, `ComponentsState`
   - `ReduxAction<T>` generic and action type literals
   - `StoreDispatchers` interface

2. **`app/types/runtime.ts`**
   - `RuntimeContext` interface
   - `ThroughputMetrics` interface
   - `BackendDef` interface and `BackendId` union
   - `WasmExports` interface (WASM instance exports)
   - Enums: `SimExecOp`, `SimSignalOp`, `SimTraceOp`, `RunnerMemOp`,
     `RunnerMemSpace`, `RunnerProbe`

3. **`app/types/services.ts`**
   - Domain controller interfaces
   - `ControllerRegistry` return type
   - `ControllerRegistryOptions`
   - `ListenerGroup` interface

4. **`app/types/dom.ts`**
   - Per-component DOM reference interfaces
   - `MergedDomRefs` aggregate type

5. **`app/types/models.ts`**
   - Explorer, watch/debug, runner, IR, theme, and preset model shapes

6. **`app/types/index.ts`**
   - Barrel re-export

**Red/green:**
- Red: baseline capture
  - `rg -o --glob '*.ts' '\\bany\\b' app | wc -l` → 1,466
  - `rg -o --glob '*.ts' '\\bany\\b' test | wc -l` → 930
- Green: type files compile and baseline counts remain unchanged (types added, no removals yet).

**Exit criteria**: All type files created, `bun run typecheck` passes, barrel exports work.

---

### Phase 1: Core Layer

**Goal**: Type the core module — state, store, runtime, bootstrap.

**Scope**: `app/core/` (**127 `any`**) 

**Red/green:**
- Red: `rg -o --glob '*.ts' '\\bany\\b' app/core | wc -l` → 127
- Green: count → 0

**Exit criteria**: Zero `any` in `app/core/`, `bun run typecheck` passes, targeted tests pass.

---

### Phase 2: State Slices

**Goal**: Type all component state slices using the Phase 0 state interfaces.

**Scope**: `app/components/*/state/slice.ts` (**34 `any`**) across:

- `shell`, `sim`, `runner`, `memory`, `apple2`, `watch`, `terminal`, `explorer`

**Red/green:**
- Red: `rg -o --glob '*.ts' '\\bany\\b' app/components/*/state/slice.ts | wc -l` → 34
- Green: count → 0

**Exit criteria**: Zero `any` in all `state/slice.ts` files.

---

### Phase 3: Sim + WASM Runtime (Non-slice)

**Goal**: Type the simulator runtime, bridge, and sim domain services.

**Scope**: `app/components/sim/` excluding state slice (**243 `any`**)

**Red/green:**
- Red: `rg -o --glob '*.ts' --glob '!app/components/sim/state/slice.ts' '\\bany\\b' app/components/sim | wc -l` → 243
- Green: count → 0

**Exit criteria**: Zero `any` in non-slice sim files.

---

### Phase 4: Shell + Terminal + Editor (Non-slice)

**Goal**: Type UI chrome components and terminal/editor plumbing.

**Scope**: shell + terminal + editor excluding shell/terminal state slices (**376 `any`**)

**Red/green:**
- Red: `rg -o --glob '*.ts' --glob '!app/components/shell/state/slice.ts' --glob '!app/components/terminal/state/slice.ts' '\\bany\\b' app/components/shell app/components/terminal app/components/editor | wc -l` → 376
- Green: count → 0

**Exit criteria**: Zero `any` in non-slice shell/terminal/editor files.

---

### Phase 5: Explorer + Watch + Memory (Non-slice)

**Goal**: Type component inspection and debugging surfaces.

**Scope**: explorer + watch + memory excluding state slices (**451 `any`**)

**Red/green:**
- Red: `rg -o --glob '*.ts' --glob '!app/components/explorer/state/slice.ts' --glob '!app/components/watch/state/slice.ts' --glob '!app/components/memory/state/slice.ts' '\\bany\\b' app/components/explorer app/components/watch app/components/memory | wc -l` → 451
- Green: count → 0

**Exit criteria**: Zero `any` in non-slice explorer/watch/memory files.

---

### Phase 6: Apple2 + RISC-V + Runner + Source (Non-slice)

**Goal**: Type system-specific components and runner/source configuration.

**Scope**: apple2 + riscv + runner + source excluding apple2/runner state slices (**235 `any`**)

**Red/green:**
- Red: `rg -o --glob '*.ts' --glob '!app/components/apple2/state/slice.ts' --glob '!app/components/runner/state/slice.ts' '\\bany\\b' app/components/apple2 app/components/riscv app/components/runner app/components/source | wc -l` → 235
- Green: count → 0

**Exit criteria**: Zero `any` in this scope and **zero `any` in all of `app/`**.

---

### Phase 7: Test Types

**Goal**: Eliminate `any` from tests using source types created in Phases 0–6.

**Scope**: `test/` (**930 `any`**) 

**Sub-phases by directory:**

| Sub-phase | Directory | Count |
|-----------|-----------|-------|
| 7a | `test/core/` | 96 |
| 7b | `test/components/sim/` | 171 |
| 7c | `test/components/apple2/` | 144 |
| 7d | `test/components/explorer/` | 79 |
| 7e | `test/components/shell/` | 63 |
| 7f | `test/components/{runner,watch,memory,terminal,source,riscv}/` | 155 |
| 7g | `test/integration/` | 222 |

**Shared test helpers to create:**
- `test/helpers/types.ts` — `CallLog`, `MockService<T>`, `TestHarness<T>`

**Red/green:**
- Red: `rg -o --glob '*.ts' '\\bany\\b' test | wc -l` → 930
- Green: count → target (see acceptance criteria)

**Exit criteria**: `any` count in `test/` ≤ 50 (residual dynamic mocks only).

---

## Acceptance Criteria

| Criterion | Target |
|-----------|--------|
| `any` in `app/` | **0** |
| `any` in `test/` | **≤ 50** (documented residual) |
| Typecheck | `bun run typecheck` passes |
| Tests | `bun run test:all` passes |
| Build | `bun run build` succeeds |
| Residual `any` | Each justified with `// any: <reason>` comment |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Circular type dependencies between components | Medium | High | Use `app/types/` as single source of truth; import through barrel where possible |
| Over-typing factory configs breaks flexibility | Medium | Medium | Start with broad interfaces, then narrow incrementally |
| WASM interface types drift from native exports | Low | High | Keep `WasmExports` documented with validation tests against runtime usage |
| Large options objects resist typing | High | Low | Use focused option interfaces (`Pick<>`/subset types) per boundary |
| Test mocks become brittle with strict types | Medium | Medium | Use `Partial<T>` and test-only helper types |
| Scope creep into architecture refactors | Medium | Medium | Log architecture issues; keep this PRD type-only |

---

## Execution Snapshot (2026-03-01)

- `any` occurrence counts are now **0** in both `web/app` and `web/test`:
  - `cd web && rg -o --glob '*.ts' '\bany\b' app | wc -l` → `0`
  - `cd web && rg -o --glob '*.ts' '\bany\b' test | wc -l` → `0`
- Typecheck status:
  - `cd web && npx tsc --noEmit` now passes.
- Remaining blockers:
  - `// @ts-nocheck` directives remain in shell/terminal/editor scope (`28` total) and should be removed in a follow-up hardening pass.
  - Bun gates were run after installing Bun (`1.3.10`):
    - `cd web && bun run typecheck` → **pass**
    - `cd web && bun run build` → **pass**
    - `cd web && bun run test:all` → **fail** (`409 pass, 25 fail, 1 error`; dominant failures are Bun `skip()` not implemented, integration timeouts, and several runtime assertion/type errors).

This PRD remains **In Progress** until typecheck/test/build acceptance gates pass.

---

## Implementation Checklist

- [x] **Phase 0**: Foundation types (`app/types/`)
  - [x] `state.ts` — AppState, slice interfaces, ReduxAction, StoreDispatchers
  - [x] `runtime.ts` — RuntimeContext, WasmExports, enums
  - [x] `services.ts` — Domain controller interfaces, ControllerRegistry
  - [x] `dom.ts` — DomRefs interfaces
  - [x] `models.ts` — Data model types
  - [x] `index.ts` — Barrel export
- [x] **Phase 1**: Core layer (127 → 0 `any`)
- [x] **Phase 2**: State slices (34 → 0 `any`)
- [x] **Phase 3**: Sim + WASM runtime non-slice (243 → 0 `any`)
- [x] **Phase 4**: Shell + Terminal + Editor non-slice (376 → 0 `any`)
- [x] **Phase 5**: Explorer + Watch + Memory non-slice (451 → 0 `any`)
- [x] **Phase 6**: Apple2 + RISC-V + Runner + Source non-slice (235 → 0 `any`)
- [x] **Phase 7**: Test types (930 → ≤50 `any`)
  - [x] 7a: `test/core/`
  - [x] 7b: `test/components/sim/`
  - [x] 7c: `test/components/apple2/`
  - [x] 7d: `test/components/explorer/`
  - [x] 7e: `test/components/shell/`
  - [x] 7f: `test/components/{runner,watch,memory,terminal,source,riscv}/`
  - [x] 7g: `test/integration/`
- [ ] Validation hardening: remove `@ts-nocheck` / `@ts-ignore` directives and re-run typecheck.
- [ ] Runtime gates: run `bun run test:all` and `bun run build` in a Bun-enabled environment.
