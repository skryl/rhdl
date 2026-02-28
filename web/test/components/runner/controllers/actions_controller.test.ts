import test from 'node:test';
import assert from 'node:assert/strict';

import { createRunnerActionsController } from '../../../../app/components/runner/controllers/actions_controller';

function makeResponse(body: any, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return body;
    }
  };
}

function createHarness(overrides: any = {}) {
  const calls: any[] = [];
  const dom: any = {
    backendSelect: { value: 'interpreter' },
    irJson: { value: '' },
    sampleSelect: {
      value: '/sample.json',
      selectedOptions: [{ textContent: 'CPU Sample' }]
    },
    runnerSelect: { value: 'generic' }
  };
  const controller = createRunnerActionsController({
    dom,
    getRunnerPreset: (id: any) => ({ id, label: 'Generic', usesManualIr: true, preferredTab: 'vcdTab' }),
    setBackendState: (backend: any) => calls.push(['setBackendState', backend]),
    ensureBackendInstance: async (backend: any) => {
      calls.push(['ensureBackendInstance', backend]);
    },
    setRunnerPresetState: (id: any) => calls.push(['setRunnerPresetState', id]),
    updateIrSourceVisibility: () => calls.push(['updateIrSourceVisibility']),
    loadRunnerIrBundle: async () => ({ simJson: '{}', explorerJson: '{}', explorerMeta: null, sourceBundle: null, schematicBundle: null }),
    initializeSimulator: async (options: any) => calls.push(['initializeSimulator', options]),
    applyRunnerDefaults: async (preset: any) => calls.push(['applyRunnerDefaults', preset.id]),
    clearComponentSourceOverride: () => calls.push(['clearComponentSourceOverride']),
    resetComponentExplorerState: () => calls.push(['resetComponentExplorerState']),
    log: (msg: any) => calls.push(['log', msg]),
    isComponentTabActive: () => false,
    refreshComponentExplorer: () => calls.push(['refreshComponentExplorer']),
    clearComponentSourceBundle: () => calls.push(['clearComponentSourceBundle']),
    clearComponentSchematicBundle: () => calls.push(['clearComponentSchematicBundle']),
    setComponentSourceBundle: (value: any) => calls.push(['setComponentSourceBundle', value]),
    setComponentSchematicBundle: (value: any) => calls.push(['setComponentSchematicBundle', value]),
    setActiveTab: (tab: any) => calls.push(['setActiveTab', tab]),
    refreshStatus: () => calls.push(['refreshStatus']),
    fetchImpl: async () => makeResponse('{"ports":[]}'),
    ...overrides
  });
  return { controller, dom, calls };
}

test('loadSample loads text and resets component explorer', async () => {
  const { controller, dom, calls } = createHarness({
    isComponentTabActive: () => true,
    fetchImpl: async (path: any) => {
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
  assert.equal(calls.some(([k]) => k === 'applyRunnerDefaults'), true);
  assert.equal(calls.some(([k]) => k === 'setActiveTab'), true);
  assert.equal(calls.some(([k]) => k === 'refreshStatus'), true);
});

test('loadRunnerPreset applies preset preferred backend before simulator initialization', async () => {
  const { controller, dom, calls } = createHarness({
    getRunnerPreset: () => ({
      id: 'apple2',
      label: 'Apple II System Runner',
      usesManualIr: true,
      preferredTab: 'ioTab',
      preferredBackend: 'compiler'
    })
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.loadRunnerPreset();

  const setBackendIndex = calls.findIndex(([k, value]) => k === 'setBackendState' && value === 'compiler');
  const ensureBackendIndex = calls.findIndex(([k, value]) => k === 'ensureBackendInstance' && value === 'compiler');
  const initializeIndex = calls.findIndex(([k]) => k === 'initializeSimulator');

  assert.notEqual(setBackendIndex, -1);
  assert.notEqual(ensureBackendIndex, -1);
  assert.notEqual(initializeIndex, -1);
  assert.equal(setBackendIndex < initializeIndex, true);
  assert.equal(ensureBackendIndex < initializeIndex, true);
  assert.equal(dom.backendSelect.value, 'compiler');
});

test('loadRunnerPreset schedules component explorer warmup after runner load', async () => {
  const { controller, dom, calls } = createHarness({
    requestFrame: (cb: any) => cb(),
    setTimeoutImpl: (cb: any) => cb()
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.loadRunnerPreset();

  const refreshStatusIndex = calls.findIndex(([k]) => k === 'refreshStatus');
  const refreshExplorerIndex = calls.findIndex(([k]) => k === 'refreshComponentExplorer');
  assert.notEqual(refreshStatusIndex, -1);
  assert.notEqual(refreshExplorerIndex, -1);
  assert.equal(refreshStatusIndex < refreshExplorerIndex, true);
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

test('loadRunnerPreset with loading UI yields to browser and restores loading placeholders', async () => {
  const { controller, dom, calls } = createHarness({
    requestFrame: (cb: any) => {
      calls.push(['requestFrame']);
      cb();
    },
    setTimeoutImpl: (cb: any) => {
      calls.push(['setTimeout']);
      cb();
    },
    initializeSimulator: async (options: any) => {
      calls.push(['initializeSimulator', options, dom.apple2TextScreen.textContent, dom.loadRunnerBtn.disabled]);
    },
    refreshStatus: () => {
      calls.push(['refreshStatus']);
    }
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';
  dom.loadRunnerBtn = { disabled: false };
  dom.apple2TextScreen = { textContent: 'Initial display text' };
  dom.apple2HiresCanvas = { hidden: false };
  dom.runnerStatus = { textContent: 'Runner not initialized' };

  await controller.loadRunnerPreset({ showLoadingUi: true });

  const requestFrameIndex = calls.findIndex(([k]) => k === 'requestFrame');
  const initializeIndex = calls.findIndex(([k]) => k === 'initializeSimulator');
  assert.notEqual(requestFrameIndex, -1);
  assert.notEqual(initializeIndex, -1);
  assert.equal(requestFrameIndex < initializeIndex, true);
  assert.equal(
    calls.some(([k, options, text, disabled]) => (
      k === 'initializeSimulator'
      && options?.yieldToUi === true
      && options?.deferComponentExplorerRebuild === true
      && text === 'Loading...'
      && disabled === true
    )),
    true
  );
  assert.equal(dom.loadRunnerBtn.disabled, false);
  assert.equal(dom.apple2TextScreen.textContent, 'Initial display text');
  assert.equal(dom.apple2HiresCanvas.hidden, false);
  assert.equal(dom.runnerStatus.textContent, 'Runner not initialized');
});
