import test from 'node:test';
import assert from 'node:assert/strict';

import { createRuntimeContext } from '../../../app/core/runtime/context';

test('createRuntimeContext creates isolated runtime holders', () => {
  const a = createRuntimeContext(() => ({ kind: 'parser-a' }));
  const b = createRuntimeContext(() => ({ kind: 'parser-b' }));

  assert.equal(a.instance, null);
  assert.equal(a.sim, null);
  assert.equal(a.irMeta, null);
  assert.equal(a.waveformP5, null);
  assert.equal((a.parser as { kind?: string } | null)?.kind, 'parser-a');
  assert.equal((b.parser as { kind?: string } | null)?.kind, 'parser-b');

  assert.ok(a.backendInstances instanceof Map);
  assert.ok(b.backendInstances instanceof Map);
  assert.notEqual(a.backendInstances, b.backendInstances);
  assert.ok(Array.isArray(a.uiTeardowns));
  assert.ok(Array.isArray(b.uiTeardowns));
  assert.notEqual(a.uiTeardowns, b.uiTeardowns);
});
