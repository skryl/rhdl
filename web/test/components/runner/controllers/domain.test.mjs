import test from 'node:test';
import assert from 'node:assert/strict';
import { createRunnerDomainController } from '../../../../app/components/runner/controllers/domain.mjs';

test('createRunnerDomainController exposes runner lifecycle helpers', () => {
  const fn = () => {};
  const domain = createRunnerDomainController({
    getRunnerPreset: fn,
    currentRunnerPreset: fn,
    loadRunnerPreset: fn,
    loadSample: fn,
    loadRunnerIrBundle: fn,
    updateIrSourceVisibility: fn,
    getRunnerActionsController: fn,
    ensureBackendInstance: fn
  });

  assert.equal(domain.getPreset, fn);
  assert.equal(domain.loadPreset, fn);
  assert.equal(domain.getActionsController, fn);
});
