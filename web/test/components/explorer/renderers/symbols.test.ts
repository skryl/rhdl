import test from 'node:test';
import assert from 'node:assert/strict';
import { symbolShapes, SYMBOL_TYPES } from '../../../../app/components/explorer/renderers/symbols';

test('symbolShapes has entries for all expected types', () => {
  for (const type of SYMBOL_TYPES) {
    assert.ok(symbolShapes.has(type), `missing shape for type: ${type}`);
  }
});

test('SYMBOL_TYPES includes all core types', () => {
  const expected = ['component', 'focus', 'io', 'memory', 'op', 'net', 'pin'] as const;
  for (const t of expected) {
    assert.ok(SYMBOL_TYPES.includes(t), `SYMBOL_TYPES missing: ${t}`);
  }
});

test('each shape has draw and boundingBox functions', () => {
  for (const [type, shape] of symbolShapes) {
    assert.equal(typeof shape.draw, 'function', `${type}.draw is not a function`);
    assert.equal(typeof shape.boundingBox, 'function', `${type}.boundingBox is not a function`);
  }
});

function createMockCtx() {
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const handler = {
    get(target: Record<PropertyKey, unknown>, prop: PropertyKey) {
      if (prop in target) return target[prop];
      return (...args: unknown[]) => { calls.push({ method: String(prop), args }); };
    }
  };
  return { calls, ctx: new Proxy({ calls }, handler) as unknown as CanvasRenderingContext2D };
}

test('component shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('component')!.draw(ctx, 100, 100, 178, 72, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('focus shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('focus')!.draw(ctx, 100, 100, 228, 94, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('memory shape draw calls beginPath at least twice (double border)', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('memory')!.draw(ctx, 100, 100, 124, 56, {});
  const beginPaths = calls.filter(c => c.method === 'beginPath');
  assert.ok(beginPaths.length >= 2, `memory shape should draw double border, got ${beginPaths.length} beginPath calls`);
});

test('io shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('io')!.draw(ctx, 100, 100, 34, 16, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('op shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('op')!.draw(ctx, 100, 100, 104, 42, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('net shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('net')!.draw(ctx, 100, 100, 52, 18, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('pin shape draw calls beginPath', () => {
  const { calls, ctx } = createMockCtx();
  symbolShapes.get('pin')!.draw(ctx, 100, 100, 14, 10, {});
  assert.ok(calls.some(c => c.method === 'beginPath'), 'expected beginPath call');
});

test('boundingBox returns {x, y, w, h} with correct bounds', () => {
  const bb = symbolShapes.get('component')!.boundingBox(100, 200, 178, 72);
  assert.equal(bb.x, 100 - 178 / 2, 'x = cx - w/2');
  assert.equal(bb.y, 200 - 72 / 2, 'y = cy - h/2');
  assert.equal(bb.w, 178);
  assert.equal(bb.h, 72);
});
