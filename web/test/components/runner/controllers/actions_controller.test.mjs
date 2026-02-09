import test from 'node:test';
import assert from 'node:assert/strict';

import { createRunnerActionsController } from '../../../../app/components/runner/controllers/actions_controller.mjs';

function makeResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return body;
    }
  };
}

function createHarness(overrides = {}) {
  const calls = [];
  const dom = {
    irJson: { value: '' },
    sampleSelect: {
      value: '/sample.json',
      selectedOptions: [{ textContent: 'CPU Sample' }]
    },
    runnerSelect: { value: 'generic' }
  };
  const controller = createRunnerActionsController({
    dom,
    getRunnerPreset: (id) => ({ id, label: 'Generic', usesManualIr: true, preferredTab: 'vcdTab' }),
    setRunnerPresetState: (id) => calls.push(['setRunnerPresetState', id]),
    updateIrSourceVisibility: () => calls.push(['updateIrSourceVisibility']),
    loadRunnerIrBundle: async () => ({ simJson: '{}', explorerJson: '{}', explorerMeta: null, sourceBundle: null, schematicBundle: null }),
    initializeSimulator: async (options) => calls.push(['initializeSimulator', options]),
    clearComponentSourceOverride: () => calls.push(['clearComponentSourceOverride']),
    resetComponentExplorerState: () => calls.push(['resetComponentExplorerState']),
    log: (msg) => calls.push(['log', msg]),
    isComponentTabActive: () => false,
    refreshComponentExplorer: () => calls.push(['refreshComponentExplorer']),
    clearComponentSourceBundle: () => calls.push(['clearComponentSourceBundle']),
    clearComponentSchematicBundle: () => calls.push(['clearComponentSchematicBundle']),
    setComponentSourceBundle: (value) => calls.push(['setComponentSourceBundle', value]),
    setComponentSchematicBundle: (value) => calls.push(['setComponentSchematicBundle', value]),
    setActiveTab: (tab) => calls.push(['setActiveTab', tab]),
    refreshStatus: () => calls.push(['refreshStatus']),
    fetchImpl: async () => makeResponse('{"ports":[]}'),
    ...overrides
  });
  return { controller, dom, calls };
}

test('loadSample loads text and resets component explorer', async () => {
  const { controller, dom, calls } = createHarness({
    isComponentTabActive: () => true,
    fetchImpl: async (path) => {
      if (path === '/sample.json') {
        return makeResponse('{"ports":[{"name":"clk","width":1}]}');
      }
      return makeResponse('', 404);
    }
  });

  await controller.loadSample();
  assert.equal(dom.irJson.value.includes('"clk"'), true);
  assert.equal(calls.some(([k]) => k === 'clearComponentSourceOverride'), true);
  assert.equal(calls.some(([k]) => k === 'resetComponentExplorerState'), true);
  assert.equal(calls.some(([k]) => k === 'refreshComponentExplorer'), true);
});

test('loadRunnerPreset runs manual preset initialization path', async () => {
  const { controller, dom, calls } = createHarness();
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';
  await controller.loadRunnerPreset();

  assert.equal(calls.some(([k]) => k === 'setRunnerPresetState'), true);
  assert.equal(calls.some(([k]) => k === 'updateIrSourceVisibility'), true);
  assert.equal(calls.some(([k]) => k === 'initializeSimulator'), true);
  assert.equal(calls.some(([k]) => k === 'setActiveTab'), true);
  assert.equal(calls.some(([k]) => k === 'refreshStatus'), true);
});

test('preloadStartPreset loads non-manual bundle into component stores', async () => {
  const { controller, calls } = createHarness({
    loadRunnerIrBundle: async () => ({
      simJson: '{}',
      explorerJson: '{}',
      explorerMeta: null,
      sourceBundle: { source: 1 },
      schematicBundle: { schematic: 1 }
    })
  });

  await controller.preloadStartPreset({ usesManualIr: false });
  assert.equal(
    calls.some(([k, value]) => k === 'setComponentSourceBundle' && value && value.source === 1),
    true
  );
  assert.equal(
    calls.some(([k, value]) => k === 'setComponentSchematicBundle' && value && value.schematic === 1),
    true
  );
});
