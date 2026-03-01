import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fetchTextAsset,
  fetchJsonAsset
} from '../../../app/core/lib/fetch_asset';

interface FetchResponseStub {
  ok: boolean;
  status: number;
  text: () => Promise<string>;
}

function createFetchStub(response: FetchResponseStub): typeof fetch {
  return (async () => response as Response) as unknown as typeof fetch;
}

test('fetchTextAsset reads text and reports HTTP errors', async () => {
  const text = await fetchTextAsset('/ok', 'fixture', createFetchStub({
    ok: true,
    status: 200,
    async text() {
      return 'hello';
    }
  }));
  assert.equal(text, 'hello');

  await assert.rejects(
    () => fetchTextAsset('/missing', 'fixture', createFetchStub({
      ok: false,
      status: 404,
      async text() {
        return '';
      }
    })),
    /fixture load failed \(404\)/
  );
});

test('fetchJsonAsset parses JSON and reports parse errors', async () => {
  const parsed = await fetchJsonAsset<{ a: number }>('/ok', 'bundle', createFetchStub({
    ok: true,
    status: 200,
    async text() {
      return '{"a":1}';
    }
  }));
  assert.equal(parsed.a, 1);

  await assert.rejects(
    () => fetchJsonAsset('/bad', 'bundle', createFetchStub({
      ok: true,
      status: 200,
      async text() {
        return '{';
      }
    })),
    /bundle parse failed/
  );
});
