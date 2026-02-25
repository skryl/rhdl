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
│                    State (Redux)                        │
│  components.graphFocusId, graphHighlightedSignal, ...   │
└──────────────┬──────────────────────────┬───────────────┘
               │ data                     │ interactions
               ▼                          ▼
┌──────────────────────┐   ┌──────────────────────────────┐
│  SchematicDataModel   │   │   D3 Zoom/Pan Behavior       │
│  (element transform)  │   │   Hit Testing (spatial index)│
│  symbols/pins/nets →  │   │   Selection / Drill-down     │
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

### Phase 1: D3 Data Layer + Canvas 2D Renderer

**Objective:** Replace Cytoscape element creation with a D3 data-binding model and render to a Canvas 2D context. This validates the data pipeline and interaction model before adding WebGL complexity.

**Steps:**

1. **Red:** Write integration test that asserts a schematic renders N symbols and M wires to a canvas element given a known schematic fixture. Test fails because no D3 renderer exists.
2. Create `web/app/components/explorer/renderers/` directory structure:
   - `schematic_data_model.mjs` — transforms schematic JSON + ELK layout output into a flat render-list of positioned primitives (rects, lines, labels, pins).
   - `canvas_renderer.mjs` — draws the render-list to a `<canvas>` 2D context.
   - `interactions.mjs` — D3 zoom/pan behavior, R-tree hit testing, click/tap dispatch.
   - `spatial_index.mjs` — R-tree wrapper (`rbush`) for point-in-rect queries.
3. Create `schematic_symbols.mjs` — symbol shape library. Each symbol type (`component`, `focus`, `io`, `memory`, `op`) has a `draw(ctx, x, y, w, h, state)` function and a bounding-box specification.
4. Wire the new renderer into `graph_runtime_service.mjs` behind a feature flag (`state.components.graphRenderer: 'cytoscape' | 'd3'`). Default remains `cytoscape`.
5. **Green:** New integration test passes. Manual verification that the canvas renderer shows the same schematic as Cytoscape for the Apple II fixture.
6. Port all interaction handlers (single-tap, double-tap drill-down, signal highlight, background click) from Cytoscape callbacks to D3/R-tree dispatch.
7. Port `updateGraphActivity()` — live signal value class toggling becomes direct color mutation on the render-list + canvas redraw.
8. **Green:** Existing explorer interaction tests adapted for D3 renderer pass.

**Exit Criteria:**
- Canvas 2D renderer displays the Apple II schematic with correct layout (ELK positions).
- All navigation (drill-down, up, root) works.
- Signal highlighting and live value updates work.
- Feature flag switches cleanly between old and new renderer.

---

### Phase 2: WebGL Render Pipeline

**Objective:** Replace Canvas 2D drawing with GPU-accelerated WebGL rendering via `regl`, keeping the same data model and interaction layer.

**Steps:**

1. **Red:** Write performance benchmark test that measures render time for a 500-symbol schematic. Assert < 8ms per frame. Fails with Canvas 2D for large schematics.
2. Add `regl` dependency (CDN or bundled).
3. Create `webgl_renderer.mjs`:
   - **Symbol pass:** Instanced quad rendering. Each symbol is a textured quad with per-instance attributes (position, size, color, border, type ID). A small texture atlas holds symbol shapes (rounded-rect, double-border for memory, etc.).
   - **Wire pass:** GL_LINES or instanced thick-line rendering for orthogonal wire segments. Per-segment attributes: start/end positions, width, color, dash pattern (for bidirectional wires).
   - **Pin pass:** Instanced small markers at pin positions with direction indicators.
   - **Label pass:** SDF text atlas. Pre-rasterize the font into a signed-distance-field texture. Render labels as textured quads with SDF shader for crisp text at any zoom.
4. Implement viewport matrix from D3 zoom transform → WebGL uniform (projection × view matrix). This makes pan/zoom purely a uniform update — zero geometry recomputation.
5. Wire `webgl_renderer.mjs` into the renderer pipeline. Canvas 2D becomes the fallback when `gl = canvas.getContext('webgl2')` returns null.
6. **Green:** Performance benchmark passes. 500-symbol schematic renders at < 8ms/frame.
7. Verify visual parity with Canvas 2D renderer using screenshot comparison on the Apple II fixture.

**Exit Criteria:**
- WebGL renderer active by default when WebGL 2.0 is available.
- Automatic fallback to Canvas 2D otherwise.
- Pan/zoom is GPU-driven (uniform update only, no re-layout).
- 500+ symbols render at 60fps during continuous pan/zoom.

---

### Phase 3: Signal Animation + Visual Polish

**Objective:** Bring live signal visualization to full fidelity with smooth animations, and add domain-specific RTL styling that was impossible with Cytoscape.

**Steps:**

1. **Red:** Write test asserting that toggled signals produce a visible pulse animation (color interpolation over N frames). Fails because animation not implemented.
2. Implement per-wire animation:
   - `time` uniform incremented each frame.
   - Toggled wires get a "pulse" effect: a bright wavefront travels along the wire path from driver to load over ~200ms.
   - Active wires glow (additive blend of highlight color).
   - Selected wires render thicker with distinct color.
3. Implement symbol-type-specific shapes:
   - **Mux:** Trapezoidal shape with select input on top.
   - **Register/DFF:** Rectangle with clock triangle marker.
   - **Memory:** Double-bordered rectangle with address/data port grouping.
   - **ALU/Op:** Distinctive shape or icon glyph per operation type.
   - **I/O pads:** Arrow-shaped directional indicators.
4. Implement bus rendering:
   - Multi-bit wires rendered with double-line or hatched-line style.
   - Bus ripper junctions at fan-out points.
   - Bit-width labels at bus endpoints.
5. Port both color themes (Shenzhen, Original) to the new renderer's color uniform system.
6. **Green:** Animation test passes. Visual review confirms improved schematic fidelity.
7. Add smooth transitions for drill-down navigation (animated zoom into child component, fade-out of parent context).

**Exit Criteria:**
- Live signal toggling produces visible animation.
- Symbol shapes convey component type at a glance.
- Bus wires are visually distinct from single-bit wires.
- Both themes work.
- Drill-down transitions are smooth.

---

### Phase 4: Cleanup + Cutover

**Objective:** Remove Cytoscape dependency, clean up feature flag, and finalize.

**Steps:**

1. **Red:** Verify all existing explorer tests pass with the D3 renderer as default.
2. Remove the `cytoscape` feature flag — D3/WebGL is the only renderer.
3. Remove Cytoscape.js CDN `<script>` tag from `index.html`.
4. Remove old files:
   - `controllers/graph/layout_elk.mjs` → refactored into `renderers/elk_layout_adapter.mjs` (already done in Phase 1).
   - `controllers/graph/theme.mjs` → theme data migrated to new renderer config.
   - `controllers/graph/interactions.mjs` → replaced by new `interactions.mjs`.
   - `lib/schematic_element_builder.mjs` → replaced by `schematic_data_model.mjs`.
5. Update `docs/web_simulator.md` to document the new renderer architecture.
6. **Green:** Full test suite passes. No references to Cytoscape remain.

**Exit Criteria:**
- Cytoscape.js fully removed from the project.
- No dead code from old renderer.
- Documentation updated.
- All tests green.

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
| SDF text rendering complexity | Blurry or missing labels | Start with Canvas 2D text overlay (DOM or offscreen canvas); migrate to SDF in Phase 3 only if needed |
| `regl` bundle size or API limitations | Larger payload or missing features | `regl` is ~45KB min+gzip; alternative: raw WebGL 2.0 calls (more code but zero dependency) |
| R-tree hit testing accuracy for rotated/complex shapes | Missed clicks on symbols | Use axis-aligned bounding boxes (sufficient for Manhattan-routed schematics); refine with per-shape point-in-polygon for special shapes |
| ELK layout positions don't map cleanly to WebGL coordinates | Misaligned rendering | ELK outputs pixel coordinates; apply same coordinate system to GL viewport with a simple 2D orthographic projection |
| Large schematics overwhelm even GPU | Frame drops on very large designs | Implement level-of-detail: collapse distant components to single rectangles; hide pin/net labels below zoom threshold |
| Browser compatibility (WebGL 2.0) | Safari/older browsers fail | Canvas 2D fallback is a full renderer, not a degraded mode; test on Safari WebKit nightly |

---

## New Dependencies

| Dependency | Version | Size (min+gzip) | Purpose |
|------------|---------|------------------|---------|
| `d3-selection` | 3.x | ~6KB | Data binding to render list |
| `d3-zoom` | 3.x | ~8KB | Pan/zoom behavior with inertia |
| `d3-scale` | 4.x | ~6KB | Color scales for themes/values |
| `d3-interpolate` | 3.x | ~5KB | Smooth animation interpolation |
| `regl` | 2.x | ~45KB | WebGL 2.0 abstraction for instanced rendering |
| `rbush` | 3.x | ~6KB | R-tree spatial index for hit testing |
| **Total** | | **~76KB** | vs Cytoscape ~200KB removed |

Net bundle size change: **~124KB reduction**.

---

## File Structure (New)

```
web/app/components/explorer/
├── renderers/
│   ├── schematic_data_model.mjs      # Schematic JSON → render primitives
│   ├── canvas_renderer.mjs           # Canvas 2D draw implementation
│   ├── webgl_renderer.mjs            # WebGL instanced draw passes
│   ├── webgl_shaders.mjs             # GLSL vertex/fragment shaders
│   ├── interactions.mjs              # D3 zoom + R-tree hit dispatch
│   ├── spatial_index.mjs             # rbush wrapper
│   ├── symbols.mjs                   # Symbol shape definitions
│   ├── themes.mjs                    # Color palettes + style config
│   ├── elk_layout_adapter.mjs        # ELK integration (extracted from existing)
│   ├── text_atlas.mjs                # SDF font atlas generator
│   └── animation.mjs                 # Wire pulse + transition animations
├── controllers/
│   ├── graph/  (removed in Phase 4)
│   ...
```

---

## Implementation Checklist

- [ ] **Phase 1: D3 Data Layer + Canvas 2D**
  - [ ] Integration test for schematic rendering to canvas
  - [ ] `schematic_data_model.mjs` — data transform pipeline
  - [ ] `canvas_renderer.mjs` — Canvas 2D drawing
  - [ ] `interactions.mjs` — D3 zoom/pan + R-tree hit testing
  - [ ] `spatial_index.mjs` — rbush spatial index
  - [ ] `symbols.mjs` — symbol shape library
  - [ ] Feature flag wiring in `graph_runtime_service.mjs`
  - [ ] Port interaction handlers (tap, double-tap, signal select)
  - [ ] Port live signal value updates
  - [ ] Interaction tests adapted for D3 renderer
- [ ] **Phase 2: WebGL Render Pipeline**
  - [ ] Performance benchmark test
  - [ ] Add `regl` dependency
  - [ ] `webgl_renderer.mjs` — instanced symbol/wire/pin/label passes
  - [ ] `webgl_shaders.mjs` — GLSL shaders
  - [ ] Viewport matrix from D3 zoom → GL uniform
  - [ ] WebGL ↔ Canvas 2D automatic fallback
  - [ ] Visual parity verification
- [ ] **Phase 3: Signal Animation + Visual Polish**
  - [ ] Wire pulse animation for toggled signals
  - [ ] Domain-specific symbol shapes (mux, register, memory, ALU, I/O)
  - [ ] Bus rendering (double-line, width labels)
  - [ ] Theme port (Shenzhen + Original)
  - [ ] Drill-down transition animation
- [ ] **Phase 4: Cleanup + Cutover**
  - [ ] Remove Cytoscape feature flag
  - [ ] Remove Cytoscape CDN script
  - [ ] Remove old graph controller files
  - [ ] Update `docs/web_simulator.md`
  - [ ] Final test suite pass
