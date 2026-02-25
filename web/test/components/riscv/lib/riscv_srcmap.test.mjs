import test from 'node:test';
import assert from 'node:assert/strict';
import { createRiscvSourceMap } from '../../../../app/components/riscv/lib/riscv_srcmap.mjs';
import { disassembleRiscvLines } from '../../../../app/components/riscv/lib/riscv_disasm.mjs';

const validJson = {
  format: 'rhdl.riscv.srcmap.v1',
  files: ['kernel/start.c', 'kernel/main.c'],
  functions: [
    [0x80000000, 0x100, 'start', 0],
    [0x80000100, 0x200, 'main', 1],
  ],
  lines: [
    [0x80000000, 0, 10],
    [0x80000004, 0, 11],
    [0x80000100, 1, 5],
  ],
  sources: {
    'kernel/start.c':
      'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11',
  },
};

test('returns null for missing format', () => {
  const json = { ...validJson };
  delete json.format;
  const result = createRiscvSourceMap(json);
  assert.equal(result, null);
});

test('returns null for wrong format', () => {
  const json = { ...validJson, format: 'wrong.format.v1' };
  const result = createRiscvSourceMap(json);
  assert.equal(result, null);
});

test('reports correct counts', () => {
  const map = createRiscvSourceMap(validJson);
  assert.equal(map.fileCount, 2);
  assert.equal(map.functionCount, 2);
  assert.equal(map.lineCount, 3);
});

test('lookupFunction returns function for address in range', () => {
  const map = createRiscvSourceMap(validJson);
  const fn = map.lookupFunction(0x80000000);
  assert.notEqual(fn, null);
  assert.equal(fn.name, 'start');
  assert.equal(fn.addr, 0x80000000);
  assert.equal(fn.size, 0x100);
  assert.equal(fn.file, 'kernel/start.c');
});

test('lookupFunction returns null for address outside function', () => {
  const map = createRiscvSourceMap(validJson);
  const fn = map.lookupFunction(0x80000300);
  assert.equal(fn, null);
});

test('lookupLine returns line info for known address', () => {
  const map = createRiscvSourceMap(validJson);
  const line = map.lookupLine(0x80000004);
  assert.notEqual(line, null);
  assert.equal(line.file, 'kernel/start.c');
  assert.equal(line.line, 11);
});

test('lookupLine returns null for address before any line', () => {
  const map = createRiscvSourceMap(validJson);
  const line = map.lookupLine(0x70000000);
  assert.equal(line, null);
});

test('getSourceLine returns correct line text', () => {
  const map = createRiscvSourceMap(validJson);
  const text = map.getSourceLine('kernel/start.c', 10);
  assert.equal(text, 'line10');
});

test('getSourceLine returns null for out-of-range line', () => {
  const map = createRiscvSourceMap(validJson);
  const text = map.getSourceLine('kernel/start.c', 99);
  assert.equal(text, null);
});

test('lookup returns combined function/file/line/source info', () => {
  const map = createRiscvSourceMap(validJson);
  const info = map.lookup(0x80000000);
  assert.notEqual(info, null);
  assert.equal(info.function, 'start');
  assert.equal(info.file, 'kernel/start.c');
  assert.equal(info.line, 10);
  assert.equal(info.source, 'line10');
});

test('lookup returns null for address before all entries', () => {
  const map = createRiscvSourceMap(validJson);
  const info = map.lookup(0x70000000);
  assert.equal(info, null);
});

test('disassembleRiscvLines integrates source annotations when sourceMap is given', () => {
  const map = createRiscvSourceMap(validJson);

  // Build a small memory buffer with NOP instructions (addi x0, x0, 0 = 0x00000013)
  // Place two NOPs at 0x80000000 and 0x80000004
  const NOP = 0x00000013;
  const buf = new Uint8Array(8);
  const view = new DataView(buf.buffer);
  view.setUint32(0, NOP, true);
  view.setUint32(4, NOP, true);

  function readMemory(start, length) {
    const out = new Uint8Array(length);
    const base = 0x80000000;
    for (let i = 0; i < length; i += 1) {
      const offset = ((start + i) >>> 0) - base;
      if (offset >= 0 && offset < buf.length) {
        out[i] = buf[offset];
      }
    }
    return out;
  }

  const lines = disassembleRiscvLines(
    0x80000000,
    2,
    readMemory,
    { addressSpace: 0x100000000, sourceMap: map }
  );

  // Should contain a function header annotation for start()
  const hasHeader = lines.some(
    (l) => l.includes('start') && l.includes('kernel/start.c')
  );
  assert.ok(hasHeader, `Expected function header annotation in output: ${JSON.stringify(lines)}`);

  // Should contain a source line annotation for line 10
  const hasSourceLine = lines.some((l) => l.includes('10:') && l.includes('line10'));
  assert.ok(hasSourceLine, `Expected source line annotation in output: ${JSON.stringify(lines)}`);
});
