import test from 'node:test';
import assert from 'node:assert/strict';
import { createComponentDomainController } from '../../../../app/components/explorer/controllers/domain.mjs';

test('createComponentDomainController groups component explorer actions', () => {
  const fn = () => {};
  const domain = createComponentDomainController({
    isComponentTabActive: fn,
    refreshActiveComponentTab: fn,
    refreshComponentExplorer: fn,
    renderComponentTree: fn,
    setComponentGraphFocus: fn,
    currentComponentGraphFocusNode: fn,
    renderComponentViews: fn,
    zoomComponentGraphIn: fn,
    zoomComponentGraphOut: fn,
    resetComponentGraphViewport: fn,
    clearComponentSourceOverride: fn,
    resetComponentExplorerState: fn
  });

  assert.equal(domain.isTabActive, fn);
  assert.equal(domain.setGraphFocus, fn);
  assert.equal(domain.zoomGraphIn, fn);
  assert.equal(domain.zoomGraphOut, fn);
  assert.equal(domain.resetGraphView, fn);
  assert.equal(domain.resetExplorerState, fn);
});
