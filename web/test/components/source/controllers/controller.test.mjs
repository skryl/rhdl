import test from 'node:test';
import assert from 'node:assert/strict';
import { createComponentSourceController } from '../../../../app/components/source/controllers/controller.mjs';

test('source controller delegates to source runtime service', () => {
  const state = {
    components: {
      sourceBundle: null,
      sourceBundleByClass: new Map(),
      sourceBundleByModule: new Map(),
      schematicBundle: null,
      schematicBundleByPath: new Map(),
      overrideSource: '',
      overrideMeta: null
    }
  };
  const controller = createComponentSourceController({
    dom: { irJson: { value: '' } },
    state,
    currentRunnerPreset: () => ({ id: 'generic', usesManualIr: true }),
    normalizeComponentSourceBundle: (bundle) => bundle,
    normalizeComponentSchematicBundle: (bundle) => bundle,
    destroyComponentGraph: () => {}
  });

  assert.equal(typeof controller.updateIrSourceVisibility, 'function');
  assert.equal(typeof controller.resetComponentExplorerState, 'function');
});
