import test from 'node:test';
import assert from 'node:assert/strict';

import { createRunnerBundleLoader } from '../../app/controllers/runner_bundle_controller.mjs';

function makeResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return body;
    }
  };
}

test('loadRunnerIrBundle returns manual bundle when preset is generic/manual', async () => {
  const dom = { irJson: { value: '{"foo":1}' } };
  const logs = [];
  const loader = createRunnerBundleLoader({
    dom,
    parseIrMeta: () => ({ parsed: true }),
    resetComponentExplorerState: () => {},
    log: (msg) => logs.push(msg),
    fetchImpl: async () => makeResponse('')
  });

  const bundle = await loader.loadRunnerIrBundle({ usesManualIr: true }, { logLoad: true });
  assert.equal(bundle.simJson, '{"foo":1}');
  assert.equal(bundle.explorerJson, '{"foo":1}');
  assert.equal(bundle.explorerMeta, null);
  assert.equal(bundle.sourceBundle, null);
  assert.equal(bundle.schematicBundle, null);
  assert.deepEqual(logs, []);
});

test('loadRunnerIrBundle loads sim/explorer/source/schematic bundles', async () => {
  const dom = { irJson: { value: '' } };
  const logs = [];
  let resets = 0;
  let parseCalls = 0;
  const fetchMap = {
    '/sim.json': makeResponse('{"ports":[{"name":"clk","width":1}]}'),
    '/hier.json': makeResponse('{"ports":[{"name":"hier_clk","width":1}]}'),
    '/sources.json': makeResponse('{"components":[{"component_class":"Top","module_name":"top_mod"}]}'),
    '/schematic.json': makeResponse('{"components":[{"path":"top"}]}')
  };
  const loader = createRunnerBundleLoader({
    dom,
    parseIrMeta: (json) => {
      parseCalls += 1;
      return { parsedFrom: json };
    },
    resetComponentExplorerState: () => {
      resets += 1;
    },
    log: (msg) => logs.push(msg),
    fetchImpl: async (path) => fetchMap[path] || makeResponse('', 404)
  });

  const bundle = await loader.loadRunnerIrBundle({
    usesManualIr: false,
    label: 'CPU',
    simIrPath: '/sim.json',
    explorerIrPath: '/hier.json',
    sourceBundlePath: '/sources.json',
    schematicPath: '/schematic.json'
  }, { logLoad: true });

  assert.equal(dom.irJson.value.includes('"clk"'), true);
  assert.equal(resets, 1);
  assert.equal(parseCalls, 1);
  assert.equal(bundle.simJson.includes('"clk"'), true);
  assert.equal(bundle.explorerJson.includes('"hier_clk"'), true);
  assert.equal(bundle.explorerMeta.parsedFrom.includes('"hier_clk"'), true);
  assert.equal(bundle.sourceBundle.byClass.get('Top').module_name, 'top_mod');
  assert.equal(bundle.schematicBundle.byPath.get('top').path, 'top');
  assert.ok(logs.includes('Loaded CPU IR bundle'));
});
