import { createCanvasRenderer } from '../renderers/canvas_renderer';
import { createWebGLRenderer } from '../renderers/webgl_renderer';
import type {
  GraphViewport,
  RenderList,
  ThemePalette
} from '../lib/types';

type RenderBackend = 'webgl' | 'canvas2d';

interface WorkerRenderer {
  render: (renderList: RenderList, viewport: GraphViewport, palette: ThemePalette) => void;
  destroy: () => void;
}

interface InitMessage {
  type: 'init';
  canvas?: OffscreenCanvas;
  width?: number;
  height?: number;
}

interface ResizeMessage {
  type: 'resize';
  width?: number;
  height?: number;
}

interface RenderMessage {
  type: 'render';
  renderList?: RenderList;
  viewport?: GraphViewport;
  palette?: ThemePalette;
}

interface DisposeMessage {
  type: 'dispose';
}

type WorkerMessage = InitMessage | ResizeMessage | RenderMessage | DisposeMessage;

function toPositiveInt(value: unknown, fallback = 1): number {
  const numeric = Number(value);
  if (Number.isFinite(numeric) && numeric > 0) {
    return Math.max(1, Math.round(numeric));
  }
  return Math.max(1, Math.round(fallback || 1));
}

let renderCanvas: OffscreenCanvas | null = null;
let renderer: WorkerRenderer | null = null;
let backend: RenderBackend | '' = '';

function destroyRenderer(): void {
  if (!renderer) {
    return;
  }
  try {
    renderer.destroy();
  } catch (_err: unknown) {
    // Best-effort cleanup.
  }
  renderer = null;
  backend = '';
}

function ensureRenderer(): void {
  if (!renderCanvas || renderer) {
    return;
  }

  const webgl = createWebGLRenderer(renderCanvas as unknown as HTMLCanvasElement);
  if (webgl) {
    renderer = webgl;
    backend = 'webgl';
  } else {
    const canvas2d = createCanvasRenderer(renderCanvas as unknown as HTMLCanvasElement);
    if (!canvas2d) {
      throw new Error('unable to initialize schematic renderer');
    }
    renderer = canvas2d;
    backend = 'canvas2d';
  }

  self.postMessage({ type: 'ready', backend });
}

function handleInit(message: InitMessage): void {
  destroyRenderer();
  if (!(message.canvas instanceof OffscreenCanvas)) {
    throw new Error('worker init missing OffscreenCanvas');
  }
  renderCanvas = message.canvas;
  renderCanvas.width = toPositiveInt(message.width, renderCanvas.width || 800);
  renderCanvas.height = toPositiveInt(message.height, renderCanvas.height || 600);
  ensureRenderer();
}

function handleResize(message: ResizeMessage): void {
  if (!renderCanvas) {
    return;
  }
  renderCanvas.width = toPositiveInt(message.width, renderCanvas.width || 1);
  renderCanvas.height = toPositiveInt(message.height, renderCanvas.height || 1);
}

function handleRender(message: RenderMessage): void {
  if (!renderCanvas) {
    return;
  }
  ensureRenderer();
  if (!renderer) {
    return;
  }

  const renderList = message.renderList;
  const viewport = message.viewport;
  const palette = message.palette;
  if (!renderList || !viewport || !palette) {
    return;
  }

  renderer.render(renderList, viewport, palette);
}

self.onmessage = (event: MessageEvent<WorkerMessage>) => {
  const message = event?.data;
  if (!message || typeof message !== 'object' || typeof message.type !== 'string') {
    return;
  }

  try {
    if (message.type === 'init') {
      handleInit(message);
      return;
    }
    if (message.type === 'resize') {
      handleResize(message);
      return;
    }
    if (message.type === 'render') {
      handleRender(message);
      return;
    }
    if (message.type === 'dispose') {
      destroyRenderer();
      renderCanvas = null;
    }
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err || 'unknown error');
    self.postMessage({ type: 'error', error: errorMessage });
  }
};
