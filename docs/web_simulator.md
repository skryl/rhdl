# RHDL IR Web Simulator (p5.js + WASM)

This app runs RHDL IR simulator backends in the browser via WebAssembly and renders live VCD waveforms with p5.js.

Architecture details are included at the bottom of this page.

## Features

- Load RHDL-generated IR JSON
- Select backend (`interpreter`, `jit`, `compiler`)
- Preconfigured runner presets (Generic, CPU, MOS 6502, Apple II, Game Boy)
- One-click Apple II runner setup (IR + ROM load)
- Step, run, pause, reset simulation
- Clocked stepping (forced clock edge) or unclocked ticking
- Tunable run pacing: `Cycles/Frame` and `UI Every` (cycles) to batch simulation and reduce UI/VCD overhead
- Live VCD streaming from Rust tracer to the browser
- Watch list + current value table
- Value breakpoints (`signal == value`)
- Export full VCD file for GTKWave
- Redux-backed UX state store for tooling/automation
- LitElement UI components with co-located styles
- Panel components split into modules under `web/app/components/` and bundled by Bun
- Built-in terminal command dispatcher for runner/backend switching, stepping, watches, breakpoints, and memory helpers
- Tabbed workspace:
  - `1. I/O`: Apple II display + `HIRES`, `COLOR`, `SOUND` toggles, keyboard input queue, debug registers
  - `2. VCD + Signals`: waveform canvas, watch table, event log
  - `3. Memory`: RAM browser + direct byte writes + memory dump loading
  - `4. Components`: source-backed component details (`RHDL` + `Verilog`) when source bundles are present
- Memory dump utilities:
  - `Save Dump` exports current Apple II RAM to `.bin` and stores it as "last saved"
  - `Download Snapshot` exports current Apple II RAM as a portable `.rhdlsnap` file (includes `startPc` when available)
  - `Load Dump` accepts both raw binary dumps and `.rhdlsnap` snapshot files
  - `Load Last Saved` restores the most recently saved dump from browser storage
  - `Reset (Vector)` resets the Apple II runner from the Memory tab, with optional manual reset-vector override (`$B82A` / `0xB82A`)

## Build pipeline

The web simulator uses a two-stage build:

1. Ruby-side artifact generation (WASM + IR/fixture metadata)
2. Bun bundle (JS + runtime assets) into `web/dist/`

```bash
bundle exec rake web:build
```

Generates core web runtime artifacts under `web/assets/pkg/*.wasm`.

If artifacts are missing, run:

```bash
bundle exec rake web:generate
```

`ir_compiler` is built as AOT for web:
- `web:build` runs `ir_compiler`'s `aot_codegen` over `assets/fixtures/apple2/ir/apple2.json` by default.
- Then it builds `ir_compiler.wasm` with `--features aot`.

Bundle simulator output into `web/dist` with Bun:

```bash
cd web
bun run build
```

or via rake:

```bash
bundle exec rake web:bundle
```

For production bundle:

```bash
cd web
bun run build:prod
```

or:

```bash
bundle exec rake web:bundle:prod
```

`web:bundle` copies required third-party runtime files (`vim-wasm`, `ghostty-web`) into `web/dist/assets/pkg` so editor and terminal WASM integrations are packaged together.

## Run Web UI

Serve the bundled `web/dist` directory:

```bash
bundle exec rake web:start
```

`web:start` serves with cross-origin isolation headers required for `SharedArrayBuffer`:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`
- `Cross-Origin-Resource-Policy: same-origin`

If you use a custom server, you must set equivalent headers.

Without those headers, the mirb worker will not be able to use `SharedArrayBuffer`.

Manual example (must be configured to emit COOP/COEP):

```bash
cd web/dist
python3 -m http.server 8080
```

Open [http://localhost:8080](http://localhost:8080).

## Desktop app (Electrobun)

Desktop builds package the same `web/dist/` output into `web/desktop/src/simulator` via
`web/desktop/scripts/prebuild.ts`.

```bash
# From repository root
bundle exec rake desktop:install   # Install Electrobun dependencies
bundle exec rake web:bundle       # Ensure web/dist is fresh (or run `bun run build` in web/)
bundle exec rake desktop:dev      # Build and launch desktop app in dev mode
bundle exec rake desktop:build    # Build dev package output
bundle exec rake desktop:release  # Build stable package output
bundle exec rake desktop:clean    # Remove packaged desktop artifacts
```

`desktop:dev`/`desktop:build`/`desktop:release` rely on the prebuild hook to sync the `web/dist` bundle.

## Runner Presets and Defaults

Runner presets are generated into:

- `web/app/components/runner/config/generated_presets.ts`

Current generated runner order:

- `generic` (manual IR runner, from `presets.ts`)
- `cpu`
- `mos6502`
- `apple2`
- `gameboy`
- `riscv`
- `riscv_linux`

Current defaults:

- Default runner preset: `apple2`
- Default backend state: `compiler` (`Compiler (AOT)`)
- Trace capture starts disabled on load for all presets (`traceEnabledOnLoad: false`)
- To auto-enable trace at runner load, set `runner.traceEnabledOnLoad: true` (or legacy `runner.defaults.traceEnabled: true`) in the runner config JSON before `bundle exec rake web:generate`

Preset generation source list is controlled by:

- `lib/rhdl/cli/tasks/web_generate_task.rb` (`RUNNER_CONFIG_PATHS`)

Current generated list includes:

- `examples/8bit/config.json`
- `examples/mos6502/config.json`
- `examples/apple2/config.json`
- `examples/gameboy/config.json`
- `examples/riscv/config.json`
- `examples/riscv/config_linux.json`

RISC-V web preset status:

- Included by default in `RUNNER_CONFIG_PATHS` and exported as:
  - `riscv` (xv6)
  - `riscv_linux` (Linux)
- `riscv` maps to UART I/O (`mode: uart`) with:
  - `./assets/fixtures/riscv/software/bin/kernel.bin`
  - `./assets/fixtures/riscv/software/bin/fs.img`
  - `./assets/pkg/ir_compiler_riscv.wasm`
  - custom xv6 kernel/disk binaries can be swapped in through runner controls, but the defaults above are the shipped preloads
- `riscv_linux` maps to UART I/O (`mode: uart`) and loads Linux assets when present:
  - `./assets/fixtures/riscv/software/bin/linux_kernel.bin`
  - `./assets/fixtures/riscv/software/bin/linux_initramfs.cpio`
  - `./assets/fixtures/riscv/software/bin/rhdl_riscv_virt.dtb`
  - `./assets/fixtures/riscv/software/bin/linux_bootstrap.bin`
- Note: regenerate assets from `examples/riscv/config.json` / `examples/riscv/config_linux.json` whenever preset defaults change so generated presets stay aligned.
- If RISC-V preset assets are not generated, preset selection still appears but default boot will skip/fail the required loads.

## Deploy To GitHub Pages

- A workflow is included at `.github/workflows/pages.yml`.
- It builds all web artifacts via:
  - `bundle exec rake web:generate`
  - `bundle exec rake web:bundle`
- It publishes a static artifact containing:
  - `web/dist/index.html`
  - `web/dist/coi-serviceworker.js`
  - `web/dist/` (bundled JS, WASM, and static assets)
- GitHub Pages does not let this repo configure COOP/COEP response headers directly.
- `index.html` registers `coi-serviceworker.js` to inject COOP/COEP/CORP on same-origin responses as a fallback.
- Enable Pages in repository settings:
  - `Settings -> Pages -> Source: GitHub Actions`
- Deploy URL will be exposed in the workflow run after the `deploy` job completes.

## Run Tests

Run all web unit tests (no build step required):

```bash
bun test $(find web/test -type f -name '*.test.ts' | sort)
```

Run only browser integration smoke tests (Playwright):

```bash
cd web
bun install
bunx playwright install chromium
bun run test:integration
```

Useful integration suites:

- `web/test/integration/app_load.test.ts`
- `web/test/integration/app_flows.test.ts`
- `web/test/integration/mos6502_compiler_backend.test.ts`
- `web/test/integration/cpu8bit_default_bin_autoload.test.ts`
- `web/test/integration/cpu8bit_programs.test.ts`
- `web/test/integration/memory_dump_asset_tree.test.ts`
- `web/test/integration/memory_follow_pc_highlight.test.ts`

Run only state store tests:

```bash
bun test web/test/state/store.test.ts
```

## Notes

- The selected dropdown sample is loaded automatically on startup (default: `assets/fixtures/apple2/ir/apple2.json`).
- Backend selection is in the left control panel.
- `compiler` (AOT wasm) is the default backend state at startup.
- `compiler` in the web UI is `ir_compiler` AOT (precompiled wasm), not runtime `rustc` compilation in-browser.
- Terminal command help is available in-app via `help` and includes runner/backend/theme/sim/watch/breakpoint/memory actions.
- Apple II / CPU runner assets are included under `assets/fixtures/`:
  - `assets/fixtures/apple2/ir/apple2.json` (from `examples/apple2/hdl/apple2`)
  - `assets/fixtures/apple2/ir/apple2_sources.json` (`RHDL` + `Verilog` sources for Apple II components)
  - `assets/fixtures/apple2/ir/apple2_schematic.json` (precomputed schematic connectivity for Apple II)
  - `assets/fixtures/cpu/ir/cpu_sources.json` (`RHDL` + `Verilog` sources for CPU components)
  - `assets/fixtures/cpu/ir/cpu_schematic.json` (precomputed schematic connectivity for CPU)
- `assets/fixtures/apple2/memory/appleiigo.rom` (12KB system ROM)
- `assets/fixtures/apple2/memory/karateka_mem.bin` + `assets/fixtures/apple2/memory/karateka_mem_meta.txt` for quick dump load
- Build/update wasm backends only:
  - `bundle exec rake web:build`
  - `bundle exec rake web:bundle`
- Regenerate web artifacts (IR + source + schematic):
  - `bundle exec rake web:generate`
- Memory tab supports:
  - arbitrary dump file load at offset (via Apple II RAM interface)
  - one-click Karateka dump load (patches reset vector and resets to dump PC)
- Clock options are labeled by execution mode:
  - `forced`: direct process clock stepping (`tick_forced`)
  - `driven`: toggle external clock (for example top-level `clk`) and propagate through combinational logic
- The UI consumes incremental VCD chunks from `trace_take_live_vcd()` each frame.
- Redux state bridge (if `redux.min.js` loads):
  - store: `window.__RHDL_REDUX_STORE__`
  - current in-memory app state: `window.__RHDL_UX_STATE__`
  - manual sync helper: `window.__RHDL_REDUX_SYNC__('manual')`

## Web App Architecture

This section describes the current architecture of the RHDL web simulator and where responsibilities live.

### Runtime Model

- `web/app/core/bootstrap.ts` is the composition root.
- `web/app/main.ts` loads UI components and starts bootstrap.
- Bootstrap creates:
  - DOM refs (`bindings/dom_bindings.ts`)
  - mutable runtime context (`runtime/context.ts`)
  - mutable UX state (`state/initial_state.ts`)
  - Redux store + bridge (`state/store.ts`, `state/store_bridge.ts`)
  - controller registry (`controllers/registry_controller.ts`)
  - startup orchestration (`controllers/startup_controller.ts`)

### Layering

- `state/`: reducers, actions, store plumbing, redux sync helpers.
- `runtime/`: backend definitions, wasm simulator wrapper, VCD parser.
- `controllers/`: app behavior and orchestration. High-level intent lives here.
- `controllers/terminal/`: command routing and command handlers.
- `controllers/registry_lazy/`: lazy construction for heavy controller/managers.
- `managers/`: reusable behavior units (watch manager, dashboard layout manager).
- `bindings/`: DOM event wiring that maps UI events to controller-domain operations.
- `components/`: LitElement panels and rendering helpers.
- `lib/`: shared pure utilities (numeric parsing, IR metadata, dashboard/state helpers).

### Registry + Domains

`createControllerRegistry` returns grouped domains consumed by startup/bindings:

- `shell`
- `runner`
- `components`
- `apple2`
- `sim`
- `watch`

Each domain exposes cohesive capabilities instead of one flat API bag. Lazy getters in
`controllers/registry_lazy/*` defer heavy object construction until needed.

### Startup Contract

`startApp` receives explicit grouped dependencies:

- `env`: host environment hooks
- `store`: state dispatchers/sync helpers
- `util`: pure utility functions
- `keys`: storage keys/constants
- `bindings`: binding constructors + UI binding registry
- `app`: registry domains

This keeps startup deterministic and testable without browser globals.

### UI Composition

- `index.html` contains shell markup and panel containers.
- Lit components (`components/*.ts`) own panel-specific rendering and styles.
- Bindings attach listeners and call domain methods.
- Redux sync snapshots app state for toolability and test instrumentation.

### Schematic Renderer

The component schematic tab (`5. Schematic`) renders interactive RTL schematics
with hierarchical drill-down into sub-components.

**Layout** is handled by [ELK.js](https://github.com/kieler/elkjs) (Eclipse Layout
Kernel), a port-aware hierarchical layout engine loaded from CDN. An adapter
converts the internal render list into an ELK graph, runs the layout, and maps
computed positions back onto the schematic primitives (symbols, pins, nets, wires).

**Rendering** uses a WebGL 2.0 instanced pipeline as the primary backend, with a
Canvas 2D fallback for environments where WebGL is unavailable (e.g. headless
browsers). Both renderers consume the same flat `RenderList` of typed primitives
and resolve colors from a shared theme palette. The WebGL path uses SDF
rounded-rect fragment shaders for crisp edges at any zoom level.

**Interaction** is built on a spatial R-tree index over rendered elements.
Single-click selects a component or highlights a signal; double-click drills down
into a child component's internal schematic. Left-button drag pans the viewport,
mouse wheel/trackpad scroll zooms around the cursor, and `Zoom +` / `Zoom -` /
`Reset View` buttons provide explicit viewport controls.

**Live activity** updates wire and net colors each frame based on current signal
values from the running simulation — non-zero signals highlight in green, toggled
signals flash amber. This animation is gated by trace state: when trace is off,
schematic activity is static; when trace is on, live activity animates.

Each element type has a distinct color: cyan for components, purple for IO ports,
amber for ops/assigns, copper for memory, green for nets, and neutral gray for
pins. A color legend is drawn in screen space in the bottom-right corner.

### Testing Strategy

- Unit tests:
  - controller units (`test/controllers`)
  - binding units (`test/bindings`)
  - manager/runtime/lib/state modules
- Browser integration tests (`test/integration`):
  - app load smoke
  - core user flows (runner load, memory dump actions, run/pause, terminal commands)

### Static Assets

- `assets/pkg`: wasm artifacts.
- `assets/fixtures`: generated IR/source/schematic fixtures and sample binary assets.
- `bundle exec rake web:build`: wasm build pipeline entrypoint.
- `bundle exec rake web:bundle`: Bun bundle entrypoint for `web/dist/`.
- `bundle exec rake web:generate`: web asset generation entrypoint (builds wasm first when missing).
