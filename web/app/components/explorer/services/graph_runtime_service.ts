import { toBigInt } from '../../../core/lib/numeric_utils';
import { nodeDisplayPath } from '../lib/model_utils';
import ELK from 'elkjs/lib/elk.bundled';

import { buildRenderList } from '../renderers/schematic_data_model';
import { createCanvasRenderer } from '../renderers/canvas_renderer';
import { createWebGLRenderer } from '../renderers/webgl_renderer';
import { buildSpatialIndex } from '../renderers/spatial_index';
import { bindD3Interactions } from '../renderers/interactions';
import { buildElkGraph, applyElkResult } from '../renderers/elk_layout_adapter';
import { updateRenderActivity } from '../renderers/render_activity';
import { getThemePalette, drawLegend } from '../renderers/themes';

const MIN_GRAPH_SCALE = 0.05;
const MAX_GRAPH_SCALE = 8;
const BUTTON_ZOOM_FACTOR = 1.2;
const DEFAULT_GRAPH_VIEWPORT = Object.freeze({ x: 0, y: 0, scale: 1 });
const SCHEMATIC_LOADING_TEXT = 'Loading schematic...';

function requireFn(name: any, fn: any) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphRuntimeService requires function: ${name}`);
  }
}

function clamp(value: any, min: any, max: any) {
  return Math.min(max, Math.max(min, value));
}

function toCanvasPixelSize(value: any, fallback: any) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return Math.max(1, Math.floor(Number(fallback) || 1));
  }
  return Math.max(1, Math.floor(parsed));
}

export function createExplorerGraphRuntimeService({
  dom,
  state,
  currentComponentGraphFocusNode,
  renderComponentTree,
  renderComponentViews,
  createSchematicElements,
  signalLiveValueByName,
  isTraceEnabled = () => true
}: any = {}) {
  if (!dom || !state) {
    throw new Error('createExplorerGraphRuntimeService requires dom/state');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('createSchematicElements', createSchematicElements);
  requireFn('signalLiveValueByName', signalLiveValueByName);

  // renderer state (kept outside components state to avoid serialization)
  let renderListRef: any = null;
  let viewport = { ...DEFAULT_GRAPH_VIEWPORT };
  let graphBuildVersion = 0;
  let graphBuildInFlight: any = null;

  function syncGraphCanvasSize(graph: any) {
    if (!graph?.canvas) {
      return false;
    }

    const targetWidth = toCanvasPixelSize(dom.componentVisual?.clientWidth, graph.canvas.width || 800);
    const targetHeight = toCanvasPixelSize(dom.componentVisual?.clientHeight, graph.canvas.height || 600);
    let resized = false;

    if (graph.canvas.width !== targetWidth || graph.canvas.height !== targetHeight) {
      graph.canvas.width = targetWidth;
      graph.canvas.height = targetHeight;
      resized = true;
    }

    if (graph.legendCanvas) {
      if (graph.legendCanvas.width !== targetWidth || graph.legendCanvas.height !== targetHeight) {
        graph.legendCanvas.width = targetWidth;
        graph.legendCanvas.height = targetHeight;
        resized = true;
      }
    }

    return resized;
  }

  function yieldToBrowser() {
    return new Promise<void>((resolve) => {
      const scheduleTimeout = () => {
        if (typeof globalThis.setTimeout === 'function') {
          globalThis.setTimeout(resolve, 0);
          return;
        }
        resolve();
      };
      if (typeof globalThis.requestAnimationFrame === 'function') {
        globalThis.requestAnimationFrame(() => {
          scheduleTimeout();
        });
        return;
      }
      scheduleTimeout();
    });
  }

  function isBuildCurrent(token: any, key: any) {
    return (
      graphBuildVersion === token
      && !!graphBuildInFlight
      && graphBuildInFlight.token === token
      && graphBuildInFlight.key === key
    );
  }

  function clearBuildInFlightIfCurrent(token: any, key: any) {
    if (isBuildCurrent(token, key)) {
      graphBuildInFlight = null;
    }
  }

  function renderGraphWithViewport(graph: any) {
    if (!graph || !graph.renderer || typeof graph.renderer.render !== 'function') {
      return false;
    }
    syncGraphCanvasSize(graph);
    const renderList = renderListRef || graph.renderList || [];
    const palette = getThemePalette(state.theme);
    graph.renderer.render(renderList, viewport, palette);
    if (typeof graph.renderLegendOverlay === 'function') {
      graph.renderLegendOverlay(palette);
    }
    return true;
  }

  function zoomComponentGraphByFactor(factor = 1) {
    const graph = state.components.graph;
    if (!graph || !graph.canvas || !viewport) {
      return false;
    }
    if (graph.viewport && graph.viewport !== viewport) {
      viewport = graph.viewport;
    }
    const prevScale = Number.isFinite(viewport.scale) ? viewport.scale : 1;
    const nextScale = clamp(prevScale * Number(factor || 1), MIN_GRAPH_SCALE, MAX_GRAPH_SCALE);
    if (!Number.isFinite(nextScale) || Math.abs(nextScale - prevScale) < 1e-6) {
      return false;
    }

    const rect = typeof graph.canvas.getBoundingClientRect === 'function'
      ? graph.canvas.getBoundingClientRect()
      : null;
    const centerX = (Number(rect?.width) > 0 ? Number(rect.width) : Number(graph.canvas.width) || 800) * 0.5;
    const centerY = (Number(rect?.height) > 0 ? Number(rect.height) : Number(graph.canvas.height) || 600) * 0.5;
    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    const worldX = (centerX - tx) / prevScale;
    const worldY = (centerY - ty) / prevScale;

    viewport.scale = nextScale as any;
    viewport.x = (centerX - (worldX * nextScale)) as any;
    viewport.y = (centerY - (worldY * nextScale)) as any;
    return renderGraphWithViewport(graph);
  }

  function zoomInComponentGraph() {
    return zoomComponentGraphByFactor(BUTTON_ZOOM_FACTOR);
  }

  function zoomOutComponentGraph() {
    return zoomComponentGraphByFactor(1 / BUTTON_ZOOM_FACTOR);
  }

  function resetComponentGraphViewport() {
    const graph = state.components.graph;
    if (!graph || !viewport) {
      return false;
    }
    if (graph.viewport && graph.viewport !== viewport) {
      viewport = graph.viewport;
    }
    viewport.x = DEFAULT_GRAPH_VIEWPORT.x;
    viewport.y = DEFAULT_GRAPH_VIEWPORT.y;
    viewport.scale = DEFAULT_GRAPH_VIEWPORT.scale;
    return renderGraphWithViewport(graph);
  }

  function destroyComponentGraph() {
    graphBuildVersion += 1;
    graphBuildInFlight = null;
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

  async function buildComponentGraphAsync({
    model,
    focusNode,
    showChildren,
    graphKey,
    rerender,
    token
  }: any) {
    try {
      await yieldToBrowser();
      if (!isBuildCurrent(token, graphKey)) {
        return;
      }

      const schematicElements = createSchematicElements(model, focusNode, showChildren);
      await yieldToBrowser();
      if (!isBuildCurrent(token, graphKey)) {
        return;
      }

      const renderList = buildRenderList(schematicElements);
      renderListRef = renderList;

      if (!dom.componentVisual || !isBuildCurrent(token, graphKey)) {
        clearBuildInFlightIfCurrent(token, graphKey);
        return;
      }
      dom.componentVisual.innerHTML = '';

      const canvas = document.createElement('canvas');
      canvas.width = toCanvasPixelSize(dom.componentVisual.clientWidth, 800);
      canvas.height = toCanvasPixelSize(dom.componentVisual.clientHeight, 600);
      canvas.style.width = '100%';
      canvas.style.height = '100%';
      dom.componentVisual.appendChild(canvas);

      const webglRenderer = createWebGLRenderer(canvas);
      const renderer = webglRenderer || createCanvasRenderer(canvas);
      if (!renderer) {
        clearBuildInFlightIfCurrent(token, graphKey);
        state.components.graphLayoutEngine = 'error';
        dom.componentVisual.textContent = 'Unable to render component schematic.';
        return;
      }
      state.components.graphRenderBackend = webglRenderer ? 'webgl' : 'canvas2d';

      let legendCanvas: any = null;
      let legendCtx: any = null;
      if (webglRenderer) {
        legendCanvas = document.createElement('canvas');
        legendCanvas.width = canvas.width;
        legendCanvas.height = canvas.height;
        legendCanvas.style.width = '100%';
        legendCanvas.style.height = '100%';
        legendCanvas.style.position = 'absolute';
        legendCanvas.style.top = '0';
        legendCanvas.style.left = '0';
        legendCanvas.style.pointerEvents = 'none';
        dom.componentVisual.style.position = 'relative';
        dom.componentVisual.appendChild(legendCanvas);
        legendCtx = legendCanvas.getContext('2d');
      }

      function renderLegendOverlay(pal: any) {
        if (!legendCtx) return;
        legendCtx.clearRect(0, 0, legendCanvas.width, legendCanvas.height);
        drawLegend(legendCtx, legendCanvas.width, legendCanvas.height, pal);
      }

      await yieldToBrowser();
      if (!isBuildCurrent(token, graphKey)) {
        clearBuildInFlightIfCurrent(token, graphKey);
        return;
      }
      const spatialIndex = buildSpatialIndex(renderList);

      const interactions = bindD3Interactions({
        canvas,
        state,
        model,
        spatialIndex,
        viewport,
        renderComponentTree,
        renderComponentViews,
        requestRender: () => {
          renderGraphWithViewport(graphHandle);
        }
      });

      const graphHandle = {
        type: 'd3',
        renderer,
        interactions,
        canvas,
        legendCanvas,
        viewport,
        spatialIndex,
        renderList,
        renderLegendOverlay,
        destroy() {
          renderer.destroy();
          interactions.destroy();
        }
      };

      if (!isBuildCurrent(token, graphKey)) {
        graphHandle.destroy();
        return;
      }

      state.components.graph = graphHandle;
      state.components.graphKey = graphKey;
      state.components.graphSelectedId = null;
      if (!state.components.graphLiveValues) {
        state.components.graphLiveValues = new Map();
      }
      renderGraphWithViewport(graphHandle);

      if (isBuildCurrent(token, graphKey)) {
        graphBuildInFlight = null;
      }

      if (typeof rerender === 'function' && state.activeTab === 'componentGraphTab') {
        rerender();
      }

      await yieldToBrowser();
      if (state.components.graph !== graphHandle || state.components.graphKey !== graphKey) {
        return;
      }

      const elkGraph = buildElkGraph(renderList);
      const elk = new ELK();
      state.components.graphLayoutEngine = 'elk';
      elk.layout(elkGraph as any).then((result) => {
        if (state.components.graph !== graphHandle || state.components.graphKey !== graphKey) {
          return;
        }
        if (result && Array.isArray(result.children)) {
          applyElkResult(renderList, result);
          const newIndex = buildSpatialIndex(renderList);
          if (graphHandle.interactions) {
            graphHandle.spatialIndex = newIndex;
          }
          renderGraphWithViewport(graphHandle);
        }
      }).catch((_err) => {
        if (state.components.graph === graphHandle && state.components.graphKey === graphKey) {
          state.components.graphLayoutEngine = 'error';
        }
      });
    } catch (_err: any) {
      if (isBuildCurrent(token, graphKey)) {
        graphBuildInFlight = null;
        state.components.graphLayoutEngine = 'error';
        if (dom.componentVisual) {
          dom.componentVisual.textContent = 'Unable to render component schematic.';
        }
      }
    }
  }

  function ensureComponentGraph(model: any, rerender: any) {
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
    const elkAvailable = typeof ELK === 'function';
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
    if (graphBuildInFlight && graphBuildInFlight.key === graphKey) {
      return null;
    }

    destroyComponentGraph();
    dom.componentVisual.innerHTML = '';
    dom.componentVisual.textContent = SCHEMATIC_LOADING_TEXT;
    state.components.graphLayoutEngine = 'loading';

    const token = graphBuildVersion + 1;
    graphBuildVersion = token;
    graphBuildInFlight = { token, key: graphKey };
    void buildComponentGraphAsync({
      model,
      focusNode,
      showChildren,
      graphKey,
      rerender,
      token
    });
    return null;
  }

  function renderComponentVisual({ node, model, rerender }: any) {
    if (!dom.componentVisual) {
      return { ok: false, reason: 'missing-container' };
    }
    if (!node || !model) {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Select a component to visualize.';
      return { ok: false, reason: 'missing-node' };
    }

    const graph = ensureComponentGraph(model, rerender);
    if (!graph) {
      if (state.components.graphLayoutEngine === 'loading') {
        if (!String(dom.componentVisual.textContent || '').trim()) {
          dom.componentVisual.textContent = SCHEMATIC_LOADING_TEXT;
        }
        return { ok: false, reason: 'graph-loading' };
      }
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
    const traceEnabled = (
      typeof isTraceEnabled === 'function'
      ? isTraceEnabled() === true
      : true
    );
    const nextValues = updateRenderActivity({
      renderList,
      signalLiveValueByName: traceEnabled ? signalLiveValueByName : (() => null),
      toBigInt,
      highlightedSignal: state.components.graphHighlightedSignal,
      previousValues: traceEnabled ? (state.components.graphLiveValues || new Map()) : new Map()
    });
    state.components.graphLiveValues = nextValues;

    // Re-render canvas
    renderGraphWithViewport(graph);

    return { ok: true };
  }

  function describeComponentGraphPanel({ selectedNode, focusNode }: any) {
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
        ` | ${mode} | layout=${layout} | elk=${elk} | dbl-click dive, drag pan, wheel zoom, reset view`,
      focusPath: `Focus: ${nodeDisplayPath(focusNode)}`,
      topDisabled: !model || focusNode.id === model.rootId,
      upDisabled: !focusNode.parentId
    };
  }

  return {
    destroyComponentGraph,
    zoomInComponentGraph,
    zoomOutComponentGraph,
    resetComponentGraphViewport,
    renderComponentVisual,
    describeComponentGraphPanel
  };
}
