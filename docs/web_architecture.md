# Web App Architecture

This document describes the current architecture of the RHDL web simulator and where responsibilities live.

## Runtime Model

- `web/app/bootstrap.mjs` is the composition root.
- `web/app/main.mjs` loads UI components and starts bootstrap.
- Bootstrap creates:
  - DOM refs (`bindings/dom_bindings.mjs`)
  - mutable runtime context (`runtime/context.mjs`)
  - mutable UX state (`state/initial_state.mjs`)
  - Redux store + bridge (`state/store.mjs`, `state/store_bridge.mjs`)
  - controller registry (`controllers/registry_controller.mjs`)
  - startup orchestration (`controllers/startup_controller.mjs`)

## Layering

- `state/`: reducers, actions, store plumbing, redux sync helpers.
- `runtime/`: backend definitions, wasm simulator wrapper, VCD parser.
- `controllers/`: app behavior and orchestration. High-level intent lives here.
- `controllers/terminal/`: command routing and command handlers.
- `controllers/registry_lazy/`: lazy construction for heavy controller/managers.
- `managers/`: reusable behavior units (watch manager, dashboard layout manager).
- `bindings/`: DOM event wiring that maps UI events to controller-domain operations.
- `components/`: LitElement panels and rendering helpers.
- `lib/`: shared pure utilities (numeric parsing, IR metadata, dashboard/state helpers).

## Registry + Domains

`createControllerRegistry` returns grouped domains consumed by startup/bindings:

- `shell`
- `runner`
- `components`
- `apple2`
- `sim`
- `watch`

Each domain exposes cohesive capabilities instead of one flat API bag. Lazy getters in
`controllers/registry_lazy/*` defer heavy object construction until needed.

## Startup Contract

`startApp` receives explicit grouped dependencies:

- `env`: host environment hooks
- `store`: state dispatchers/sync helpers
- `util`: pure utility functions
- `keys`: storage keys/constants
- `bindings`: binding constructors + UI binding registry
- `app`: registry domains

This keeps startup deterministic and testable without browser globals.

## UI Composition

- `index.html` contains shell markup and panel containers.
- Lit components (`components/*.mjs`) own panel-specific rendering and styles.
- Bindings attach listeners and call domain methods.
- Redux sync snapshots app state for toolability and test instrumentation.

## Testing Strategy

- Unit tests:
  - controller units (`test/controllers`)
  - binding units (`test/bindings`)
  - manager/runtime/lib/state modules
- Browser integration tests (`test/integration`):
  - app load smoke
  - core user flows (runner load, memory dump actions, run/pause, terminal commands)

## Static Assets

- `assets/pkg`: wasm artifacts.
- `assets/fixtures`: generated IR/source/schematic fixtures and sample binary assets.
- `bundle exec rake web:build`: wasm build pipeline entrypoint.
- `bundle exec rake web:generate`: web asset generation entrypoint (builds wasm first when missing).
