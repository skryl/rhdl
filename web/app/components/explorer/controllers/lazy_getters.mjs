import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../source/lib/bundle_normalizers.mjs';
import { COMPONENT_SIGNAL_PREVIEW_LIMIT } from '../config/constants.mjs';
import { createComponentExplorerController } from './controller.mjs';
import { createComponentSourceController } from '../../source/controllers/controller.mjs';

function requireFn(name, fn) {
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
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createComponentLazyGetters requires dom/state/runtime');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('currentComponentSourceText', currentComponentSourceText);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('destroyComponentGraph', destroyComponentGraph);

  let componentExplorerController = null;
  let componentSourceController = null;

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
