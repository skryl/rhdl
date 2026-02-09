import test from 'node:test';
import assert from 'node:assert/strict';
import { createWatchDomainController } from '../../../../app/components/watch/controllers/domain.mjs';

test('createWatchDomainController exposes watch and breakpoint actions', () => {
  const fn = () => {};
  const domain = createWatchDomainController({
    refreshWatchTable: fn,
    addWatchSignal: fn,
    removeWatchSignal: fn,
    addBreakpointSignal: fn,
    clearAllBreakpoints: fn,
    removeBreakpointSignal: fn,
    renderBreakpointList: fn
  });

  assert.equal(domain.refreshTable, fn);
  assert.equal(domain.addSignal, fn);
   assert.equal(domain.addBreakpoint, fn);
   assert.equal(domain.clearBreakpoints, fn);
   assert.equal(domain.removeBreakpoint, fn);
  assert.equal(domain.renderBreakpoints, fn);
});
