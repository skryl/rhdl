import test from 'node:test';
import assert from 'node:assert/strict';

import { createRunnerActionsController } from '../../../../app/components/runner/controllers/actions_controller';

type RunnerDom = {
  backendSelect: { value: string };
  irJson: { value: string };
  sampleSelect: {
    value: string;
    selectedOptions: Array<{ textContent: string }>;
  };
  runnerSelect: { value: string };
  loadRunnerBtn?: { disabled: boolean };
  apple2TextScreen?: { textContent: string };
  apple2HiresCanvas?: { hidden: boolean };
  runnerStatus?: { textContent: string };
};

type Call = [string, ...unknown[]];

function makeResponse(body: string, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return body;
    }
  };
}

function createHarness(overrides: Record<string, unknown> = {}) {
  const calls: Call[] = [];
  const dom: RunnerDom = {
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
    getRunnerPreset: (id: string) => ({ id, label: 'Generic', usesManualIr: true, preferredTab: 'vcdTab' }),
    setBackendState: (backend: string) => calls.push(['setBackendState', backend]),
    ensureBackendInstance: async (backend: string) => {
      calls.push(['ensureBackendInstance', backend]);
    },
    setRunnerPresetState: (id: string) => calls.push(['setRunnerPresetState', id]),
    updateIrSourceVisibility: () => calls.push(['updateIrSourceVisibility']),
    loadRunnerIrBundle: async () => ({ simJson: '{}', explorerJson: '{}', explorerMeta: null, sourceBundle: null, schematicBundle: null }),
    initializeSimulator: async (options: Record<string, unknown>) => calls.push(['initializeSimulator', options]),
    applyRunnerDefaults: async (preset: { id: string }) => calls.push(['applyRunnerDefaults', preset.id]),
    clearComponentSourceOverride: () => calls.push(['clearComponentSourceOverride']),
    resetComponentExplorerState: () => calls.push(['resetComponentExplorerState']),
    log: (msg: unknown) => calls.push(['log', msg]),
    isComponentTabActive: () => false,
    refreshComponentExplorer: () => calls.push(['refreshComponentExplorer']),
    clearComponentSourceBundle: () => calls.push(['clearComponentSourceBundle']),
    clearComponentSchematicBundle: () => calls.push(['clearComponentSchematicBundle']),
    setComponentSourceBundle: (value: unknown) => calls.push(['setComponentSourceBundle', value]),
    setComponentSchematicBundle: (value: unknown) => calls.push(['setComponentSchematicBundle', value]),
    setActiveTab: (tab: string) => calls.push(['setActiveTab', tab]),
    refreshStatus: () => calls.push(['refreshStatus']),
    fetchImpl: async () => makeResponse('{"ports":[]}'),
    ...overrides
  });
  return { controller, dom, calls };
}

test('loadSample loads text and resets component explorer', async () => {
  const { controller, dom, calls } = createHarness({
    isComponentTabActive: () => true,
    fetchImpl: async (path: string) => {
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
    requestFrame: (cb: () => void) => cb(),
    setTimeoutImpl: (cb: () => void) => cb()
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
    calls.some((call) => {
      const [key, value] = call;
      const sourceBundle = value as { source?: number } | null | undefined;
      return key === 'setComponentSourceBundle' && sourceBundle?.source === 1;
    }),
    true
  );
  assert.equal(
    calls.some((call) => {
      const [key, value] = call;
      const schematicBundle = value as { schematic?: number } | null | undefined;
      return key === 'setComponentSchematicBundle' && schematicBundle?.schematic === 1;
    }),
    true
  );
});

test('loadRunnerPreset with loading UI yields to browser and restores loading placeholders', async () => {
  const { controller, dom, calls } = createHarness({
    requestFrame: (cb: () => void) => {
      calls.push(['requestFrame']);
      cb();
    },
    setTimeoutImpl: (cb: () => void) => {
      calls.push(['setTimeout']);
      cb();
    },
    initializeSimulator: async (options: { yieldToUi?: boolean; deferComponentExplorerRebuild?: boolean }) => {
      calls.push([
        'initializeSimulator',
        options,
        dom.apple2TextScreen?.textContent ?? '',
        dom.loadRunnerBtn?.disabled ?? false
      ]);
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
    calls.some((call) => {
      const [key, options, text, disabled] = call;
      const initOptions = options as { yieldToUi?: boolean; deferComponentExplorerRebuild?: boolean } | undefined;
      return (
        key === 'initializeSimulator'
        && initOptions?.yieldToUi === true
        && initOptions?.deferComponentExplorerRebuild === true
        && text === 'Loading...'
        && disabled === true
      );
    }),
    true
  );
  assert.equal(dom.loadRunnerBtn.disabled, false);
  assert.equal(dom.apple2TextScreen.textContent, 'Initial display text');
  assert.equal(dom.apple2HiresCanvas.hidden, false);
  assert.equal(dom.runnerStatus.textContent, 'Runner not initialized');
});
