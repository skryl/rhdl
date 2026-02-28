import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fetchTextAsset,
  fetchJsonAsset
} from '../../../app/core/lib/fetch_asset';

test('fetchTextAsset reads text and reports HTTP errors', async () => {
  const text = await fetchTextAsset('/ok', 'fixture', (async () => ({
    ok: true,
    status: 200,
    async text() {
      return 'hello';
    }
  })) as any);
  assert.equal(text, 'hello');

  await assert.rejects(
    () => fetchTextAsset('/missing', 'fixture', (async () => ({ ok: false, status: 404 })) as any),
    /fixture load failed \(404\)/
  );
});

test('fetchJsonAsset parses JSON and reports parse errors', async () => {
  const parsed = await fetchJsonAsset('/ok', 'bundle', (async () => ({
    ok: true,
    status: 200,
    async text() {
      return '{"a":1}';
    }
  })) as any);
  assert.equal(parsed.a, 1);

  await assert.rejects(
    () => fetchJsonAsset('/bad', 'bundle', (async () => ({
      ok: true,
      status: 200,
      async text() {
        return '{';
      }
    })) as any),
    /bundle parse failed/
  );
});
