import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_APPLE2_SNAPSHOT_KIND,
  DEFAULT_APPLE2_SNAPSHOT_VERSION,
  bytesToBase64,
  base64ToBytes,
  parsePcLiteral,
  extractPcFromText,
  isSnapshotFileName,
  buildApple2SnapshotPayload,
  parseApple2SnapshotPayload,
  parseApple2SnapshotText
} from '../../app/lib/apple2_snapshot.mjs';

test('base64 helpers round-trip bytes', () => {
  const source = Uint8Array.from([0x01, 0x02, 0x7f, 0xff]);
  const encoded = bytesToBase64(source);
  const decoded = base64ToBytes(encoded);
  assert.deepEqual(Array.from(decoded), Array.from(source));
});

test('parsePcLiteral supports hex and decimal forms', () => {
  assert.equal(parsePcLiteral('$B82A'), 0xB82A);
  assert.equal(parsePcLiteral('0xB82A'), 0xB82A);
  assert.equal(parsePcLiteral('B82A'), 0xB82A);
  assert.equal(parsePcLiteral('47146'), 0xB82A);
  assert.equal(parsePcLiteral('nope'), null);
});

test('extractPcFromText finds known metadata patterns', () => {
  assert.equal(extractPcFromText('PC at dump: $B82A'), 0xB82A);
  assert.equal(extractPcFromText('start_pc = 0xB849'), 0xB849);
  assert.equal(extractPcFromText('nothing here'), null);
});

test('snapshot filename detection supports accepted extensions', () => {
  assert.equal(isSnapshotFileName('foo.rhdlsnap'), true);
  assert.equal(isSnapshotFileName('foo.snapshot.json'), true);
  assert.equal(isSnapshotFileName('foo.bin'), false);
});

test('buildApple2SnapshotPayload + parseApple2SnapshotPayload preserve fields', () => {
  const bytes = Uint8Array.from([0x11, 0x22, 0x33]);
  const payload = buildApple2SnapshotPayload(bytes, 0x200, 'test dump', '2026-02-07T00:00:00.000Z', '$B82A');

  assert.equal(payload.kind, DEFAULT_APPLE2_SNAPSHOT_KIND);
  assert.equal(payload.version, DEFAULT_APPLE2_SNAPSHOT_VERSION);
  assert.equal(payload.offset, 0x200);
  assert.equal(payload.startPc, 0xB82A);

  const parsed = parseApple2SnapshotPayload(payload);
  assert.ok(parsed);
  assert.equal(parsed.offset, 0x200);
  assert.equal(parsed.startPc, 0xB82A);
  assert.deepEqual(Array.from(parsed.bytes), Array.from(bytes));
});

test('parseApple2SnapshotPayload can infer startPc from label text', () => {
  const bytes = Uint8Array.from([0xaa]);
  const payload = buildApple2SnapshotPayload(bytes, 0, 'Karateka dump (PC=$B849)');
  delete payload.startPc;

  const parsed = parseApple2SnapshotPayload(payload);
  assert.ok(parsed);
  assert.equal(parsed.startPc, 0xB849);
});

test('parseApple2SnapshotText returns null for invalid json', () => {
  assert.equal(parseApple2SnapshotText('{broken'), null);
  assert.equal(parseApple2SnapshotText(''), null);
});
