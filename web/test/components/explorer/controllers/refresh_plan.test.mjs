import test from 'node:test';
import assert from 'node:assert/strict';

import { resolveComponentRefreshPlan } from '../../../../app/components/explorer/controllers/refresh_plan.mjs';

test('component refresh plan for component tab renders tree + inspector only', () => {
  const plan = resolveComponentRefreshPlan('componentTab');
  assert.deepEqual(plan, {
    renderTree: true,
    renderInspector: true,
    renderGraph: false
  });
});

test('component refresh plan for schematic tab renders graph only', () => {
  const plan = resolveComponentRefreshPlan('componentGraphTab');
  assert.deepEqual(plan, {
    renderTree: false,
    renderInspector: false,
    renderGraph: true
  });
});

test('component refresh plan for non-component tabs renders nothing', () => {
  const plan = resolveComponentRefreshPlan('ioTab');
  assert.deepEqual(plan, {
    renderTree: false,
    renderInspector: false,
    renderGraph: false
  });
});
