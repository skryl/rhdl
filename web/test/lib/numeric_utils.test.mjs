import test from 'node:test';
import assert from 'node:assert/strict';

import {
  toBigInt,
  parseNumeric,
  formatValue,
  parseHexOrDec,
  hexWord,
  hexByte
} from '../../app/lib/numeric_utils.mjs';

test('toBigInt normalizes numeric and bigint inputs', () => {
  assert.equal(toBigInt(42), 42n);
  assert.equal(toBigInt(7n), 7n);
  assert.equal(toBigInt(12.9), 12n);
  assert.equal(toBigInt('x'), 0n);
});

test('parseNumeric parses decimal/hex/binary and rejects invalid text', () => {
  assert.equal(parseNumeric('42'), 42n);
  assert.equal(parseNumeric('0x2a'), 42n);
  assert.equal(parseNumeric('0b101010'), 42n);
  assert.equal(parseNumeric(''), null);
  assert.equal(parseNumeric('abc'), null);
});

test('formatValue formats single-bit and multi-bit values', () => {
  assert.equal(formatValue(3, 1), '1');
  assert.equal(formatValue(31, 8), '0x1f');
  assert.equal(formatValue(null, 8), '-');
});

test('parseHexOrDec falls back to default on invalid input', () => {
  assert.equal(parseHexOrDec('0x20', 7), 32);
  assert.equal(parseHexOrDec('20', 7), 20);
  assert.equal(parseHexOrDec('', 7), 7);
  assert.equal(parseHexOrDec('hello', 7), 7);
});

test('hex helpers produce uppercase fixed-width text', () => {
  assert.equal(hexWord(0x2a), '002A');
  assert.equal(hexWord(0x12345), '2345');
  assert.equal(hexByte(0xa), '0A');
  assert.equal(hexByte(0x2ff), '2FF');
});
