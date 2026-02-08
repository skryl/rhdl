import test from 'node:test';
import assert from 'node:assert/strict';
import { createWatchDomainController } from '../../app/controllers/registry_watch_domain_controller.mjs';

test('createWatchDomainController exposes watch and breakpoint actions', () => {
  const fn = () => {};
  const domain = createWatchDomainController({
    refreshWatchTable: fn,
    addWatchSignal: fn,
    removeWatchSignal: fn,
    renderBreakpointList: fn
  });

  assert.equal(domain.refreshTable, fn);
  assert.equal(domain.addSignal, fn);
  assert.equal(domain.renderBreakpoints, fn);
});
