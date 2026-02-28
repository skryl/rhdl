# TypeScript + Bun Bundler Migration for Web Simulator

## Status
Proposed (2026-02-28)

## Context

The RHDL web simulator (`web/app/`) is currently 154 vanilla JavaScript files
(~25K LOC) using ES modules (`.mjs`) with no build step. Dependencies are loaded
via CDN script tags (p5, Redux, ELK.js as globals) or CDN ESM URLs (Lit, lit-html).
Tests are 103 files (~13K LOC) using Node's built-in `node:test` runner.

This architecture served the project well during initial development but now creates
friction:

- **No type safety** – refactors across 11 component modules are error-prone.
- **CDN coupling** – production depends on jsdelivr availability; offline/desktop
  use is fragile.
- **No tree-shaking** – every module is fetched individually by the browser (154+
  HTTP requests on cold load).
- **No dead-code elimination** – unused exports are shipped.
- **Inconsistent dependency loading** – three patterns coexist (global scripts,
  CDN ESM URLs, relative imports).

### Why Bun

Bun's bundler is chosen over Vite/esbuild/webpack because:

1. Already a project dependency (Electrobun desktop app uses Bun).
2. Native TypeScript support (no separate tsc transpile step for dev).
3. Fast builds (~10x faster than esbuild for comparable projects).
4. Built-in test runner compatible with Node's `node:test` API.
5. Single toolchain for both desktop (Electrobun) and web builds.

## Goals

1. Convert all 154 `.mjs`/`.js` source files to TypeScript (`.ts`).
2. Convert all 103 `.test.mjs` test files to TypeScript (`.test.ts`).
3. Replace CDN dependency loading with `npm` imports bundled by Bun.
4. Produce a single-page app bundle (`dist/`) with hashed assets.
5. Preserve the existing development server workflow (`rake web:start`).
6. Preserve the Electrobun desktop build pipeline (point it at `dist/`).
7. Maintain all 103 existing tests passing throughout migration.

## Non-Goals

- Rewriting application logic or component architecture.
- Adding a UI framework migration (Lit stays as-is).
- SSR or code-splitting (the app is a single-page simulator).
- Strict TypeScript (`strict: true`) in phase 1 – start permissive, tighten later.

## Codebase Inventory

### Source Files (web/app/)

| Module | Files | LOC | Notes |
|--------|-------|-----|-------|
| core | 22 | 2,321 | State, runtime, bindings, controllers |
| explorer | 29 | 5,422 | Schematic viewer, WebGL, ELK layout |
| sim | 16 | 3,923 | WASM backends, simulation runtime |
| shell | 19 | 3,466 | App shell, themes, Lit element |
| terminal | 16 | 2,921 | Ghostty, mirb worker, commands |
| apple2 | 21 | 2,813 | Apple II I/O, audio, display |
| runner | 10 | 1,297 | Runner presets, lifecycle |
| watch | 8 | 798 | VCD trace, breakpoints |
| riscv | 2 | 763 | RISC-V disassembly |
| memory | 6 | 637 | Memory browser |
| editor | 1 | 547 | Vim-wasm editor |
| source | 3 | 178 | Source code viewer |
| **Total** | **154** | **~25K** | |

### Test Files (web/test/)

| Category | Files | LOC |
|----------|-------|-----|
| Unit (components + core) | 92 | ~11,500 |
| Integration | 11 | ~1,400 |
| **Total** | **103** | **~13K** |

### External Dependencies

| Package | Current Loading | Bundled Import |
|---------|----------------|----------------|
| redux@4.2.1 | `<script>` CDN → `window.Redux` | `import { createStore } from 'redux'` |
| p5@1.11.1 | `<script>` CDN → `window.p5` | `import p5 from 'p5'` |
| elkjs@0.9.3 | `<script>` CDN → `window.ELK` | `import ELK from 'elkjs/lib/elk.bundled'` |
| lit@3.2.1 | CDN ESM URL | `import { LitElement } from 'lit'` |
| lit-html@3.2.1 | CDN ESM URL | `import { html } from 'lit-html'` |
| ghostty-web@0.4.0 | dynamic `import()` from assets | Keep dynamic (WASM) |
| vim-wasm@0.0.13 | dynamic `import()` from assets | Keep dynamic (WASM) |

### Special Files

| File | Handling |
|------|----------|
| `terminal/workers/mirb_worker.js` | Separate worker entry point; bundle independently |
| `coi-serviceworker.js` | Copy to dist/ as-is (not bundled) |
| `assets/pkg/*.wasm` | Copy to dist/assets/ as-is |
| `index.html` | Template; rewrite `<script>` tags to point at bundle |

## Phased Plan

### Phase 0: Bun Build Infrastructure (foundation)

Set up the Bun bundler, tsconfig, and build scripts without touching any source
files. The existing `.mjs` source continues to work.

**Tasks:**
1. Create `web/tsconfig.json` with permissive settings.
2. Create `web/bunfig.toml` (if needed for Bun-specific config).
3. Add build entry point `web/build.ts` that invokes `Bun.build()`.
4. Add `web/app/entry.ts` – a thin wrapper that imports `./main.mjs` (bridge).
5. Update `web/package.json` with build/dev scripts.
6. Add `web/dist/` to `.gitignore`.
7. Update `rake web:build` to invoke `bun run build`.
8. Update `rake web:start` to serve from `dist/` (or fallback to source).
9. Verify: existing tests still pass, `dist/index.html` loads in browser.

**Exit criteria:**
- `bun run build` produces `dist/index.html` + `dist/app.js` bundle.
- Bundle loads in browser and app functions identically to unbundled.
- All 103 tests pass via `bun test` (running `.mjs` files).

### Phase 1: Core Module Conversion (low-risk, high-leverage)

Convert `web/app/core/` (22 files, 2.3K LOC) and its tests to TypeScript.
This module has no Lit components, no WASM, no DOM – pure logic.

**Tasks:**
1. Rename `core/**/*.mjs` → `core/**/*.ts`.
2. Add type annotations to exported functions and interfaces.
3. Create `types/` directory with shared type definitions:
   - `types/state.ts` – Redux state shape.
   - `types/runtime.ts` – runtime context, WASM instance types.
   - `types/sim.ts` – simulation types (backend, signals, etc.).
4. Replace `window.Redux` usage with `import { createStore } from 'redux'`.
5. Remove `fallback_redux.mjs` (Redux will be bundled).
6. Rename `test/core/**/*.test.mjs` → `test/core/**/*.test.ts`.
7. Verify: `bun test test/core/` passes.

**Exit criteria:**
- All core module files are `.ts`.
- All core tests pass.
- `bun run build` produces working bundle.

### Phase 2: Leaf Component Conversion (low coupling)

Convert components with few dependencies: `source` (3 files), `memory` (6),
`watch` (8), `riscv` (2), `editor` (1). Total: 20 files.

**Tasks:**
1. Rename each module's `.mjs` → `.ts`.
2. Add types. Use shared types from Phase 1.
3. Convert CDN Lit imports to bare `import { LitElement } from 'lit'`.
4. Convert corresponding test files.
5. Verify per-module: `bun test test/components/<module>/`.

**Exit criteria:**
- All 5 leaf modules are `.ts`.
- Their tests pass.
- Bundle works.

### Phase 3: Runner + Apple2 Conversion (medium coupling)

Convert `runner` (10 files) and `apple2` (21 files). These depend on core
and have moderate cross-module coupling.

**Tasks:**
1. Rename `.mjs` → `.ts`.
2. Type the runner preset system and Apple II I/O interfaces.
3. Replace `window.p5` global access with `import p5 from 'p5'`.
4. Convert tests.

**Exit criteria:**
- runner and apple2 modules are `.ts`.
- Tests pass. Apple II runner loads and simulates in browser.

### Phase 4: Terminal + Sim Conversion (WASM + Worker complexity)

Convert `terminal` (16 files) and `sim` (16 files). These contain WASM loading,
Web Workers, SharedArrayBuffer, and dynamic imports.

**Tasks:**
1. Rename `.mjs` → `.ts`.
2. Type WASM instantiation patterns (`WebAssembly.Instance` etc.).
3. Convert `mirb_worker.js` → `mirb_worker.ts` (separate Bun entry point).
4. Type the `ghostty-web` and `vim-wasm` dynamic import interfaces.
5. Replace `window.ELK` global access with `import ELK from 'elkjs/lib/elk.bundled'`.
6. Convert tests.

**Exit criteria:**
- terminal and sim modules are `.ts`.
- Worker builds as separate bundle.
- WASM loading works. mirb terminal works.
- Tests pass.

### Phase 5: Explorer + Shell Conversion (largest modules)

Convert `explorer` (29 files) and `shell` (19 files). Explorer has WebGL
shaders, canvas rendering, and ELK layout. Shell has Lit components and
theming.

**Tasks:**
1. Rename `.mjs` → `.ts`.
2. Type WebGL interfaces, canvas renderer, spatial index.
3. Type Lit component properties and element registration.
4. Convert tests.

**Exit criteria:**
- All source files are `.ts`. Zero `.mjs` files remain in `web/app/`.
- All 103 tests pass.
- Full app works in browser and desktop.

### Phase 6: Cleanup + Strictness

Tighten TypeScript config and clean up migration artifacts.

**Tasks:**
1. Enable `strict: true` in `tsconfig.json`.
2. Fix all strict-mode type errors.
3. Remove CDN script tags from `index.html` (all deps now bundled).
4. Remove `coi-serviceworker.js` CDN registration logic from HTML (keep
   the file for GitHub Pages deployment).
5. Update `web/desktop/` pipeline to consume `dist/` instead of raw source.
6. Update `web/desktop/scripts/prebuild.ts` to copy from `dist/`.
7. Update `web/desktop/electrobun.config.ts` copy paths.
8. Remove `fallback_redux.mjs` and related global-check patterns.
9. Add CI lint step: `bun run typecheck` (tsc --noEmit).

**Exit criteria:**
- `strict: true` compiles clean.
- No CDN script tags remain in production HTML.
- Desktop app builds from `dist/`.
- CI runs typecheck + test + build.

## TypeScript Configuration

```jsonc
// web/tsconfig.json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ESNext", "DOM", "DOM.Iterable", "WebWorker"],
    "jsx": "react-jsx",
    "strict": false,             // Phase 6 enables true
    "noEmit": true,              // Bun handles emit
    "skipLibCheck": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": false,
    "allowJs": true,             // Enables incremental migration
    "outDir": "dist",
    "rootDir": ".",
    "baseUrl": ".",
    "paths": {
      "@core/*": ["app/core/*"],
      "@components/*": ["app/components/*"],
      "@types/*": ["app/types/*"]
    }
  },
  "include": ["app/**/*.ts", "app/**/*.mjs", "test/**/*.ts", "test/**/*.mjs"],
  "exclude": ["node_modules", "dist", "assets"]
}
```

## Bun Build Configuration

```typescript
// web/build.ts
await Bun.build({
  entrypoints: [
    "./app/entry.ts",
    "./app/components/terminal/workers/mirb_worker.ts",
  ],
  outdir: "./dist",
  target: "browser",
  format: "esm",
  splitting: false,       // Single-page app; no code splitting needed
  sourcemap: "linked",
  minify: process.env.NODE_ENV === "production",
  naming: {
    entry: "[name].[hash].js",
    asset: "assets/[name].[hash][ext]",
  },
  external: [],           // Bundle everything
  define: {
    "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV ?? "development"),
  },
  loader: {
    ".wasm": "file",      // Copy WASM files, don't bundle them
  },
});
```

## File Rename Strategy

Each `.mjs` → `.ts` rename follows this mechanical process:

1. `git mv web/app/path/file.mjs web/app/path/file.ts`
2. Update all imports referencing this file:
   - Internal: `from './file.mjs'` → `from './file.ts'` (or extensionless
     with bundler resolution).
   - Tests: same pattern.
3. Add minimal type annotations to exports.
4. Run `bun test` for the affected module.

**Import extension strategy:** Bun's bundler resolves extensionless imports.
During migration, we can either:
- (A) Drop extensions entirely: `from './file'` – cleaner, standard TS.
- (B) Use `.ts` extensions: `from './file.ts'` – explicit, Bun-native.

**Recommendation:** Option (A) – drop extensions. This is idiomatic TypeScript
and Bun resolves them natively.

## Impact on Desktop Pipeline

The Electrobun desktop build currently copies raw source files from `web/`.
After migration:

| Before | After |
|--------|-------|
| Prebuild copies `web/app/` (154 .mjs files) | Prebuild copies `web/dist/` (bundled output) |
| Prebuild copies `web/index.html` | Prebuild copies `web/dist/index.html` |
| Browser loads 154+ individual modules | Browser loads 1-2 bundles |
| CDN required for p5/Redux/ELK | All deps bundled; works offline |

## Impact on Tests

| Before | After |
|--------|-------|
| `node --test` runner | `bun test` runner |
| `.test.mjs` files | `.test.ts` files |
| `import from 'node:test'` | `import { test, expect } from 'bun:test'` or keep `node:test` |
| No type checking in tests | Full type checking |

**Bun test compatibility:** Bun supports `node:test` and `node:assert` APIs.
Tests can be migrated incrementally – rename to `.ts`, add types, keep the
same test runner API initially.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Dynamic WASM imports break with bundler | Medium | High | Mark WASM loaders as external or use `new URL()` + `import.meta.url` pattern that Bun preserves |
| Web Worker bundling complexity | Medium | Medium | Build workers as separate entry points in `Bun.build()` |
| Lit CDN → npm import causes double-registration | Low | Medium | Ensure CDN script tags removed before npm Lit is loaded |
| p5 global → import breaks existing code | Medium | Medium | Use `import p5 from 'p5'` + assign to window for compatibility, then remove window reference |
| SharedArrayBuffer/COI regression | Low | High | Desktop always has COI; test GitHub Pages deployment in Phase 6 |
| 13K LOC of tests need .mjs → .ts rename | Low (mechanical) | Low | Script the rename; types optional in tests initially |
| Build time regression for development | Low | Medium | Bun builds are <1s for projects this size |

## Estimated Effort Per Phase

| Phase | Files Changed | Scope |
|-------|--------------|-------|
| 0: Build infra | ~8 new/modified | Config files, rake tasks, entry point |
| 1: Core | ~44 (22 src + 22 test) | Pure logic, no DOM/WASM |
| 2: Leaf components | ~40 (20 src + 20 test) | Small modules, some Lit |
| 3: Runner + Apple2 | ~62 (31 src + 31 test) | p5 global removal, I/O types |
| 4: Terminal + Sim | ~64 (32 src + 32 test) | WASM, workers, dynamic imports |
| 5: Explorer + Shell | ~96 (48 src + 48 test) | WebGL, Lit, themes |
| 6: Cleanup | ~10 modified | Config tightening, desktop update |

## Acceptance Criteria

1. Zero `.mjs` files remain in `web/app/`.
2. `bun run build` produces working `dist/` bundle.
3. All 103+ tests pass via `bun test`.
4. `bun run typecheck` (tsc --noEmit) passes with `strict: true`.
5. No CDN script tags in production HTML.
6. Desktop app builds from `dist/`.
7. App loads and runs identically in browser and desktop.
8. WASM backends (interpreter, JIT, compiler) all functional.
9. SharedArrayBuffer/mirb terminal works.
10. Build time < 5 seconds.

## Implementation Checklist

- [ ] **Phase 0: Build Infrastructure**
  - [ ] `web/tsconfig.json`
  - [ ] `web/build.ts` (Bun.build config)
  - [ ] `web/app/entry.ts` (bridge entry point)
  - [ ] Update `web/package.json` scripts
  - [ ] `web/dist/` in `.gitignore`
  - [ ] Update `rake web:build` and `rake web:start`
  - [ ] Verify bundle loads in browser
  - [ ] Verify tests still pass
- [ ] **Phase 1: Core Module** (22 files → .ts)
  - [ ] `app/core/state/*.ts`
  - [ ] `app/core/runtime/*.ts`
  - [ ] `app/core/controllers/*.ts`
  - [ ] `app/core/bindings/*.ts`
  - [ ] `app/core/lib/*.ts`
  - [ ] `app/core/services/*.ts`
  - [ ] `app/types/state.ts`, `runtime.ts`, `sim.ts`
  - [ ] `test/core/**/*.test.ts`
  - [ ] Remove `fallback_redux.mjs`
- [ ] **Phase 2: Leaf Components** (20 files → .ts)
  - [ ] `app/components/source/**/*.ts`
  - [ ] `app/components/memory/**/*.ts`
  - [ ] `app/components/watch/**/*.ts`
  - [ ] `app/components/riscv/**/*.ts`
  - [ ] `app/components/editor/**/*.ts`
  - [ ] Convert CDN Lit imports → `from 'lit'`
  - [ ] Corresponding test files
- [ ] **Phase 3: Runner + Apple2** (31 files → .ts)
  - [ ] `app/components/runner/**/*.ts`
  - [ ] `app/components/apple2/**/*.ts`
  - [ ] Replace `window.p5` → `import p5`
  - [ ] Corresponding test files
- [ ] **Phase 4: Terminal + Sim** (32 files → .ts)
  - [ ] `app/components/terminal/**/*.ts`
  - [ ] `app/components/sim/**/*.ts`
  - [ ] `mirb_worker.js` → `mirb_worker.ts` (separate bundle entry)
  - [ ] Type WASM instantiation interfaces
  - [ ] Replace `window.ELK` → `import ELK`
  - [ ] Corresponding test files
- [ ] **Phase 5: Explorer + Shell** (48 files → .ts)
  - [ ] `app/components/explorer/**/*.ts`
  - [ ] `app/components/shell/**/*.ts`
  - [ ] Type WebGL/canvas interfaces
  - [ ] Type Lit component properties
  - [ ] Corresponding test files
- [ ] **Phase 6: Cleanup + Strict Mode**
  - [ ] Enable `strict: true`
  - [ ] Fix all strict-mode errors
  - [ ] Remove CDN script tags from HTML
  - [ ] Update desktop pipeline to use `dist/`
  - [ ] Add CI typecheck step
  - [ ] Final browser + desktop integration test
