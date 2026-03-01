import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../source/lib/bundle_normalizers';
import { COMPONENT_SIGNAL_PREVIEW_LIMIT } from '../config/constants';
import { createComponentExplorerController } from './controller';
import { createComponentSourceController } from '../../source/controllers/controller';
import type { RunnerPresetModel } from '../../../types/models';
import type { RuntimeContext } from '../../../types/runtime';
import type { AppState } from '../../../types/state';
import type { MergedDomRefs } from '../../../types/dom';
import type { ExplorerDomRefs, ExplorerRuntimeLike, ExplorerStateLike } from '../lib/types';

interface ComponentLazyGetterOptions {
  dom: MergedDomRefs;
  state: AppState;
  runtime: RuntimeContext;
  scheduleReduxUxSync: (reason: string) => void;
  currentComponentSourceText: () => string;
  currentRunnerPreset: () => RunnerPresetModel;
  destroyComponentGraph: () => void;
}

function requireFn(name: string, fn: unknown): void {
  if (typeof fn !== 'function') {
    throw new Error(`createComponentLazyGetters requires function: ${name}`);
  }
}

export function createComponentLazyGetters({
  dom,
  state,
  runtime,
  scheduleReduxUxSync,
  currentComponentSourceText,
  currentRunnerPreset,
  destroyComponentGraph
}: ComponentLazyGetterOptions) {
  if (!dom || !state || !runtime) {
    throw new Error('createComponentLazyGetters requires dom/state/runtime');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('currentComponentSourceText', currentComponentSourceText);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('destroyComponentGraph', destroyComponentGraph);

  let componentExplorerController: ReturnType<typeof createComponentExplorerController> | null = null;
  let componentSourceController: ReturnType<typeof createComponentSourceController> | null = null;

  function getComponentExplorerController(): ReturnType<typeof createComponentExplorerController> {
    if (!componentExplorerController) {
      componentExplorerController = createComponentExplorerController({
        dom: dom as unknown as ExplorerDomRefs,
        state: state as unknown as ExplorerStateLike,
        runtime: runtime as unknown as ExplorerRuntimeLike,
        scheduleReduxUxSync,
        currentComponentSourceText,
        componentSignalPreviewLimit: COMPONENT_SIGNAL_PREVIEW_LIMIT
      });
    }
    return componentExplorerController;
  }

  function getComponentSourceController(): ReturnType<typeof createComponentSourceController> {
    if (!componentSourceController) {
      componentSourceController = createComponentSourceController({
        dom,
        state,
        currentRunnerPreset,
        normalizeComponentSourceBundle,
        normalizeComponentSchematicBundle,
        destroyComponentGraph
      });
    }
    return componentSourceController;
  }

  return {
    getComponentExplorerController,
    getComponentSourceController
  };
}
