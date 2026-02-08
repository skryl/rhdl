import test from 'node:test';
import assert from 'node:assert/strict';
import { createSimDomainController } from '../../app/controllers/registry_sim_domain_controller.mjs';

test('createSimDomainController exposes simulator controls', () => {
  const fn = () => {};
  const domain = createSimDomainController({
    setupP5: fn,
    refreshStatus: fn,
    initializeSimulator: fn,
    initializeTrace: fn,
    stepSimulation: fn,
    runFrame: fn,
    drainTrace: fn,
    maskForWidth: fn
  });

  assert.equal(domain.setupP5, fn);
  assert.equal(domain.step, fn);
  assert.equal(domain.maskForWidth, fn);
});
