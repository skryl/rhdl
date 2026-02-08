import test from 'node:test';
import assert from 'node:assert/strict';

import { BACKEND_DEFS, getBackendDef } from '../../app/runtime/backend_defs.mjs';

test('getBackendDef resolves known backends and falls back to interpreter', () => {
  assert.equal(getBackendDef('interpreter').id, 'interpreter');
  assert.equal(getBackendDef('jit').id, 'jit');
  assert.equal(getBackendDef('compiler').id, 'compiler');
  assert.equal(getBackendDef('unknown').id, 'interpreter');
  assert.equal(getBackendDef(null).id, 'interpreter');
});

test('backend defs expose wasm paths for each backend', () => {
  for (const id of ['interpreter', 'jit', 'compiler']) {
    const def = BACKEND_DEFS[id];
    assert.ok(def);
    assert.equal(typeof def.wasmPath, 'string');
    assert.ok(def.wasmPath.endsWith('.wasm'));
  }
});
