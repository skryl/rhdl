// D3-style interaction layer for the RTL schematic renderer.
// Handles click dispatch via spatial index, double-tap detection for drill-down.

const DOUBLE_TAP_MS = 320;
const ZOOM_SENSITIVITY = 0.0015;
const MIN_ZOOM_SCALE = 0.05;
const MAX_ZOOM_SCALE = 8;
const PAN_DRAG_THRESHOLD = 3;

interface GraphViewport {
  x: number;
  y: number;
  scale: number;
}

interface HitElement {
  type?: string;
  componentId?: string;
  signalName?: string;
  liveName?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

interface InteractionState {
  components: {
    selectedNodeId: string | null;
    graphLastTap: { nodeId: string; timeMs: number } | null;
    graphFocusId: string | null;
    graphShowChildren: boolean;
    graphHighlightedSignal: { signalName: string | null; liveName: string | null } | null;
  };
}

interface InteractionModel {
  nodes: Map<string, unknown>;
}

interface SpatialIndexLike {
  queryPoint: (x: number, y: number) => HitElement | null;
}

interface CanvasLike {
  width: number;
  height: number;
  getBoundingClientRect: () => { left: number; top: number; width: number; height: number };
}

interface ListenerTargetLike {
  addEventListener?: (type: string, listener: unknown, options?: unknown) => void;
  removeEventListener?: (type: string, listener: unknown, options?: unknown) => void;
}

interface PanState {
  startX: number;
  startY: number;
  baseX: number;
  baseY: number;
  dragged: boolean;
}

interface BindD3InteractionOptions {
  canvas: CanvasLike;
  state: InteractionState;
  model: InteractionModel;
  spatialIndex: SpatialIndexLike;
  renderComponentTree: () => void;
  renderComponentViews: () => void;
  requestRender?: () => void;
  now?: () => number;
  doubleTapMs?: number;
  viewport?: GraphViewport | null;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function asListenerTarget(value: unknown): ListenerTargetLike | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  return value as ListenerTargetLike;
}

function addListener(target: unknown, type: string, listener: EventListener, options?: unknown): void {
  const listenerTarget = asListenerTarget(target);
  if (!listenerTarget || typeof listenerTarget.addEventListener !== 'function') {
    return;
  }
  listenerTarget.addEventListener(type, listener, options);
}

function removeListener(target: unknown, type: string, listener: EventListener, options?: unknown): void {
  const listenerTarget = asListenerTarget(target);
  if (!listenerTarget || typeof listenerTarget.removeEventListener !== 'function') {
    return;
  }
  listenerTarget.removeEventListener(type, listener, options);
}

function isComponent(element: HitElement): boolean {
  return element.type === 'component' || element.type === 'focus';
}

function isNetOrPin(element: HitElement): boolean {
  const hasSignal = String(element.signalName || '').trim() !== '' || String(element.liveName || '').trim() !== '';
  return hasSignal && !isComponent(element);
}

function readSignalHighlight(element: HitElement): { signalName: string | null; liveName: string | null } | null {
  const signalName = String(element.signalName || '').trim();
  const liveName = String(element.liveName || '').trim();
  if (!signalName && !liveName) {
    return null;
  }
  return {
    signalName: signalName || null,
    liveName: liveName || null
  };
}

function readMousePosition(event: MouseEvent | WheelEvent): { x: number; y: number } {
  return {
    x: Number(event.clientX) || 0,
    y: Number(event.clientY) || 0
  };
}

export function bindD3Interactions({
  canvas,
  state,
  model,
  spatialIndex,
  renderComponentTree,
  renderComponentViews,
  requestRender,
  now = () => Date.now(),
  doubleTapMs = DOUBLE_TAP_MS,
  viewport = null
}: BindD3InteractionOptions): { destroy: () => void } {
  if (!canvas || !state || !model) {
    throw new Error('bindD3Interactions requires canvas, state, and model');
  }

  const renderNow = typeof requestRender === 'function' ? requestRender : () => {};
  const globalTarget: unknown =
    typeof window !== 'undefined' && typeof window.addEventListener === 'function'
      ? window
      : canvas;

  let panState: PanState | null = null;
  let suppressClick = false;
  const wheelListenerOptions: AddEventListenerOptions = { passive: false };

  function toScreenCoords(clientX: number, clientY: number): { x: number; y: number } {
    const rect = canvas.getBoundingClientRect();
    return {
      x: clientX - rect.left,
      y: clientY - rect.top
    };
  }

  function toWorldCoords(clientX: number, clientY: number): { x: number; y: number } {
    const screen = toScreenCoords(clientX, clientY);
    if (viewport) {
      const scale = Number.isFinite(viewport.scale) && viewport.scale > 0 ? viewport.scale : 1;
      const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
      const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
      return {
        x: (screen.x - tx) / scale,
        y: (screen.y - ty) / scale
      };
    }
    return screen;
  }

  function handleClick(event: MouseEvent): void {
    if (suppressClick) {
      suppressClick = false;
      return;
    }

    const point = readMousePosition(event);
    const world = toWorldCoords(point.x, point.y);
    const hit = spatialIndex.queryPoint(world.x, world.y);

    if (!hit) {
      state.components.graphHighlightedSignal = null;
      renderComponentViews();
      return;
    }

    if (isNetOrPin(hit)) {
      state.components.graphHighlightedSignal = readSignalHighlight(hit);
      renderComponentViews();
      return;
    }

    if (isComponent(hit)) {
      const componentId = String(hit.componentId || '').trim();
      if (!componentId || !model.nodes.has(componentId)) {
        return;
      }

      const nowMs = now();
      const lastTap = state.components.graphLastTap;
      const isDoubleTap = !!(
        lastTap
        && lastTap.nodeId === componentId
        && (nowMs - lastTap.timeMs) < doubleTapMs
      );

      state.components.graphLastTap = { nodeId: componentId, timeMs: nowMs };

      if (state.components.selectedNodeId !== componentId) {
        state.components.selectedNodeId = componentId;
        renderComponentTree();
      }

      if (isDoubleTap) {
        state.components.graphFocusId = componentId;
        state.components.graphShowChildren = true;
        state.components.graphHighlightedSignal = null;
      }

      renderComponentViews();
    }
  }

  function handleWheel(event: WheelEvent): void {
    if (!viewport) {
      return;
    }

    const prevScale = Number.isFinite(viewport.scale) ? viewport.scale : 1;
    const zoom = Math.exp(-(Number(event.deltaY) || 0) * ZOOM_SENSITIVITY);
    const nextScale = clamp(prevScale * zoom, MIN_ZOOM_SCALE, MAX_ZOOM_SCALE);
    if (!Number.isFinite(nextScale) || Math.abs(nextScale - prevScale) < 1e-6) {
      return;
    }

    const point = readMousePosition(event);
    const screen = toScreenCoords(point.x, point.y);
    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    const worldX = (screen.x - tx) / prevScale;
    const worldY = (screen.y - ty) / prevScale;

    viewport.scale = nextScale;
    viewport.x = screen.x - worldX * nextScale;
    viewport.y = screen.y - worldY * nextScale;

    event.preventDefault();
    renderNow();
  }

  function handleMouseDown(event: MouseEvent): void {
    if (!viewport || event.button !== 0) {
      return;
    }

    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    panState = {
      startX: Number(event.clientX) || 0,
      startY: Number(event.clientY) || 0,
      baseX: tx,
      baseY: ty,
      dragged: false
    };
  }

  function handleMouseMove(event: MouseEvent): void {
    if (!panState || !viewport) {
      return;
    }

    const dx = (Number(event.clientX) || 0) - panState.startX;
    const dy = (Number(event.clientY) || 0) - panState.startY;
    if (!panState.dragged) {
      const moved = Math.abs(dx) >= PAN_DRAG_THRESHOLD || Math.abs(dy) >= PAN_DRAG_THRESHOLD;
      if (!moved) {
        return;
      }
      panState.dragged = true;
    }

    viewport.x = panState.baseX + dx;
    viewport.y = panState.baseY + dy;
    event.preventDefault();
    renderNow();
  }

  function handleMouseUp(event: MouseEvent): void {
    if (!panState) {
      return;
    }
    if (panState.dragged) {
      suppressClick = true;
      event.preventDefault();
    }
    panState = null;
  }

  addListener(canvas, 'click', handleClick as EventListener);
  addListener(canvas, 'wheel', handleWheel as EventListener, wheelListenerOptions);
  addListener(canvas, 'mousedown', handleMouseDown as EventListener);
  addListener(globalTarget, 'mousemove', handleMouseMove as EventListener);
  addListener(globalTarget, 'mouseup', handleMouseUp as EventListener);

  function destroy(): void {
    removeListener(canvas, 'click', handleClick as EventListener);
    removeListener(canvas, 'wheel', handleWheel as EventListener, wheelListenerOptions);
    removeListener(canvas, 'mousedown', handleMouseDown as EventListener);
    removeListener(globalTarget, 'mousemove', handleMouseMove as EventListener);
    removeListener(globalTarget, 'mouseup', handleMouseUp as EventListener);
  }

  return { destroy };
}
