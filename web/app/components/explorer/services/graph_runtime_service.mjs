import { toBigInt } from '../../../core/lib/numeric_utils.mjs';
import { nodeDisplayPath } from '../lib/model_utils.mjs';

import { buildRenderList } from '../renderers/schematic_data_model.mjs';
import { createCanvasRenderer } from '../renderers/canvas_renderer.mjs';
import { createWebGLRenderer } from '../renderers/webgl_renderer.mjs';
import { buildSpatialIndex } from '../renderers/spatial_index.mjs';
import { bindD3Interactions } from '../renderers/interactions.mjs';
import { buildElkGraph, applyElkResult } from '../renderers/elk_layout_adapter.mjs';
import { updateRenderActivity } from '../renderers/render_activity.mjs';
import { getThemePalette } from '../renderers/themes.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphRuntimeService requires function: ${name}`);
  }
}

export function createExplorerGraphRuntimeService({
  dom,
  state,
  currentComponentGraphFocusNode,
  renderComponentTree,
  renderComponentViews,
  createSchematicElements,
  signalLiveValueByName
} = {}) {
  if (!dom || !state) {
    throw new Error('createExplorerGraphRuntimeService requires dom/state');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('createSchematicElements', createSchematicElements);
  requireFn('signalLiveValueByName', signalLiveValueByName);

  // renderer state (kept outside components state to avoid serialization)
  let renderListRef = null;
  let viewport = { x: 0, y: 0, scale: 1 };

  function destroyComponentGraph() {
    if (state.components.graph && typeof state.components.graph.destroy === 'function') {
      state.components.graph.destroy();
    }
    state.components.graph = null;
    state.components.graphKey = '';
    state.components.graphSelectedId = null;
    state.components.graphLastTap = null;
    state.components.graphLayoutEngine = 'none';
    state.components.graphElkAvailable = false;
    renderListRef = null;
  }

  function ensureComponentGraph(model) {
    if (!dom.componentVisual || !model) {
      return null;
    }

    const focusNode = currentComponentGraphFocusNode();
    if (!focusNode) {
      return null;
    }
    const showChildren = !!state.components.graphShowChildren;
    const schematicKey = state.components.schematicBundle
      ? (state.components.schematicBundle.generated_at || state.components.schematicBundle.runner || 'schem')
      : 'none';
    const elkAvailable = typeof window.ELK === 'function';
    state.components.graphElkAvailable = elkAvailable;
    const graphKey =
      `${state.components.sourceKey}:d3:${state.theme}:` +
      `${schematicKey}:${focusNode.id}:${showChildren ? 1 : 0}:` +
      `${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;

    if (!elkAvailable) {
      state.components.graphLayoutEngine = 'missing';
      return null;
    }
    if (state.components.graph && state.components.graphKey === graphKey) {
      return state.components.graph;
    }

    destroyComponentGraph();
    dom.componentVisual.innerHTML = '';

    // Build render list from schematic elements
    const schematicElements = createSchematicElements(model, focusNode, showChildren);
    const renderList = buildRenderList(schematicElements);
    renderListRef = renderList;

    // Create canvas
    const canvas = document.createElement('canvas');
    canvas.width = dom.componentVisual.clientWidth || 800;
    canvas.height = dom.componentVisual.clientHeight || 600;
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    dom.componentVisual.appendChild(canvas);

    // Create renderer — try WebGL first, fall back to Canvas 2D
    const webglRenderer = createWebGLRenderer(canvas);
    const renderer = webglRenderer || createCanvasRenderer(canvas);
    state.components.graphRenderBackend = webglRenderer ? 'webgl' : 'canvas2d';

    // Run ELK layout
    const elkGraph = buildElkGraph(renderList);
    const elk = new window.ELK();
    state.components.graphLayoutEngine = 'elk';
    elk.layout(elkGraph).then((result) => {
      if (result && Array.isArray(result.children)) {
        applyElkResult(renderList, result);
        // Rebuild spatial index after layout
        const newIndex = buildSpatialIndex(renderList);
        if (graphHandle.interactions) {
          graphHandle.spatialIndex = newIndex;
        }
        // Render with new positions
        const palette = getThemePalette(state.theme);
        renderer.render(renderList, viewport, palette);
      }
    }).catch((_err) => {
      state.components.graphLayoutEngine = 'error';
    });

    // Build spatial index
    const spatialIndex = buildSpatialIndex(renderList);

    // Bind interactions
    const interactions = bindD3Interactions({
      canvas,
      state,
      model,
      spatialIndex,
      renderComponentTree,
      renderComponentViews,
      requestRender: () => {
        const palette = getThemePalette(state.theme);
        renderer.render(renderListRef || renderList, viewport, palette);
      }
    });

    // Initial render
    const palette = getThemePalette(state.theme);
    renderer.render(renderList, viewport, palette);

    const graphHandle = {
      type: 'd3',
      renderer,
      interactions,
      canvas,
      spatialIndex,
      renderList,
      destroy() {
        renderer.destroy();
        interactions.destroy();
      }
    };

    state.components.graph = graphHandle;
    state.components.graphKey = graphKey;
    state.components.graphSelectedId = null;
    if (!state.components.graphLiveValues) {
      state.components.graphLiveValues = new Map();
    }
    return graphHandle;
  }

  function renderComponentVisual({ node, model, rerender }) {
    if (!dom.componentVisual) {
      return { ok: false, reason: 'missing-container' };
    }
    if (!node || !model) {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Select a component to visualize.';
      return { ok: false, reason: 'missing-node' };
    }

    const graph = ensureComponentGraph(model);
    if (!graph) {
      if (state.components.graphLayoutEngine === 'missing') {
        dom.componentVisual.textContent = 'ELK layout engine unavailable.';
      } else {
        dom.componentVisual.textContent = 'Unable to render component schematic.';
      }
      return { ok: false, reason: 'graph-unavailable' };
    }

    if (dom.componentVisual.clientWidth < 20 || dom.componentVisual.clientHeight < 20) {
      requestAnimationFrame(() => {
        if (state.activeTab === 'componentGraphTab') {
          rerender();
        }
      });
      return { ok: false, reason: 'small-container' };
    }

    const renderList = renderListRef || graph.renderList;

    // Update live signal activity
    const nextValues = updateRenderActivity({
      renderList,
      signalLiveValueByName,
      toBigInt,
      highlightedSignal: state.components.graphHighlightedSignal,
      previousValues: state.components.graphLiveValues || new Map()
    });
    state.components.graphLiveValues = nextValues;

    // Re-render canvas
    const palette = getThemePalette(state.theme);
    graph.renderer.render(renderList, viewport, palette);

    return { ok: true };
  }

  function describeComponentGraphPanel({ selectedNode, focusNode }) {
    if (!selectedNode || !focusNode) {
      return {
        title: 'Component Schematic',
        meta: state.components.parseError || 'Load IR to inspect component connectivity.',
        focusPath: 'Focus: top',
        topDisabled: true,
        upDisabled: true
      };
    }

    const mode = state.components.graphShowChildren ? 'schematic view' : 'symbol view';
    const layout = state.components.graphLayoutEngine || 'none';
    const elk = state.components.graphElkAvailable ? 'ready' : 'missing';
    const model = state.components.model;
    return {
      title: nodeDisplayPath(focusNode),
      meta:
        `selected=${nodeDisplayPath(selectedNode)} | focus=${nodeDisplayPath(focusNode)}` +
        ` | ${mode} | layout=${layout} | elk=${elk} | dbl-click component to dive`,
      focusPath: `Focus: ${nodeDisplayPath(focusNode)}`,
      topDisabled: !model || focusNode.id === model.rootId,
      upDisabled: !focusNode.parentId
    };
  }

  return {
    destroyComponentGraph,
    renderComponentVisual,
    describeComponentGraphPanel
  };
}
