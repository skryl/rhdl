import type {
  GraphViewport,
  RenderList,
  ThemePalette
} from '../lib/types';

const DEFAULT_SCHEMATIC_RENDER_WORKER_PATH = './assets/pkg/schematic_render_worker.js';

interface SchematicRenderWorkerClient {
  render: (renderList: RenderList, viewport: GraphViewport, palette: ThemePalette) => void;
  setCanvasSize: (pixelWidth: number, pixelHeight: number) => void;
  destroy: () => void;
}

interface CreateSchematicRenderWorkerClientOptions {
  canvas: HTMLCanvasElement | null | undefined;
  workerScriptUrl?: string;
  documentRef?: Document;
  globalRef?: typeof globalThis;
  onBackend?: (backend: string) => void;
}

function resolveScriptUrl(scriptUrl: unknown, { documentRef, globalRef }: unknown = {}) {
  const base = documentRef?.baseURI
    || globalRef?.location?.href
    || 'http://localhost/';
  try {
    return new URL(String(scriptUrl || DEFAULT_SCHEMATIC_RENDER_WORKER_PATH), base).href;
  } catch (_err: unknown) {
    return String(scriptUrl || DEFAULT_SCHEMATIC_RENDER_WORKER_PATH);
  }
}

function toPositiveInt(value: unknown, fallback = 1): number {
  const numeric = Number(value);
  if (Number.isFinite(numeric) && numeric > 0) {
    return Math.max(1, Math.round(numeric));
  }
  return Math.max(1, Math.round(fallback || 1));
}

export function createSchematicRenderWorkerClient({
  canvas,
  workerScriptUrl = DEFAULT_SCHEMATIC_RENDER_WORKER_PATH,
  documentRef = globalThis.document,
  globalRef = globalThis,
  onBackend
}: CreateSchematicRenderWorkerClientOptions): SchematicRenderWorkerClient | null {
  const WorkerCtor = globalRef?.Worker;
  if (!canvas || typeof WorkerCtor !== 'function') {
    return null;
  }
  if (typeof canvas.transferControlToOffscreen !== 'function') {
    return null;
  }

  let worker: Worker | null = null;
  let disposed = false;

  const absoluteWorkerScriptUrl = resolveScriptUrl(workerScriptUrl, { documentRef, globalRef });

  try {
    const offscreen = canvas.transferControlToOffscreen();
    worker = new WorkerCtor(absoluteWorkerScriptUrl, { type: 'module' });

    worker.onmessage = (event: MessageEvent) => {
      if (disposed) {
        return;
      }
      const message = event?.data;
      if (!message || typeof message !== 'object') {
        return;
      }
      if (message.type === 'ready' && typeof onBackend === 'function') {
        onBackend(String(message.backend || ''));
      }
    };

    worker.postMessage({
      type: 'init',
      canvas: offscreen,
      width: toPositiveInt(canvas.width, 800),
      height: toPositiveInt(canvas.height, 600)
    }, [offscreen as unknown as Transferable]);
  } catch (_err: unknown) {
    try {
      worker?.terminate();
    } catch (_innerErr: unknown) {
      // Best-effort teardown.
    }
    return null;
  }

  function postMessage(message: unknown): void {
    if (disposed || !worker) {
      return;
    }
    try {
      worker.postMessage(message);
    } catch (_err: unknown) {
      // Ignore worker post failures.
    }
  }

  return {
    render(renderList: RenderList, viewport: GraphViewport, palette: ThemePalette): void {
      postMessage({
        type: 'render',
        renderList,
        viewport,
        palette
      });
    },
    setCanvasSize(pixelWidth: number, pixelHeight: number): void {
      postMessage({
        type: 'resize',
        width: toPositiveInt(pixelWidth, 1),
        height: toPositiveInt(pixelHeight, 1)
      });
    },
    destroy(): void {
      if (disposed) {
        return;
      }
      disposed = true;
      postMessage({ type: 'dispose' });
      try {
        if (worker) {
          worker.onmessage = null;
          worker.onerror = null;
          worker.onmessageerror = null;
          worker.terminate();
        }
      } catch (_err: unknown) {
        // Ignore termination failures.
      }
      worker = null;
    }
  };
}
