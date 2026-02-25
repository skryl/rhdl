# PRD: Custom D3.js RTL Visualizer with GPU Acceleration

**Status:** Proposed
**Date:** 2026-02-25
**Author:** Agent

---

## Context

The web simulator's RTL schematic visualizer currently uses **Cytoscape.js 3.30.2** for graph rendering and **ELK.js 0.9.3** for hierarchical port-based layout. While functional, Cytoscape imposes constraints:

- **Styling is CSS-selector based** — limited to Cytoscape's property vocabulary (no arbitrary SVG/HTML in nodes).
- **Rendering is canvas-only** — no native SVG output, no custom draw routines per node type.
- **Performance ceiling** — large schematics (hundreds of symbols, thousands of wires) hit frame drops during pan/zoom and live signal updates because every style class toggle triggers a full canvas redraw.
- **Schematic fidelity** — RTL schematics have domain-specific conventions (shaped symbols for muxes/ALUs/registers, bus ripper notation, clock domain coloring, pin stub rendering) that Cytoscape's generic graph model cannot express without hacks.
- **Node interiors** — Cytoscape nodes are opaque rectangles; we cannot render port labels, internal structure, or miniature waveforms inside a component box.

Replacing Cytoscape with a **D3.js data-binding layer + WebGL-accelerated rendering backend** will give us full control over visual fidelity, custom symbol shapes, and the performance headroom to render large Apple II / RISC-V schematics with live signal animation at 60fps.

### Current Code Map

Files being replaced (under `web/app/components/explorer/`):

| File | Role | Cytoscape coupling |
|------|------|--------------------|
| `services/graph_runtime_service.mjs` | Graph lifecycle, `window.cytoscape()` init, render loop | Direct: creates Cytoscape instance, calls `cy.batch()`, `cy.animate()`, `cy.resize()` |
| `controllers/graph/interactions.mjs` | Tap/click handlers | Direct: `cy.on('tap', 'node', ...)`, `cy.on('tap', 'edge', ...)` |
| `lib/graph_activity.mjs` | Live signal value updates | Direct: `cy.nodes()`, `cy.edges()`, `node.toggleClass()`, `cy.batch()` |
| `controllers/graph/layout_elk.mjs` | ELK layout execution | Direct: reads from `cy.nodes()`, writes via `symbol.position()`, `cy.fit()` |
| `controllers/graph/theme.mjs` | Palette + Cytoscape style rules | Direct: returns Cytoscape CSS-selector style array |
| `lib/schematic_element_builder.mjs` | Schematic JSON to elements | Indirect: outputs `{data: {id, ...}, classes: '...'}` Cytoscape element format |

Existing tests (under `web/test/components/explorer/`):

| Test file | What it covers |
|-----------|---------------|
| `services/graph_runtime_service.test.mjs` | `destroyComponentGraph()`, `describeComponentGraphPanel()`, callback validation |
| `controllers/graph/interactions.test.mjs` | Node/edge/canvas tap dispatch, double-tap drill-down, signal highlighting |
| `controllers/graph/controller.test.mjs` | Graph controller lifecycle, callback validation |
| `controllers/model_controller.test.mjs` | Selection, focus state management |

Test runner: `node --test` (Node.js native test module). Run via `npm run test:unit` from `web/`.

---

## Goals

1. Replace Cytoscape.js with a custom renderer built on D3.js for data binding, scales, and zoom/pan.
2. Use WebGL (via `regl` or raw shaders) for GPU-accelerated rendering of nodes and edges, falling back to Canvas 2D where WebGL is unavailable.
3. Retain ELK.js for hierarchical port-based layout — it is purpose-built for this and not worth replacing.
4. Preserve all existing interactive features: drill-down navigation, signal highlighting, live value updates, theme switching.
5. Maintain the existing schematic data contract (`symbols`, `pins`, `nets`, `wires` JSON) and state shape — the renderer is a drop-in replacement for the Cytoscape integration layer.
6. Improve rendering performance for large schematics (target: 500+ symbols, 2000+ wires at 60fps pan/zoom).

## Non-Goals

- Replacing ELK.js with a D3 force layout. ELK's layered algorithm with port constraints is critical for readable RTL schematics.
- Changing the schematic data generation pipeline (Ruby-side `Codegen::Schematic`).
- Rewriting the component tree, inspector, or signal panels — only the graph rendering surface changes.
- Adding new schematic features (e.g., timing diagrams inside nodes) in this PRD. This lays the foundation; enhancements come later.
- Supporting non-Chromium browsers for WebGL 2.0. Canvas 2D fallback covers Firefox/Safari edge cases.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    State (existing)                      │
│  components.graphFocusId, graphHighlightedSignal, ...   │
└──────────────┬──────────────────────────┬───────────────┘
               │ data                     │ interactions
               ▼                          ▼
┌──────────────────────┐   ┌──────────────────────────────┐
│  SchematicDataModel   │   │   D3 Zoom/Pan Behavior       │
│  (element transform)  │   │   Hit Testing (spatial index)│
│  Cytoscape elements → │   │   Selection / Drill-down     │
│  render primitives    │   └──────────────┬───────────────┘
└──────────┬───────────┘                   │
           │ render list                   │ viewport transform
           ▼                               ▼
┌─────────────────────────────────────────────────────────┐
│               WebGL Render Pipeline                     │
│                                                         │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐             │
│  │ Symbol    │ │ Wire      │ │ Label     │             │
│  │ Pass      │ │ Pass      │ │ Pass      │             │
│  │ (instanced│ │ (line     │ │ (SDF text │             │
│  │  quads)   │ │  segments)│ │  atlas)   │             │
│  └───────────┘ └───────────┘ └───────────┘             │
│                                                         │
│  Uniforms: viewMatrix, zoom, time (animation)           │
│  Attributes: position, size, color, state flags         │
└─────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────┐
│   <canvas> element   │
│   (WebGL context)    │
│   + SVG overlay for  │
│     tooltips/menus   │
└─────────────────────┘
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout engine | Keep ELK.js | Best-in-class for layered port-based layout; async worker model |
| Data binding | D3.js (selections, scales, zoom) | Industry standard; excellent zoom/pan behavior; no framework lock-in |
| GPU rendering | WebGL 2.0 via `regl` | Minimal abstraction over GL; instanced drawing; small bundle (~45KB) |
| Text rendering | SDF (signed distance field) bitmap atlas | GPU-rendered text that stays sharp at all zoom levels |
| Edge routing | Orthogonal segments from ELK + GPU line rendering | ELK computes routes; we render as GL line segments with configurable width |
| Hit testing | R-tree spatial index (`rbush`) | O(log n) point queries for click/hover; updated after layout |
| Fallback | Canvas 2D renderer (same data model) | If WebGL unavailable, draw with 2D context using identical layout |
| Overlay | Thin SVG layer for tooltips, context menus | DOM-based overlays are easier for rich interactive popups |

---

## Phased Plan

### Phase 1: Renderer-Agnostic Data Model

**Objective:** Extract a renderer-agnostic data model from the existing Cytoscape element format. This decouples layout and rendering from Cytoscape's API without changing any visible behavior.

The existing `schematic_element_builder.mjs` outputs Cytoscape-format elements: `{data: {id, ...}, classes: 'schem-component schem-focus'}`. This phase creates a `RenderList` — a flat array of typed primitives (symbols, pins, nets, wires) with explicit coordinates, dimensions, and state — that any renderer can consume.

**Red:**

1. Create test file `web/test/components/explorer/renderers/schematic_data_model.test.mjs`.
2. Write test: `buildRenderList()` given a minimal Cytoscape element array (2 symbols, 3 pins, 1 net, 2 wires) returns a `RenderList` with:
   - `symbols` array: each entry has `{id, x, y, width, height, type, label, componentId, classes}`.
   - `pins` array: each entry has `{id, x, y, width, height, symbolId, side, direction, signalName, liveName, valueKey}`.
   - `nets` array: each entry has `{id, x, y, width, height, label, signalName, liveName, valueKey, bus}`.
   - `wires` array: each entry has `{id, sourceId, targetId, signalName, liveName, valueKey, width, direction, kind, bus}`.
3. Write test: `buildRenderList()` with empty input returns empty sub-arrays.
4. Write test: symbol `type` field is derived from class string — `'schem-component schem-focus'` → `type: 'focus'`, `'schem-memory'` → `type: 'memory'`, etc.
5. Run `node --test web/test/components/explorer/renderers/schematic_data_model.test.mjs` — all tests **fail** (module does not exist).

**Green:**

6. Create `web/app/components/explorer/renderers/schematic_data_model.mjs`.
7. Implement `buildRenderList(cytoscapeElements)`:
   - Parse the Cytoscape element array into four typed sub-arrays.
   - Derive `type` from the `classes` string (`schem-focus` → focus, `schem-component` → component, `schem-io` → io, `schem-memory` → memory, `schem-op` → op, `schem-net` → net, `schem-pin` → pin).
   - Copy all data fields (`signalName`, `liveName`, `valueKey`, `width`, `side`, `direction`, etc.) to the primitive.
   - Default coordinates to `{x: 0, y: 0}` (layout applies positions later).
8. Implement `applyLayoutPositions(renderList, elkOutput)`:
   - Takes ELK `layout()` output and applies `{x, y}` to each symbol, pin, and net by ID.
   - Pin positions are computed relative to parent symbol (same math as current `layout_elk.mjs` lines 136-156).
9. Run tests — all **pass**.

**Refactor:**

10. Extract shared constants (`SYMBOL_TYPE_MAP`, default dimensions) into a `renderers/constants.mjs` if the data model file exceeds 200 lines.

**Exit Criteria:**
- `buildRenderList()` produces correctly typed primitives from Cytoscape-format elements.
- `applyLayoutPositions()` matches the existing ELK position application logic.
- Existing code unchanged — this is a new module only.

---

### Phase 2: Canvas 2D Renderer + Symbol Shapes

**Objective:** Implement a Canvas 2D renderer that draws the `RenderList` to a `<canvas>` element, plus a symbol shape library.

**Red:**

1. Create test file `web/test/components/explorer/renderers/canvas_renderer.test.mjs`.
2. Write test: `createCanvasRenderer(canvas)` returns an object with `render(renderList, viewport)` and `destroy()` methods.
3. Write test: calling `render()` with a `RenderList` containing 2 symbols and 1 wire calls `ctx.fillRect` / `ctx.strokeRect` / `ctx.moveTo` / `ctx.lineTo` the expected number of times (mock the 2D context).
4. Write test: calling `render()` with an empty `RenderList` clears the canvas but does not throw.
5. Create test file `web/test/components/explorer/renderers/symbols.test.mjs`.
6. Write test: `symbolShapes` map has entries for each type: `component`, `focus`, `io`, `memory`, `op`, `net`, `pin`.
7. Write test: each shape's `draw(ctx, x, y, w, h, state)` function calls `ctx.beginPath()` at least once (mock context).
8. Run tests — all **fail**.

**Green:**

9. Create `web/app/components/explorer/renderers/symbols.mjs`:
   - Export `symbolShapes` — a `Map<type, {draw(ctx, x, y, w, h, state), boundingBox(x, y, w, h)}>`.
   - `component` / `focus`: rounded rectangle (`ctx.roundRect`), border width varies by type.
   - `memory`: double-border rounded rectangle.
   - `io`: small rounded rectangle with directional arrow marker.
   - `op`: rounded rectangle with operation label.
   - `net`: compact rounded rectangle.
   - `pin`: small rounded rectangle marker.
10. Create `web/app/components/explorer/renderers/canvas_renderer.mjs`:
    - `createCanvasRenderer(canvas)` — gets 2D context, stores reference.
    - `render(renderList, viewport, palette)`:
      - Clear canvas.
      - Apply viewport transform (`ctx.setTransform(scale, 0, 0, scale, tx, ty)`).
      - Draw wires as orthogonal line segments (straight lines between source/target positions via net positions, matching Cytoscape `taxi` routing).
      - Draw each symbol using the shape library.
      - Draw labels with `ctx.fillText()`.
      - Draw pins using pin shape.
      - Draw nets using net shape.
    - `destroy()` — clear canvas, release references.
11. Run tests — all **pass**.

**Refactor:**

12. Ensure draw order is correct: wires first (back), then symbols, then pins, then net labels, then symbol labels (front).

**Exit Criteria:**
- Canvas renderer draws all element types from a `RenderList`.
- Symbol shapes are type-specific (not all identical rectangles).
- Renderer does not reference Cytoscape in any way.

---

### Phase 3: Spatial Index + D3 Interactions

**Objective:** Implement R-tree hit testing for click/hover and D3.js zoom/pan behavior, producing an interaction layer that dispatches the same state mutations as the current Cytoscape `interactions.mjs`.

**Red:**

1. Create test file `web/test/components/explorer/renderers/spatial_index.test.mjs`.
2. Write test: `buildSpatialIndex(renderList)` returns an index object with `queryPoint(x, y)` that returns the topmost element at that position.
3. Write test: inserting 3 symbols and querying a point inside symbol #2 returns symbol #2's data.
4. Write test: querying a point outside all symbols returns `null`.
5. Write test: querying a point where a pin overlaps a symbol returns the pin (pins are on top).
6. Create test file `web/test/components/explorer/renderers/interactions.test.mjs`.
7. Write test: `bindD3Interactions()` with mock state — clicking coordinates inside a component symbol sets `state.components.selectedNodeId` to that symbol's `componentId` and calls `renderComponentTree()`.
8. Write test: double-clicking (two clicks within 320ms on same component) sets `state.components.graphFocusId` and `state.components.graphShowChildren = true`.
9. Write test: clicking a net sets `state.components.graphHighlightedSignal`.
10. Write test: clicking empty canvas clears `state.components.graphHighlightedSignal`.
11. Run tests — all **fail**.

**Green:**

12. Create `web/app/components/explorer/renderers/spatial_index.mjs`:
    - `buildSpatialIndex(renderList)` — inserts all symbols, pins, nets into an R-tree (`rbush` or a simple array-scan for initial implementation; optimize to `rbush` in refactor).
    - `queryPoint(x, y)` — returns the element whose bounding box contains the point. Priority order: pins > nets > symbols (topmost visual layer wins).
    - `queryRect(x1, y1, x2, y2)` — returns all elements in a rectangle (for future box selection).
13. Create `web/app/components/explorer/renderers/interactions.mjs`:
    - `bindD3Interactions({canvas, state, model, renderList, spatialIndex, renderComponentTree, renderComponentViews, requestRender, now, doubleTapMs})`.
    - Attach D3 zoom behavior to the canvas element: `d3.zoom().on('zoom', ...)` updates a viewport transform and calls `requestRender()`.
    - On `click` event: transform screen coordinates to world coordinates using the inverse viewport transform, query the spatial index, then dispatch:
      - **Component hit:** set `selectedNodeId`, detect double-tap (same component within `doubleTapMs`), set `graphFocusId` + `graphShowChildren` on double-tap. Call `renderComponentTree()` / `renderComponentViews()`.
      - **Net/pin hit:** set `graphHighlightedSignal` from the hit element's `signalName`/`liveName`. Call `renderComponentViews()`.
      - **No hit (canvas):** clear `graphHighlightedSignal`. Call `renderComponentViews()`.
    - Returns `{destroy()}` to detach listeners.
14. Run tests — all **pass**.

**Refactor:**

15. If initial spatial index uses array scan, replace with `rbush` for O(log n) queries. Re-run tests.

**Exit Criteria:**
- Spatial index correctly resolves point queries across overlapping element types.
- D3 zoom/pan produces a viewport transform; click coordinates are correctly transformed to world space.
- All interaction state mutations match the existing `bindGraphInteractions()` behavior (same state fields set, same callbacks invoked).
- Tests mirror the assertions in `web/test/components/explorer/controllers/graph/interactions.test.mjs`.

---

### Phase 4: ELK Layout Adapter

**Objective:** Extract ELK layout integration from the Cytoscape-specific `layout_elk.mjs` into a standalone adapter that operates on the `RenderList` directly.

**Red:**

1. Create test file `web/test/components/explorer/renderers/elk_layout_adapter.test.mjs`.
2. Write test: `runElkLayout(renderList)` given a `RenderList` with 2 symbols (each with 2 pins) and 1 net returns a promise that resolves with updated positions on all elements.
3. Write test: the ELK graph passed to `elk.layout()` has `layoutOptions` matching the current `elkPortLayoutOptions()` (algorithm: 'layered', direction: 'RIGHT', etc.).
4. Write test: pin positions are offset relative to their parent symbol position (same formula as `layout_elk.mjs` lines 148-156).
5. Write test: if `window.ELK` is not available, returns `{engine: 'missing'}` without throwing.
6. Run tests — all **fail**.

**Green:**

7. Create `web/app/components/explorer/renderers/elk_layout_adapter.mjs`:
   - `async runElkLayout(renderList, options)`:
     - Build ELK graph from `renderList.symbols` (as children with ports from `renderList.pins`) and `renderList.nets` (as children) and `renderList.wires` (as edges).
     - Port side mapping: reuse `toElkPortSide()` logic from current code.
     - Layout options: reuse `elkPortLayoutOptions()` from current code.
     - Call `new window.ELK().layout(graph)`.
     - Apply resulting positions back to `renderList` elements via `applyLayoutPositions()` from Phase 1.
     - Return `{engine: 'elk'}` on success, `{engine: 'error'}` on failure, `{engine: 'missing'}` if ELK unavailable.
   - Pin position formula: `px = symbolX + port.x + port.width * 0.5`, `py = symbolY + port.y + port.height * 0.5` (matching current lines 153-155).
8. Mock `window.ELK` in tests with a fake that returns predetermined positions.
9. Run tests — all **pass**.

**Refactor:**

10. Extract `elkPortLayoutOptions()` and `toElkPortSide()` into shared helpers importable by both old and new code (avoid duplication during transition period).

**Exit Criteria:**
- ELK layout adapter produces identical node/pin positions as the current `layout_elk.mjs` for the same input.
- No Cytoscape dependency — operates entirely on `RenderList`.
- Graceful degradation when ELK is unavailable.

---

### Phase 5: Live Signal Activity on RenderList

**Objective:** Port `updateGraphActivity()` from Cytoscape class toggling to direct state mutation on `RenderList` primitives.

**Red:**

1. Create test file `web/test/components/explorer/renderers/render_activity.test.mjs`.
2. Write test: `updateRenderActivity(renderList, signalLiveValueByName, highlightedSignal, previousValues)` — given a net with `liveName: 'cpu__clk'` and `signalLiveValueByName('cpu__clk')` returning `1n`, sets `net.active = true`.
3. Write test: when the same net's value changes from `'0'` to `'1'` (previous values map has `'0'`), sets `net.toggled = true`.
4. Write test: when `highlightedSignal.liveName === 'cpu__clk'`, sets `net.selected = true`.
5. Write test: wires connected to the net inherit the net's `active`/`toggled`/`selected` state via `valueKey` lookup.
6. Write test: returns a new `previousValues` map for use in the next cycle.
7. Run tests — all **fail**.

**Green:**

8. Create `web/app/components/explorer/renderers/render_activity.mjs`:
   - `updateRenderActivity({renderList, signalLiveValueByName, toBigInt, highlightedSignal, previousValues})`:
     - Iterate `renderList.nets` and `renderList.pins`:
       - Look up live value via `signalLiveValueByName(liveName)`.
       - Convert to BigInt string via `toBigInt(value).toString()`.
       - Compare with `previousValues.get(valueKey)` for toggle detection.
       - Set `element.active`, `element.toggled`, `element.selected` booleans.
     - Iterate `renderList.wires`:
       - Look up aggregated value from the nets/pins `nextValues` map via `valueKey`.
       - Set `wire.active`, `wire.toggled`, `wire.selected`.
     - Return `nextValues` map.
   - Logic mirrors `graph_activity.mjs` lines 1-66 exactly, but writes to object properties instead of Cytoscape `toggleClass()`.
9. Run tests — all **pass**.

**Refactor:**

10. None needed — this is a direct port of existing logic to a new data target.

**Exit Criteria:**
- `updateRenderActivity()` produces identical active/toggled/selected states as `updateGraphActivity()` for the same inputs.
- No Cytoscape dependency.
- Return value provides the previous-values map for the next render cycle.

---

### Phase 6: Theme System

**Objective:** Port the color palette and style configuration from Cytoscape CSS-selector format to a renderer-agnostic theme object consumed by the Canvas 2D and (later) WebGL renderers.

**Red:**

1. Create test file `web/test/components/explorer/renderers/themes.test.mjs`.
2. Write test: `getThemePalette('shenzhen')` returns an object with all expected color keys (`componentBg`, `componentBorder`, `wire`, `wireActive`, `wireToggle`, `selected`, etc.) matching the values in current `theme.mjs`.
3. Write test: `getThemePalette('original')` returns the original theme colors.
4. Write test: `resolveElementColors(element, palette)` given a symbol of type `component` with `active: false` returns `{fill: palette.componentBg, stroke: palette.componentBorder, text: palette.componentText}`.
5. Write test: `resolveElementColors()` given a wire with `active: true, toggled: true, selected: false` returns `{stroke: palette.wireToggle, width: 2.7}`.
6. Write test: `resolveElementColors()` given a net with `selected: true` returns `{stroke: palette.selected, strokeWidth: 2.8}`.
7. Run tests — all **fail**.

**Green:**

8. Create `web/app/components/explorer/renderers/themes.mjs`:
   - `getThemePalette(theme)` — returns palette object (copy values from current `createSchematicPalette()`).
   - `resolveElementColors(element, palette)` — returns `{fill, stroke, strokeWidth, text}` based on element type and state flags. Encoding the same style rules from `createSchematicStyle()` but as direct value lookups instead of CSS selectors.
   - Wire style priority: `selected > toggled > active > default` (matching current CSS specificity).
   - Wire widths: default 1.4, bus 2.4, active 2.0, toggled 2.7, selected 3.2 (matching current CSS).
9. Run tests — all **pass**.

**Refactor:**

10. None needed.

**Exit Criteria:**
- Theme palette values exactly match existing `createSchematicPalette()`.
- Element color resolution produces the same visual appearance as Cytoscape CSS selectors.
- No Cytoscape dependency.

---

### Phase 7: Feature-Flagged Integration

**Objective:** Wire the new renderer stack (Phases 1-6) into `graph_runtime_service.mjs` behind a feature flag so both renderers coexist.

**Red:**

1. Add test to `web/test/components/explorer/services/graph_runtime_service.test.mjs`:
   - Test: when `state.components.graphRenderer === 'd3'`, `ensureComponentGraph()` does NOT call `window.cytoscape()` and instead creates a `<canvas>` element, builds a `RenderList`, runs ELK layout, binds D3 interactions, and returns a renderer handle.
2. Add test: `renderComponentVisual()` with `graphRenderer: 'd3'` calls `updateRenderActivity()` and triggers a canvas re-render.
3. Add test: `destroyComponentGraph()` with `graphRenderer: 'd3'` calls the renderer's `destroy()` and the interactions' `destroy()`.
4. Add test: switching from `graphRenderer: 'cytoscape'` to `'d3'` destroys the old graph and creates a new renderer.
5. Run tests — new tests **fail** (feature flag path not implemented). Existing tests still **pass** (default is still `'cytoscape'`).

**Green:**

6. Modify `graph_runtime_service.mjs`:
   - Add `state.components.graphRenderer` field (default: `'cytoscape'`).
   - In `ensureComponentGraph()`: branch on `graphRenderer`:
     - `'cytoscape'` path: existing code unchanged.
     - `'d3'` path:
       1. Call `createSchematicElements()` (existing) to get Cytoscape-format elements.
       2. Call `buildRenderList(elements)` to convert to render primitives.
       3. Call `runElkLayout(renderList)` to position elements.
       4. Create `<canvas>` element, append to `dom.componentVisual`.
       5. Call `createCanvasRenderer(canvas)` to get the renderer.
       6. Call `buildSpatialIndex(renderList)` for hit testing.
       7. Call `bindD3Interactions({...})` for interaction handlers.
       8. Store renderer handle in `state.components.graph` (replacing Cytoscape instance).
   - In `renderComponentVisual()`: branch on `graphRenderer`:
     - `'d3'` path: call `updateRenderActivity()`, then `renderer.render(renderList, viewport, palette)`.
   - In `destroyComponentGraph()`: branch on `graphRenderer`:
     - `'d3'` path: call `renderer.destroy()`, `interactions.destroy()`, clear canvas.
7. Add `graphRenderer` to the `graphKey` cache key so switching renderers forces a rebuild.
8. Run tests — all **pass** (new and existing).

**Refactor:**

9. Extract the two code paths into separate helper functions (`ensureCytoscapeGraph()`, `ensureD3Graph()`) to keep `ensureComponentGraph()` clean.

**Exit Criteria:**
- `state.components.graphRenderer = 'd3'` activates the full new stack.
- `state.components.graphRenderer = 'cytoscape'` (default) uses unchanged existing code.
- Existing tests continue to pass unchanged.
- New tests validate the D3 path end-to-end (data model → layout → render → interactions → activity updates).

---

### Phase 8: WebGL Render Pipeline

**Objective:** Replace Canvas 2D drawing with GPU-accelerated WebGL rendering via `regl`, keeping the same data model, interaction layer, and theme system.

**Red:**

1. Create test file `web/test/components/explorer/renderers/webgl_renderer.test.mjs`.
2. Write test: `createWebGLRenderer(canvas)` returns an object with `render(renderList, viewport, palette)` and `destroy()` methods (same interface as `canvasRenderer`).
3. Write test: if `canvas.getContext('webgl2')` returns `null`, `createWebGLRenderer()` returns `null` (signals fallback to Canvas 2D).
4. Write test: `render()` calls `regl.frame()` or equivalent draw call.
5. Write benchmark test: generate a synthetic `RenderList` with 500 symbols, 500 nets, 1500 pins, 2000 wires. Measure time for `render()` call. Assert < 16ms.
6. Run tests — all **fail**.

**Green:**

7. Add `regl` dependency (CDN script tag in `index.html`, or ESM import if bundled).
8. Create `web/app/components/explorer/renderers/webgl_renderer.mjs`:
   - `createWebGLRenderer(canvas)`:
     - Get WebGL 2.0 context. Return `null` if unavailable.
     - Initialize `regl` with the context.
     - Create draw commands:
       - **Symbol pass:** Instanced quad rendering. Per-instance attributes: `[x, y, width, height, fillR, fillG, fillB, strokeR, strokeG, strokeB, strokeWidth, cornerRadius]`. Vertex shader positions quad corners; fragment shader draws rounded-rect with border.
       - **Wire pass:** Instanced line-segment rendering. Per-instance: `[x1, y1, x2, y2, width, r, g, b, dashFlag]`. Fragment shader handles solid/dashed lines.
       - **Pin pass:** Instanced small quads, same approach as symbols but smaller.
       - **Label pass:** Canvas 2D offscreen texture for text (simpler than SDF for initial implementation). Render all labels to an offscreen canvas, upload as texture, render as textured quads at correct positions.
     - `render(renderList, viewport, palette)`:
       1. Build/update instance buffers from `renderList` + `resolveElementColors()`.
       2. Set viewport uniform from D3 zoom transform: `mat3 = [scale, 0, tx, 0, scale, ty, 0, 0, 1]`.
       3. Execute draw commands in order: wires → symbols → pins → labels.
     - `destroy()` — destroy `regl` instance, release buffers.
9. Create `web/app/components/explorer/renderers/webgl_shaders.mjs`:
   - Vertex and fragment GLSL source strings for each pass.
   - Rounded-rect fragment shader using SDF: `float d = sdfRoundedRect(uv, size, radius); float alpha = smoothstep(0.0, fwidth(d), -d);`
10. Modify `graph_runtime_service.mjs` (d3 path in `ensureD3Graph()`):
    - Try `createWebGLRenderer(canvas)` first.
    - If returns `null`, fall back to `createCanvasRenderer(canvas)`.
    - Store which renderer is active in `state.components.graphRenderBackend: 'webgl' | 'canvas2d'`.
11. Add `webglcontextlost` / `webglcontextrestored` handlers on canvas to gracefully handle GPU context loss (switch to Canvas 2D on loss, try WebGL again on restore).
12. Run tests — all **pass**. Benchmark test passes (< 16ms for 500-symbol render).

**Refactor:**

13. Profile instance buffer updates — if rebuilding every frame is a bottleneck, implement dirty tracking (only rebuild buffers for elements whose state changed since last frame).

**Exit Criteria:**
- WebGL renderer active by default when WebGL 2.0 is available.
- Automatic fallback to Canvas 2D otherwise.
- Pan/zoom is purely a uniform update (no geometry recomputation).
- 500+ symbols render within 16ms frame budget.
- WebGL context loss does not crash — falls back gracefully.

---

### Phase 9: Signal Animation + Visual Polish

**Objective:** Add wire pulse animations, domain-specific symbol shapes, bus rendering, and smooth navigation transitions.

**Red:**

1. Create test file `web/test/components/explorer/renderers/animation.test.mjs`.
2. Write test: `createAnimationState()` returns an object with `tick(dt)` and `getWireAnimation(wireId)`.
3. Write test: when a wire transitions from `toggled: false` to `toggled: true`, `getWireAnimation(wireId)` returns `{pulseT: 0.0}`. After `tick(100)` (100ms), `pulseT` advances to `0.5` (200ms total animation duration).
4. Write test: when `pulseT >= 1.0`, animation completes and `getWireAnimation()` returns `null`.
5. Write test: `symbolShapes` updated to have distinct shapes — `memory` shape calls `ctx.rect` twice (double border), `io` shape draws a directional arrow.
6. Run tests — new tests **fail**.

**Green:**

7. Create `web/app/components/explorer/renderers/animation.mjs`:
   - `createAnimationState()`:
     - Tracks per-wire animation state keyed by wireId.
     - `markToggled(wireId)` — starts a 200ms pulse animation.
     - `tick(dtMs)` — advances all active animations, removes completed ones.
     - `getWireAnimation(wireId)` — returns `{pulseT}` (0.0 to 1.0) or `null`.
   - Wire pulse effect: bright wavefront color interpolated along wire length based on `pulseT`.
8. Update `webgl_shaders.mjs`:
   - Add `uniform float uTime` to wire pass.
   - Wire fragment shader: when pulse active, interpolate color from `wireToggle` → `white` → `wireToggle` based on `uTime` and wire segment position.
   - Active wires: subtle glow via additive blending (`gl_FragColor.rgb += glowColor * 0.15`).
9. Update `symbols.mjs` with domain-specific shapes:
   - **Register/DFF:** Rectangle with small clock triangle marker on left edge.
   - **Memory:** Double-border rectangle (outer rect + inner rect with gap).
   - **I/O in:** Right-pointing arrow shape.
   - **I/O out:** Left-pointing arrow shape.
   - **Op/ALU:** Rectangle with small `=` or operation glyph.
10. Update wire rendering for buses:
    - Bus wires (`width > 1`): render as double-line (two parallel lines) or thicker with hatching.
    - Bus width label: small text near bus endpoint showing bit width.
11. Add drill-down transition: when `graphFocusId` changes, animate viewport transform (zoom in to selected component bounds over 300ms using `d3.transition`).
12. Run tests — all **pass**.

**Refactor:**

13. Tune animation timing constants (pulse duration, glow intensity) based on visual review.

**Exit Criteria:**
- Toggled wires produce a visible 200ms pulse animation.
- Symbol shapes are visually distinct per type.
- Buses are visually distinct from single-bit wires.
- Drill-down navigation produces a smooth zoom transition.

---

### Phase 10: Cutover + Cleanup

**Objective:** Remove Cytoscape dependency, remove feature flag, clean up dead code.

**Red:**

1. Change `state.components.graphRenderer` default to `'d3'`.
2. Run full test suite: `node --test $(find web/test -type f -name '*.test.mjs' | sort)`.
3. All tests must **pass** with D3 as default. If any fail, fix them before proceeding.

**Green:**

4. Remove Cytoscape feature flag — delete the `'cytoscape'` branch in `ensureComponentGraph()`, `renderComponentVisual()`, `destroyComponentGraph()`.
5. Remove `state.components.graphRenderer` field.
6. Remove Cytoscape.js CDN `<script>` tag from `web/index.html`.
7. Delete old files:
   - `web/app/components/explorer/controllers/graph/layout_elk.mjs` (replaced by `renderers/elk_layout_adapter.mjs`).
   - `web/app/components/explorer/controllers/graph/theme.mjs` (replaced by `renderers/themes.mjs`).
   - `web/app/components/explorer/controllers/graph/interactions.mjs` (replaced by `renderers/interactions.mjs`).
   - `web/app/components/explorer/lib/graph_activity.mjs` (replaced by `renderers/render_activity.mjs`).
8. Update imports in `graph_runtime_service.mjs` and `controllers/graph/controller.mjs` to use only the new renderers.
9. Update old tests to use new module paths:
   - `interactions.test.mjs` → test the new `renderers/interactions.mjs`.
   - `graph_runtime_service.test.mjs` → remove Cytoscape-specific assertions.
10. Update `docs/web_simulator.md` under `## Web App Architecture` to document the new renderer stack.
11. Run full test suite — all **pass**. Verify no references to `cytoscape` remain: `grep -r 'cytoscape' web/app/ web/test/` returns zero results.

**Refactor:**

12. Clean up any unused imports or dead code paths revealed by the removal.

**Exit Criteria:**
- Cytoscape.js fully removed (no CDN tag, no imports, no references in app or test code).
- All tests pass.
- `docs/web_simulator.md` updated.
- No dead code from old renderer remains.

---

## Acceptance Criteria (Full Completion)

- [ ] Cytoscape.js removed from dependencies.
- [ ] D3.js + WebGL renderer is the default schematic visualizer.
- [ ] Canvas 2D fallback works when WebGL is unavailable.
- [ ] ELK.js layout integration preserved with identical positioning quality.
- [ ] All existing interactions work: drill-down, navigate up/root, signal select, signal highlight, theme switch.
- [ ] Live signal values update at simulation rate with visible active/toggled/selected states.
- [ ] 500+ symbol schematics render at 60fps during pan/zoom.
- [ ] Wire animation provides visual feedback for signal activity.
- [ ] Domain-specific symbol shapes improve schematic readability.
- [ ] Both color themes (Shenzhen, Original) supported.
- [ ] Existing test coverage maintained or improved.
- [ ] `docs/web_simulator.md` updated.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| WebGL context loss on tab switch / GPU driver crash | Blank canvas until recovery | Implement `webglcontextlost`/`webglcontextrestored` handlers; fall back to Canvas 2D on repeated failures |
| SDF text rendering complexity | Blurry or missing labels | Start with Canvas 2D offscreen text atlas (Phase 8); migrate to true SDF post-cutover only if needed |
| `regl` bundle size or API limitations | Larger payload or missing features | `regl` is ~45KB min+gzip; alternative: raw WebGL 2.0 calls (more code but zero dependency) |
| R-tree hit testing accuracy for rotated/complex shapes | Missed clicks on symbols | Use axis-aligned bounding boxes (sufficient for Manhattan-routed schematics); refine with per-shape point-in-polygon for special shapes |
| ELK layout positions don't map cleanly to WebGL coordinates | Misaligned rendering | ELK outputs pixel coordinates; apply same coordinate system to GL viewport with a simple 2D orthographic projection |
| Large schematics overwhelm even GPU | Frame drops on very large designs | Implement level-of-detail: collapse distant components to single rectangles; hide pin/net labels below zoom threshold |
| Browser compatibility (WebGL 2.0) | Safari/older browsers fail | Canvas 2D fallback is a full renderer, not a degraded mode; test on Safari WebKit nightly |
| Feature flag transition period | Bugs in one renderer not caught | Both renderers share the same data model, layout adapter, and theme — only the draw layer differs |

---

## New Dependencies

| Dependency | Version | Size (min+gzip) | Purpose | Phase |
|------------|---------|------------------|---------|-------|
| `d3-selection` | 3.x | ~6KB | Data binding to render list | 3 |
| `d3-zoom` | 3.x | ~8KB | Pan/zoom behavior with inertia | 3 |
| `d3-scale` | 4.x | ~6KB | Color scales for themes/values | 6 |
| `d3-interpolate` | 3.x | ~5KB | Smooth animation interpolation | 9 |
| `d3-transition` | 3.x | ~5KB | Drill-down zoom transitions | 9 |
| `regl` | 2.x | ~45KB | WebGL 2.0 abstraction for instanced rendering | 8 |
| `rbush` | 3.x | ~6KB | R-tree spatial index for hit testing | 3 |
| **Total** | | **~81KB** | vs Cytoscape ~200KB removed | |

Net bundle size change: **~119KB reduction**.

---

## File Structure (New)

```
web/app/components/explorer/
├── renderers/
│   ├── schematic_data_model.mjs      # Cytoscape elements → RenderList (Phase 1)
│   ├── constants.mjs                 # Shared constants, type maps (Phase 1)
│   ├── canvas_renderer.mjs           # Canvas 2D draw implementation (Phase 2)
│   ├── symbols.mjs                   # Symbol shape library (Phase 2, updated Phase 9)
│   ├── spatial_index.mjs             # R-tree wrapper for hit testing (Phase 3)
│   ├── interactions.mjs              # D3 zoom + click dispatch (Phase 3)
│   ├── elk_layout_adapter.mjs        # ELK integration, no Cytoscape (Phase 4)
│   ├── render_activity.mjs           # Live signal state updates (Phase 5)
│   ├── themes.mjs                    # Color palettes + element color resolution (Phase 6)
│   ├── webgl_renderer.mjs            # WebGL instanced draw passes (Phase 8)
│   ├── webgl_shaders.mjs             # GLSL vertex/fragment shaders (Phase 8)
│   └── animation.mjs                 # Wire pulse + transition animations (Phase 9)
│
web/test/components/explorer/
├── renderers/
│   ├── schematic_data_model.test.mjs (Phase 1)
│   ├── canvas_renderer.test.mjs      (Phase 2)
│   ├── symbols.test.mjs              (Phase 2)
│   ├── spatial_index.test.mjs        (Phase 3)
│   ├── interactions.test.mjs         (Phase 3)
│   ├── elk_layout_adapter.test.mjs   (Phase 4)
│   ├── render_activity.test.mjs      (Phase 5)
│   ├── themes.test.mjs               (Phase 6)
│   ├── webgl_renderer.test.mjs       (Phase 8)
│   └── animation.test.mjs            (Phase 9)
```

---

## Implementation Checklist

- [ ] **Phase 1: Renderer-Agnostic Data Model**
  - [ ] `schematic_data_model.test.mjs` — red (tests fail, module missing)
  - [ ] `schematic_data_model.mjs` — green (buildRenderList, applyLayoutPositions)
  - [ ] Refactor: extract constants if needed
- [ ] **Phase 2: Canvas 2D Renderer + Symbol Shapes**
  - [ ] `canvas_renderer.test.mjs` — red
  - [ ] `symbols.test.mjs` — red
  - [ ] `symbols.mjs` — green (shape library for all types)
  - [ ] `canvas_renderer.mjs` — green (draws RenderList to canvas)
  - [ ] Refactor: verify draw order
- [ ] **Phase 3: Spatial Index + D3 Interactions**
  - [ ] `spatial_index.test.mjs` — red
  - [ ] `interactions.test.mjs` — red (mirrors existing interactions.test assertions)
  - [ ] `spatial_index.mjs` — green (R-tree point queries)
  - [ ] `interactions.mjs` — green (D3 zoom + click → state mutations)
  - [ ] Refactor: upgrade to rbush if needed
- [ ] **Phase 4: ELK Layout Adapter**
  - [ ] `elk_layout_adapter.test.mjs` — red
  - [ ] `elk_layout_adapter.mjs` — green (same positions as current layout_elk.mjs)
  - [ ] Refactor: extract shared helpers
- [ ] **Phase 5: Live Signal Activity**
  - [ ] `render_activity.test.mjs` — red
  - [ ] `render_activity.mjs` — green (same logic as graph_activity.mjs)
- [ ] **Phase 6: Theme System**
  - [ ] `themes.test.mjs` — red
  - [ ] `themes.mjs` — green (palette + element color resolution)
- [ ] **Phase 7: Feature-Flagged Integration**
  - [ ] New tests in `graph_runtime_service.test.mjs` — red
  - [ ] `graph_runtime_service.mjs` modified — green (d3 path wired)
  - [ ] Existing tests still pass
  - [ ] Refactor: extract helper functions
- [ ] **Phase 8: WebGL Render Pipeline**
  - [ ] `webgl_renderer.test.mjs` — red
  - [ ] Add `regl` dependency
  - [ ] `webgl_renderer.mjs` — green (instanced symbol/wire/pin/label passes)
  - [ ] `webgl_shaders.mjs` — GLSL shaders
  - [ ] WebGL ↔ Canvas 2D automatic fallback
  - [ ] Performance benchmark passes (< 16ms for 500 symbols)
  - [ ] Refactor: dirty tracking for buffer updates
- [ ] **Phase 9: Signal Animation + Visual Polish**
  - [ ] `animation.test.mjs` — red
  - [ ] `animation.mjs` — green (wire pulse, tick/advance)
  - [ ] Updated `symbols.mjs` — domain-specific shapes
  - [ ] Updated wire rendering — bus double-line
  - [ ] Drill-down zoom transition
- [ ] **Phase 10: Cutover + Cleanup**
  - [ ] Default renderer switched to d3
  - [ ] Full test suite green
  - [ ] Cytoscape CDN tag removed
  - [ ] Old files deleted (layout_elk, theme, interactions, graph_activity)
  - [ ] Imports updated
  - [ ] Tests updated to new paths
  - [ ] `docs/web_simulator.md` updated
  - [ ] Zero `cytoscape` references in app/test code
