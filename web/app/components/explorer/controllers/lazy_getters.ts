import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../source/lib/bundle_normalizers';
import { COMPONENT_SIGNAL_PREVIEW_LIMIT } from '../config/constants';
import { createComponentExplorerController } from './controller';
import { createComponentSourceController } from '../../source/controllers/controller';

function requireFn(name: any, fn: any) {
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
}: any = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createComponentLazyGetters requires dom/state/runtime');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('currentComponentSourceText', currentComponentSourceText);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('destroyComponentGraph', destroyComponentGraph);

  let componentExplorerController: any = null;
  let componentSourceController: any = null;

  function getComponentExplorerController() {
    if (!componentExplorerController) {
      componentExplorerController = createComponentExplorerController({
        dom,
        state,
        runtime,
        scheduleReduxUxSync,
        currentComponentSourceText,
        componentSignalPreviewLimit: COMPONENT_SIGNAL_PREVIEW_LIMIT
      });
    }
    return componentExplorerController;
  }

  function getComponentSourceController() {
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
