import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fetchTextAsset,
  fetchJsonAsset,
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../app/lib/bundle_utils.mjs';

test('normalizeComponentSourceBundle builds class/module indexes', () => {
  const raw = {
    top_component_class: 'Top',
    components: [
      { component_class: 'Top', module_name: 'TopMod' },
      { component_class: 'Child', module_name: 'ChildMod' }
    ]
  };
  const normalized = normalizeComponentSourceBundle(raw);
  assert.equal(normalized.top.component_class, 'Top');
  assert.equal(normalized.byClass.get('Child').module_name, 'ChildMod');
  assert.equal(normalized.byModule.get('topmod').component_class, 'Top');
});

test('normalizeComponentSchematicBundle indexes entries by path', () => {
  const raw = {
    components: [
      { path: 'top' },
      { path: 'top.cpu' }
    ]
  };
  const normalized = normalizeComponentSchematicBundle(raw);
  assert.equal(normalized.byPath.get('top.cpu').path, 'top.cpu');
});

test('fetchTextAsset reads text and reports HTTP errors', async () => {
  const text = await fetchTextAsset('/ok', 'fixture', async () => ({
    ok: true,
    status: 200,
    async text() {
      return 'hello';
    }
  }));
  assert.equal(text, 'hello');

  await assert.rejects(
    () => fetchTextAsset('/missing', 'fixture', async () => ({ ok: false, status: 404 })),
    /fixture load failed \(404\)/
  );
});

test('fetchJsonAsset parses JSON and reports parse errors', async () => {
  const parsed = await fetchJsonAsset('/ok', 'bundle', async () => ({
    ok: true,
    status: 200,
    async text() {
      return '{"a":1}';
    }
  }));
  assert.equal(parsed.a, 1);

  await assert.rejects(
    () => fetchJsonAsset('/bad', 'bundle', async () => ({
      ok: true,
      status: 200,
      async text() {
        return '{';
      }
    })),
    /bundle parse failed/
  );
});
