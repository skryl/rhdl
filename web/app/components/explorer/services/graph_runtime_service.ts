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
import type {
  ComponentModel,
  ComponentNode,
  ExplorerDomRefs,
  ExplorerGraphLike,
  ExplorerStateLike,
  GraphViewport,
  RenderList,
  SpatialIndex,
  ThemePalette
} from '../lib/types';

const MIN_GRAPH_SCALE = 0.05;
const MAX_GRAPH_SCALE = 8;
const BUTTON_ZOOM_FACTOR = 1.2;
const DEFAULT_GRAPH_VIEWPORT: GraphViewport = Object.freeze({ x: 0, y: 0, scale: 1 });
const SCHEMATIC_LOADING_TEXT = 'Loading schematic...';

interface GraphRuntimeServiceOptions {
  dom: ExplorerDomRefs;
  state: ExplorerStateLike;
  currentComponentGraphFocusNode: () => ComponentNode | null;
  renderComponentTree: () => void;
  renderComponentViews: () => void;
  createSchematicElements: (
    model: ComponentModel,
    focusNode: ComponentNode,
    showChildren: boolean
  ) => unknown[];
  signalLiveValueByName: (liveName: string) => unknown;
  isTraceEnabled?: () => boolean;
}

interface InFlightGraphBuild {
  token: number;
  key: string;
}

interface GraphRenderer {
  render: (renderList: RenderList, viewport: GraphViewport, palette: ThemePalette) => void;
  destroy: () => void;
}

interface GraphInteractions {
  destroy: () => void;
}

interface LocalGraphHandle extends ExplorerGraphLike {
  type: 'd3';
  renderer: GraphRenderer;
  interactions: GraphInteractions;
  canvas: HTMLCanvasElement;
  legendCanvas: HTMLCanvasElement | null;
  viewport: GraphViewport;
  spatialIndex: SpatialIndex;
  renderList: RenderList;
  renderLegendOverlay: (palette: ThemePalette) => void;
  destroy: () => void;
}

interface BuildGraphOptions {
  model: ComponentModel;
  focusNode: ComponentNode;
  showChildren: boolean;
  graphKey: string;
  rerender: () => void;
  token: number;
}

interface RenderPanelOptions {
  node: ComponentNode | null;
  model: ComponentModel | null;
  rerender: () => void;
}

interface DescribePanelOptions {
  selectedNode: ComponentNode | null;
  focusNode: ComponentNode | null;
}

interface PanelDescription {
  title: string;
  meta: string;
  focusPath: string;
  topDisabled: boolean;
  upDisabled: boolean;
}

type ElkInstance = {
  layout: (graph: ReturnType<typeof buildElkGraph>) => Promise<unknown>;
};

type ElkConstructor = new () => ElkInstance;

function requireFn(name: string, fn: unknown): void {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphRuntimeService requires function: ${name}`);
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function toCanvasPixelSize(value: unknown, fallback: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return Math.max(1, Math.floor(Number(fallback) || 1));
  }
  return Math.max(1, Math.floor(parsed));
}

function hasRenderableGraph(graph: ExplorerGraphLike | null): graph is LocalGraphHandle {
  return !!graph
    && !!graph.renderer
    && typeof graph.renderer.render === 'function';
}

function describeError(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
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
}: GraphRuntimeServiceOptions) {
  if (!dom || !state) {
    throw new Error('createExplorerGraphRuntimeService requires dom/state');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('createSchematicElements', createSchematicElements);
  requireFn('signalLiveValueByName', signalLiveValueByName);

  let renderListRef: RenderList | null = null;
  let viewport: GraphViewport = { ...DEFAULT_GRAPH_VIEWPORT };
  let graphBuildVersion = 0;
  let graphBuildInFlight: InFlightGraphBuild | null = null;

  function syncGraphCanvasSize(graph: LocalGraphHandle): boolean {
    if (!graph?.canvas) {
      return false;
    }

    const fallbackWidth = Number((graph.canvas as unknown as { width?: unknown }).width) || 800;
    const fallbackHeight = Number((graph.canvas as unknown as { height?: unknown }).height) || 600;
    const targetWidth = toCanvasPixelSize(dom.componentVisual?.clientWidth, fallbackWidth);
    const targetHeight = toCanvasPixelSize(dom.componentVisual?.clientHeight, fallbackHeight);
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

  function yieldToBrowser(): Promise<void> {
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

  function isBuildCurrent(token: number, key: string): boolean {
    return (
      graphBuildVersion === token
      && !!graphBuildInFlight
      && graphBuildInFlight.token === token
      && graphBuildInFlight.key === key
    );
  }

  function clearBuildInFlightIfCurrent(token: number, key: string): void {
    if (isBuildCurrent(token, key)) {
      graphBuildInFlight = null;
    }
  }

  function renderGraphWithViewport(graph: LocalGraphHandle): boolean {
    if (!hasRenderableGraph(graph)) {
      return false;
    }
    syncGraphCanvasSize(graph);
    const renderList = renderListRef || graph.renderList;
    const palette = getThemePalette(state.theme);
    graph.renderer.render(renderList, viewport, palette);
    if (typeof graph.renderLegendOverlay === 'function') {
      graph.renderLegendOverlay(palette);
    }
    return true;
  }

  function zoomComponentGraphByFactor(factor = 1): boolean {
    const graph = state.components.graph;
    if (!graph || !('canvas' in graph) || !graph.canvas || !viewport) {
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
    const centerX = (Number(rect?.width) > 0 ? Number(rect?.width) : Number(graph.canvas.width) || 800) * 0.5;
    const centerY = (Number(rect?.height) > 0 ? Number(rect?.height) : Number(graph.canvas.height) || 600) * 0.5;
    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    const worldX = (centerX - tx) / prevScale;
    const worldY = (centerY - ty) / prevScale;

    viewport.scale = nextScale;
    viewport.x = centerX - worldX * nextScale;
    viewport.y = centerY - worldY * nextScale;
    return hasRenderableGraph(graph) ? renderGraphWithViewport(graph) : false;
  }

  function zoomInComponentGraph(): boolean {
    return zoomComponentGraphByFactor(BUTTON_ZOOM_FACTOR);
  }

  function zoomOutComponentGraph(): boolean {
    return zoomComponentGraphByFactor(1 / BUTTON_ZOOM_FACTOR);
  }

  function resetComponentGraphViewport(): boolean {
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
    return hasRenderableGraph(graph) ? renderGraphWithViewport(graph) : false;
  }

  function destroyComponentGraph(): void {
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
  }: BuildGraphOptions): Promise<void> {
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

      let legendCanvas: HTMLCanvasElement | null = null;
      let legendCtx: CanvasRenderingContext2D | null = null;
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

      const renderLegendOverlay = (palette: ThemePalette) => {
        if (!legendCtx || !legendCanvas) {
          return;
        }
        legendCtx.clearRect(0, 0, legendCanvas.width, legendCanvas.height);
        drawLegend(legendCtx, legendCanvas.width, legendCanvas.height, palette);
      };

      await yieldToBrowser();
      if (!isBuildCurrent(token, graphKey)) {
        clearBuildInFlightIfCurrent(token, graphKey);
        return;
      }

      let spatialIndex = buildSpatialIndex(renderList);
      let graphHandle: LocalGraphHandle | null = null;

      const interactions = bindD3Interactions({
        canvas,
        state,
        model,
        spatialIndex,
        viewport,
        renderComponentTree,
        renderComponentViews,
        requestRender: () => {
          if (graphHandle) {
            renderGraphWithViewport(graphHandle);
          }
        }
      });

      graphHandle = {
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
        state.components.graphLiveValues = new Map<string, string>();
      }
      renderGraphWithViewport(graphHandle);

      if (isBuildCurrent(token, graphKey)) {
        graphBuildInFlight = null;
      }

      if (state.activeTab === 'componentGraphTab') {
        rerender();
      }

      await yieldToBrowser();
      if (state.components.graph !== graphHandle || state.components.graphKey !== graphKey) {
        return;
      }

      const elkAvailable = typeof ELK === 'function';
      if (!elkAvailable) {
        state.components.graphLayoutEngine = 'missing';
        return;
      }

      const elkGraph = buildElkGraph(renderList);
      const ElkCtor = ELK as unknown as ElkConstructor;
      const elk = new ElkCtor();
      state.components.graphLayoutEngine = 'elk';

      void elk.layout(elkGraph)
        .then((result) => {
          if (state.components.graph !== graphHandle || state.components.graphKey !== graphKey) {
            return;
          }
          const resultRecord = result && typeof result === 'object' ? result : null;
          const children = resultRecord && Array.isArray((resultRecord as { children?: unknown }).children)
            ? (resultRecord as { children: unknown[] }).children
            : null;
          if (!children) {
            return;
          }

          applyElkResult(renderList, result as Parameters<typeof applyElkResult>[1]);
          spatialIndex = buildSpatialIndex(renderList);
          graphHandle.spatialIndex = spatialIndex;
          renderGraphWithViewport(graphHandle);
        })
        .catch(() => {
          if (state.components.graph === graphHandle && state.components.graphKey === graphKey) {
            state.components.graphLayoutEngine = 'error';
          }
        });
    } catch {
      if (isBuildCurrent(token, graphKey)) {
        graphBuildInFlight = null;
        state.components.graphLayoutEngine = 'error';
        if (dom.componentVisual) {
          dom.componentVisual.textContent = 'Unable to render component schematic.';
        }
      }
    }
  }

  function ensureComponentGraph(model: ComponentModel, rerender: () => void): LocalGraphHandle | null {
    if (!dom.componentVisual) {
      return null;
    }

    const focusNode = currentComponentGraphFocusNode();
    if (!focusNode) {
      return null;
    }

    const showChildren = !!state.components.graphShowChildren;
    const schematicKey = state.components.schematicBundle
      ? String(state.components.schematicBundle.generated_at || state.components.schematicBundle.runner || 'schem')
      : 'none';
    const elkAvailable = typeof ELK === 'function';
    state.components.graphElkAvailable = elkAvailable;

    const graphKey =
      `${state.components.sourceKey}:d3:${state.theme}:`
      + `${schematicKey}:${focusNode.id}:${showChildren ? 1 : 0}:`
      + `${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;

    if (!elkAvailable) {
      state.components.graphLayoutEngine = 'missing';
      return null;
    }

    if (hasRenderableGraph(state.components.graph) && state.components.graphKey === graphKey) {
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

  function renderComponentVisual({ node, model, rerender }: RenderPanelOptions): { ok: boolean; reason?: string } {
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
      if (typeof globalThis.requestAnimationFrame === 'function') {
        globalThis.requestAnimationFrame(() => {
          if (state.activeTab === 'componentGraphTab') {
            rerender();
          }
        });
      }
      return { ok: false, reason: 'small-container' };
    }

    const renderList = renderListRef || graph.renderList;

    const traceEnabled = typeof isTraceEnabled === 'function' ? isTraceEnabled() === true : true;
    const nextValues = updateRenderActivity({
      renderList,
      signalLiveValueByName: traceEnabled ? signalLiveValueByName : (() => null),
      toBigInt,
      highlightedSignal: state.components.graphHighlightedSignal,
      previousValues: traceEnabled ? (state.components.graphLiveValues || new Map<string, string>()) : new Map<string, string>()
    });
    state.components.graphLiveValues = nextValues;

    renderGraphWithViewport(graph);

    return { ok: true };
  }

  function describeComponentGraphPanel({ selectedNode, focusNode }: DescribePanelOptions): PanelDescription {
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
        `selected=${nodeDisplayPath(selectedNode)} | focus=${nodeDisplayPath(focusNode)}`
        + ` | ${mode} | layout=${layout} | elk=${elk} | dbl-click dive, drag pan, wheel zoom, reset view`,
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
