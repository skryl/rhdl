import test from 'node:test';
import assert from 'node:assert/strict';

import { disassemble6502Lines, format6502Operand } from '../../../../app/components/apple2/lib/mos6502_disasm.mjs';

function makeReadMemory(memory) {
  return (start, length) => {
    const out = new Uint8Array(length);
    for (let i = 0; i < length; i += 1) {
      out[i] = memory[(start + i) & 0xffff] || 0;
    }
    return out;
  };
}

test('format6502Operand decodes representative addressing modes', () => {
  const mem = new Uint8Array(0x10000);
  mem[0x1001] = 0x34;
  mem[0x1002] = 0x12;
  const readByte = (addr) => mem[addr & 0xffff];

  assert.deepEqual(format6502Operand('imm', 0x1000, readByte), { bytes: 2, operand: '#$34' });
  assert.deepEqual(format6502Operand('abs', 0x1000, readByte), { bytes: 3, operand: '$1234' });
  assert.deepEqual(format6502Operand('rel', 0x1000, () => 0xFE), { bytes: 2, operand: '$1000' });
});

test('disassemble6502Lines produces stable formatted rows', () => {
  const mem = new Uint8Array(0x10000);
  mem[0x1000] = 0xA9; // LDA #$01
  mem[0x1001] = 0x01;
  mem[0x1002] = 0x8D; // STA $2000
  mem[0x1003] = 0x00;
  mem[0x1004] = 0x20;
  mem[0x1005] = 0xD0; // BNE $1005
  mem[0x1006] = 0xFE;

  const lines = disassemble6502Lines(0x1000, 3, makeReadMemory(mem), { highlightPc: 0x1000 });

  assert.equal(lines.length, 3);
  assert.match(lines[0], /^>> 1000: A9 01\s+LDA #\$01$/);
  assert.match(lines[1], /^\s{2} 1002: 8D 00 20\s+STA \$2000$/);
  assert.match(lines[2], /^\s{2} 1005: D0 FE\s+BNE \$1005$/);
});

test('disassemble6502Lines emits ??? for unknown opcodes', () => {
  const mem = new Uint8Array(0x10000);
  mem[0x2000] = 0x02;
  const lines = disassemble6502Lines(0x2000, 1, makeReadMemory(mem));
  assert.match(lines[0], /^\s{2} 2000: 02\s+\?\?\?$/);
});

test('disassemble6502Lines supports large mirrored windows up to 4096 lines', () => {
  const mem = new Uint8Array(0x10000);
  mem.fill(0xEA); // NOP
  const lines = disassemble6502Lines(0x0000, 4096, makeReadMemory(mem));
  assert.equal(lines.length, 4096);
  assert.match(lines[0], /^\s{2} 0000: EA\s+NOP$/);
});
