import test from 'node:test';
import assert from 'node:assert/strict';

import {
  decode32,
  decode16,
  disassembleRiscvLines,
  classifyMnemonic,
  CSR_NAMES
} from '../../../../app/components/riscv/lib/riscv_disasm';

// --- helpers ---

function makeReadMemory(bytes) {
  // bytes: Uint8Array or object { addr: byte, ... }
  return (start, length) => {
    const out = new Uint8Array(length);
    for (let i = 0; i < length; i += 1) {
      const addr = (start + i) >>> 0;
      if (bytes instanceof Uint8Array) {
        out[i] = (addr < bytes.length) ? bytes[addr] : 0;
      } else {
        out[i] = bytes[addr] || 0;
      }
    }
    return out;
  };
}

// Encode a 32-bit instruction into little-endian bytes at address in a map.
function placeInst32(map, addr, inst) {
  map[addr] = inst & 0xff;
  map[addr + 1] = (inst >> 8) & 0xff;
  map[addr + 2] = (inst >> 16) & 0xff;
  map[addr + 3] = (inst >> 24) & 0xff;
}

function placeInst16(map, addr, inst) {
  map[addr] = inst & 0xff;
  map[addr + 1] = (inst >> 8) & 0xff;
}

// RV32I encoding helpers (matching assembler.rb)
function encodeR(rd, rs1, rs2, funct3, funct7, opcode) {
  return ((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode) >>> 0;
}

function encodeI(rd, rs1, imm, funct3, opcode) {
  return (((imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode) >>> 0;
}

function encodeS(rs1, rs2, imm, funct3, opcode) {
  const imm11_5 = (imm >> 5) & 0x7f;
  const imm4_0 = imm & 0x1f;
  return ((imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode) >>> 0;
}

function encodeB(rs1, rs2, imm, funct3, opcode) {
  const imm12 = (imm >> 12) & 0x1;
  const imm10_5 = (imm >> 5) & 0x3f;
  const imm4_1 = (imm >> 1) & 0xf;
  const imm11 = (imm >> 11) & 0x1;
  return ((imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) |
    (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | opcode) >>> 0;
}

function encodeU(rd, imm, opcode) {
  return (((imm & 0xfffff) << 12) | (rd << 7) | opcode) >>> 0;
}

function encodeJ(rd, imm, opcode) {
  const imm20 = (imm >> 20) & 0x1;
  const imm10_1 = (imm >> 1) & 0x3ff;
  const imm11 = (imm >> 11) & 0x1;
  const imm19_12 = (imm >> 12) & 0xff;
  return ((imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode) >>> 0;
}

// Opcodes
const LUI = 0b0110111, AUIPC = 0b0010111, JAL = 0b1101111, JALR = 0b1100111;
const BRANCH = 0b1100011, LOAD = 0b0000011, STORE = 0b0100011;
const OP_IMM = 0b0010011, OP = 0b0110011, SYSTEM = 0b1110011;
const MISC_MEM = 0b0001111, AMO = 0b0101111;

// --- decode32 tests ---

test('decode32: nop (addi x0, x0, 0)', () => {
  const inst = encodeI(0, 0, 0, 0b000, OP_IMM);
  assert.equal(decode32(inst, 0), 'nop');
});

test('decode32: li pseudo (addi rd, x0, imm)', () => {
  const inst = encodeI(10, 0, 42, 0b000, OP_IMM); // li a0, 42
  assert.equal(decode32(inst, 0), 'li a0, 42');
});

test('decode32: mv pseudo (addi rd, rs, 0)', () => {
  const inst = encodeI(10, 11, 0, 0b000, OP_IMM); // mv a0, a1
  assert.equal(decode32(inst, 0), 'mv a0, a1');
});

test('decode32: addi with nonzero imm', () => {
  const inst = encodeI(2, 2, -16, 0b000, OP_IMM); // addi sp, sp, -16
  assert.equal(decode32(inst, 0), 'addi sp, sp, -16');
});

test('decode32: not pseudo (xori rd, rs, -1)', () => {
  const inst = encodeI(10, 11, -1, 0b100, OP_IMM);
  assert.equal(decode32(inst, 0), 'not a0, a1');
});

test('decode32: seqz pseudo (sltiu rd, rs, 1)', () => {
  const inst = encodeI(10, 11, 1, 0b011, OP_IMM);
  assert.equal(decode32(inst, 0), 'seqz a0, a1');
});

test('decode32: slli', () => {
  const inst = encodeI(10, 11, 3, 0b001, OP_IMM);
  assert.equal(decode32(inst, 0), 'slli a0, a1, 3');
});

test('decode32: srli', () => {
  const inst = encodeI(10, 11, 4, 0b101, OP_IMM);
  assert.equal(decode32(inst, 0), 'srli a0, a1, 4');
});

test('decode32: srai', () => {
  const inst = encodeI(10, 11, (0b0100000 << 5) | 5, 0b101, OP_IMM);
  // srai uses funct7=0b0100000 in bits [31:25], shamt in [24:20]
  assert.equal(decode32(inst, 0), 'srai a0, a1, 5');
});

test('decode32: lui', () => {
  const inst = encodeU(10, 0x12345, LUI);
  assert.equal(decode32(inst, 0), 'lui a0, 0x12345');
});

test('decode32: auipc', () => {
  const inst = encodeU(10, 0xabcde, AUIPC);
  assert.equal(decode32(inst, 0), 'auipc a0, 0xabcde');
});

test('decode32: add', () => {
  const inst = encodeR(10, 11, 12, 0b000, 0b0000000, OP);
  assert.equal(decode32(inst, 0), 'add a0, a1, a2');
});

test('decode32: sub', () => {
  const inst = encodeR(10, 11, 12, 0b000, 0b0100000, OP);
  assert.equal(decode32(inst, 0), 'sub a0, a1, a2');
});

test('decode32: neg pseudo (sub rd, x0, rs)', () => {
  const inst = encodeR(10, 0, 11, 0b000, 0b0100000, OP);
  assert.equal(decode32(inst, 0), 'neg a0, a1');
});

test('decode32: snez pseudo (sltu rd, x0, rs)', () => {
  const inst = encodeR(10, 0, 11, 0b011, 0b0000000, OP);
  assert.equal(decode32(inst, 0), 'snez a0, a1');
});

test('decode32: mul (M extension)', () => {
  const inst = encodeR(10, 11, 12, 0b000, 0b0000001, OP);
  assert.equal(decode32(inst, 0), 'mul a0, a1, a2');
});

test('decode32: div (M extension)', () => {
  const inst = encodeR(10, 11, 12, 0b100, 0b0000001, OP);
  assert.equal(decode32(inst, 0), 'div a0, a1, a2');
});

test('decode32: lw', () => {
  const inst = encodeI(10, 2, 16, 0b010, LOAD);
  assert.equal(decode32(inst, 0), 'lw a0, 16(sp)');
});

test('decode32: sw', () => {
  const inst = encodeS(2, 10, 16, 0b010, STORE);
  assert.equal(decode32(inst, 0), 'sw a0, 16(sp)');
});

test('decode32: jal (pseudo j for rd=x0)', () => {
  const inst = encodeJ(0, 0x100, JAL); // j +256
  assert.equal(decode32(inst, 0x80000000), 'j 80000100');
});

test('decode32: jal ra', () => {
  const inst = encodeJ(1, 0x100, JAL); // jal ra, +256
  assert.equal(decode32(inst, 0x80000000), 'jal 80000100');
});

test('decode32: ret (jalr x0, ra, 0)', () => {
  const inst = encodeI(0, 1, 0, 0b000, JALR);
  assert.equal(decode32(inst, 0), 'ret');
});

test('decode32: jr rs (jalr x0, rs, 0)', () => {
  const inst = encodeI(0, 5, 0, 0b000, JALR);
  assert.equal(decode32(inst, 0), 'jr t0');
});

test('decode32: beq', () => {
  const inst = encodeB(10, 0, 0x20, 0b000, BRANCH); // beq a0, zero, +32
  assert.equal(decode32(inst, 0x80000000), 'beqz a0, 80000020');
});

test('decode32: bne with two regs', () => {
  const inst = encodeB(10, 11, 0x40, 0b001, BRANCH);
  assert.equal(decode32(inst, 0x80000000), 'bne a0, a1, 80000040');
});

test('decode32: ecall', () => {
  const inst = encodeI(0, 0, 0, 0b000, SYSTEM);
  assert.equal(decode32(inst, 0), 'ecall');
});

test('decode32: ebreak', () => {
  const inst = encodeI(0, 0, 1, 0b000, SYSTEM);
  assert.equal(decode32(inst, 0), 'ebreak');
});

test('decode32: mret', () => {
  const inst = encodeI(0, 0, 0x302, 0b000, SYSTEM);
  assert.equal(decode32(inst, 0), 'mret');
});

test('decode32: sret', () => {
  const inst = encodeI(0, 0, 0x102, 0b000, SYSTEM);
  assert.equal(decode32(inst, 0), 'sret');
});

test('decode32: wfi', () => {
  const inst = encodeI(0, 0, 0x105, 0b000, SYSTEM);
  assert.equal(decode32(inst, 0), 'wfi');
});

test('decode32: csrr pseudo (csrrs rd, csr, x0)', () => {
  const inst = encodeI(10, 0, 0x300, 0b010, SYSTEM); // csrr a0, mstatus
  assert.equal(decode32(inst, 0), 'csrr a0, mstatus');
});

test('decode32: csrw pseudo (csrrw x0, csr, rs)', () => {
  const inst = encodeI(0, 10, 0x180, 0b001, SYSTEM); // csrw satp, a0
  assert.equal(decode32(inst, 0), 'csrw satp, a0');
});

test('decode32: csrrs with nonzero rd and rs1', () => {
  const inst = encodeI(10, 11, 0x344, 0b010, SYSTEM); // csrrs a0, mip, a1
  assert.equal(decode32(inst, 0), 'csrrs a0, mip, a1');
});

test('decode32: fence iorw, iorw', () => {
  const pred = 0b1111, succ = 0b1111;
  const imm = (pred << 4) | succ;
  const inst = encodeI(0, 0, imm, 0b000, MISC_MEM);
  assert.equal(decode32(inst, 0), 'fence iorw, iorw');
});

test('decode32: fence.i', () => {
  const inst = encodeI(0, 0, 0, 0b001, MISC_MEM);
  assert.equal(decode32(inst, 0), 'fence.i');
});

test('decode32: amoadd.w', () => {
  // funct5=00000, aq=0, rl=0 -> funct7=0b0000000
  const inst = encodeR(10, 11, 12, 0b010, 0b0000000, AMO);
  assert.equal(decode32(inst, 0), 'amoadd.w a0, a2, (a1)');
});

test('decode32: lr.w', () => {
  // funct5=00010, aq=0, rl=0 -> funct7=0b0001000
  const inst = encodeR(10, 11, 0, 0b010, 0b0001000, AMO);
  assert.equal(decode32(inst, 0), 'lr.w a0, (a1)');
});

test('decode32: sc.w', () => {
  // funct5=00011 -> funct7=0b0001100
  const inst = encodeR(10, 11, 12, 0b010, 0b0001100, AMO);
  assert.equal(decode32(inst, 0), 'sc.w a0, a2, (a1)');
});

test('decode32: unknown opcode shows ???', () => {
  // opcode=0b1111111 is not defined
  assert.equal(decode32(0x0000007f, 0), '???');
});

// --- decode16 tests ---

test('decode16: unimp (0x0000)', () => {
  assert.equal(decode16(0x0000, 0), 'unimp');
});

test('decode16: c.nop', () => {
  // C.NOP: funct3=000, rd=0, imm=0, quadrant=01
  const inst = 0x0001; // quadrant 01, funct3 000, rd=0, imm=0
  assert.equal(decode16(inst, 0), 'c.nop');
});

test('decode16: c.addi', () => {
  // c.addi sp, 16: funct3=000, rd=2(sp), imm=16, quadrant=01
  // imm[5]=0, imm[4:0]=10000
  const inst = (0b000 << 13) | (0 << 12) | (2 << 7) | (16 << 2) | 0b01;
  assert.match(decode16(inst, 0), /c\.addi sp, 16/);
});

test('decode16: c.li', () => {
  // c.li a0, 5: funct3=010, rd=10, imm=5, quadrant=01
  const inst = (0b010 << 13) | (0 << 12) | (10 << 7) | (5 << 2) | 0b01;
  assert.equal(decode16(inst, 0), 'c.li a0, 5');
});

test('decode16: c.mv', () => {
  // c.mv a0, a1: bit12=0, rd=10, rs2=11, quadrant=10, funct3=100
  const inst = (0b100 << 13) | (0 << 12) | (10 << 7) | (11 << 2) | 0b10;
  assert.equal(decode16(inst, 0), 'c.mv a0, a1');
});

test('decode16: c.add', () => {
  // c.add a0, a1: bit12=1, rd=10, rs2=11, quadrant=10, funct3=100
  const inst = (0b100 << 13) | (1 << 12) | (10 << 7) | (11 << 2) | 0b10;
  assert.equal(decode16(inst, 0), 'c.add a0, a1');
});

test('decode16: c.jr', () => {
  // c.jr ra: bit12=0, rd/rs1=1(ra), rs2=0, quadrant=10, funct3=100
  const inst = (0b100 << 13) | (0 << 12) | (1 << 7) | (0 << 2) | 0b10;
  assert.equal(decode16(inst, 0), 'c.jr ra');
});

test('decode16: c.jalr', () => {
  // c.jalr ra: bit12=1, rd/rs1=1(ra), rs2=0, quadrant=10, funct3=100
  const inst = (0b100 << 13) | (1 << 12) | (1 << 7) | (0 << 2) | 0b10;
  assert.equal(decode16(inst, 0), 'c.jalr ra');
});

test('decode16: c.ebreak', () => {
  // c.ebreak: bit12=1, rd=0, rs2=0, quadrant=10, funct3=100
  const inst = (0b100 << 13) | (1 << 12) | (0 << 7) | (0 << 2) | 0b10;
  assert.equal(decode16(inst, 0), 'c.ebreak');
});

// --- disassembleRiscvLines integration tests ---

test('disassembleRiscvLines produces formatted output with PC highlight', () => {
  const mem = {};
  const base = 0x80000000;
  placeInst32(mem, base, encodeI(0, 0, 0, 0b000, OP_IMM)); // nop
  placeInst32(mem, base + 4, encodeI(10, 0, 42, 0b000, OP_IMM)); // li a0, 42
  placeInst32(mem, base + 8, encodeI(0, 1, 0, 0b000, JALR)); // ret

  const lines = disassembleRiscvLines(
    base, 3, makeReadMemory(mem),
    { highlightPc: base + 4, addressSpace: 0x100000000 }
  );

  assert.equal(lines.length, 3);
  assert.match(lines[0], /^\s{2} 80000000:/);
  assert.match(lines[0], /nop$/);
  assert.match(lines[1], /^>> 80000004:/);
  assert.match(lines[1], /li a0, 42$/);
  assert.match(lines[2], /^\s{2} 80000008:/);
  assert.match(lines[2], /ret$/);
});

test('disassembleRiscvLines handles mixed 32-bit and 16-bit instructions', () => {
  const mem = {};
  const base = 0x80000000;
  placeInst32(mem, base, encodeI(0, 0, 0, 0b000, OP_IMM)); // nop (32-bit)
  // c.nop = 0x0001 (16-bit)
  placeInst16(mem, base + 4, 0x0001);
  // another 32-bit after the 16-bit
  placeInst32(mem, base + 6, encodeI(10, 0, 1, 0b000, OP_IMM)); // li a0, 1

  const lines = disassembleRiscvLines(
    base, 3, makeReadMemory(mem),
    { addressSpace: 0x100000000 }
  );

  assert.equal(lines.length, 3);
  assert.match(lines[0], /nop/);
  assert.match(lines[1], /c\.nop/);
  // The 16-bit instruction advances by 2, so next is at base+6
  assert.match(lines[2], /80000006:/);
  assert.match(lines[2], /li a0, 1/);
});

test('disassembleRiscvLines shows ??? for unknown encodings', () => {
  const mem = {};
  const base = 0;
  // 0x0000007f has opcode 0b1111111 which is unknown
  placeInst32(mem, base, 0x0000007f);

  const lines = disassembleRiscvLines(
    base, 1, makeReadMemory(mem),
    { addressSpace: 0x100000000 }
  );
  assert.match(lines[0], /\?\?\?/);
});

test('disassembleRiscvLines caps at 4096 lines', () => {
  const mem = new Uint8Array(0x10000);
  // Fill with nop (0x00000013) in little-endian
  for (let i = 0; i < mem.length; i += 4) {
    mem[i] = 0x13;
    mem[i + 1] = 0x00;
    mem[i + 2] = 0x00;
    mem[i + 3] = 0x00;
  }

  const lines = disassembleRiscvLines(
    0, 5000, makeReadMemory(mem),
    { addressSpace: 0x100000000 }
  );
  assert.equal(lines.length, 4096);
});

test('CSR_NAMES includes common xv6 registers', () => {
  assert.equal(CSR_NAMES[0x300], 'mstatus');
  assert.equal(CSR_NAMES[0x180], 'satp');
  assert.equal(CSR_NAMES[0xF14], 'mhartid');
  assert.equal(CSR_NAMES[0x141], 'sepc');
});

// --- classifyMnemonic tests ---

test('classifyMnemonic categorizes arithmetic instructions', () => {
  assert.equal(classifyMnemonic('add'), 'arith');
  assert.equal(classifyMnemonic('sub'), 'arith');
  assert.equal(classifyMnemonic('addi'), 'arith');
  assert.equal(classifyMnemonic('xor'), 'arith');
  assert.equal(classifyMnemonic('slli'), 'arith');
  assert.equal(classifyMnemonic('mul'), 'arith');
  assert.equal(classifyMnemonic('div'), 'arith');
  assert.equal(classifyMnemonic('c.add'), 'arith');
  assert.equal(classifyMnemonic('c.sub'), 'arith');
  assert.equal(classifyMnemonic('c.andi'), 'arith');
});

test('classifyMnemonic categorizes load instructions', () => {
  assert.equal(classifyMnemonic('lw'), 'load');
  assert.equal(classifyMnemonic('lb'), 'load');
  assert.equal(classifyMnemonic('lhu'), 'load');
  assert.equal(classifyMnemonic('c.lw'), 'load');
  assert.equal(classifyMnemonic('c.lwsp'), 'load');
});

test('classifyMnemonic categorizes store instructions', () => {
  assert.equal(classifyMnemonic('sw'), 'store');
  assert.equal(classifyMnemonic('sb'), 'store');
  assert.equal(classifyMnemonic('c.sw'), 'store');
  assert.equal(classifyMnemonic('c.swsp'), 'store');
});

test('classifyMnemonic categorizes branch instructions', () => {
  assert.equal(classifyMnemonic('beq'), 'branch');
  assert.equal(classifyMnemonic('bne'), 'branch');
  assert.equal(classifyMnemonic('beqz'), 'branch');
  assert.equal(classifyMnemonic('bnez'), 'branch');
  assert.equal(classifyMnemonic('blt'), 'branch');
  assert.equal(classifyMnemonic('bgeu'), 'branch');
  assert.equal(classifyMnemonic('c.beqz'), 'branch');
  assert.equal(classifyMnemonic('c.bnez'), 'branch');
});

test('classifyMnemonic categorizes jump instructions', () => {
  assert.equal(classifyMnemonic('jal'), 'jump');
  assert.equal(classifyMnemonic('jalr'), 'jump');
  assert.equal(classifyMnemonic('j'), 'jump');
  assert.equal(classifyMnemonic('jr'), 'jump');
  assert.equal(classifyMnemonic('ret'), 'jump');
  assert.equal(classifyMnemonic('c.j'), 'jump');
  assert.equal(classifyMnemonic('c.jal'), 'jump');
  assert.equal(classifyMnemonic('c.jr'), 'jump');
  assert.equal(classifyMnemonic('c.jalr'), 'jump');
});

test('classifyMnemonic categorizes immediate/data instructions', () => {
  assert.equal(classifyMnemonic('li'), 'imm');
  assert.equal(classifyMnemonic('lui'), 'imm');
  assert.equal(classifyMnemonic('auipc'), 'imm');
  assert.equal(classifyMnemonic('mv'), 'imm');
  assert.equal(classifyMnemonic('nop'), 'imm');
  assert.equal(classifyMnemonic('c.li'), 'imm');
  assert.equal(classifyMnemonic('c.lui'), 'imm');
  assert.equal(classifyMnemonic('c.mv'), 'imm');
  assert.equal(classifyMnemonic('c.nop'), 'imm');
  assert.equal(classifyMnemonic('c.addi4spn'), 'imm');
  assert.equal(classifyMnemonic('c.addi16sp'), 'imm');
});

test('classifyMnemonic categorizes system instructions', () => {
  assert.equal(classifyMnemonic('ecall'), 'sys');
  assert.equal(classifyMnemonic('ebreak'), 'sys');
  assert.equal(classifyMnemonic('mret'), 'sys');
  assert.equal(classifyMnemonic('sret'), 'sys');
  assert.equal(classifyMnemonic('wfi'), 'sys');
  assert.equal(classifyMnemonic('fence'), 'sys');
  assert.equal(classifyMnemonic('fence.i'), 'sys');
  assert.equal(classifyMnemonic('sfence.vma'), 'sys');
  assert.equal(classifyMnemonic('csrr'), 'sys');
  assert.equal(classifyMnemonic('csrw'), 'sys');
  assert.equal(classifyMnemonic('csrrw'), 'sys');
  assert.equal(classifyMnemonic('c.ebreak'), 'sys');
});

test('classifyMnemonic categorizes atomic instructions', () => {
  assert.equal(classifyMnemonic('lr.w'), 'amo');
  assert.equal(classifyMnemonic('sc.w'), 'amo');
  assert.equal(classifyMnemonic('amoadd.w'), 'amo');
  assert.equal(classifyMnemonic('amoswap.w.aq'), 'amo');
});

test('classifyMnemonic returns null for unknown/invalid', () => {
  assert.equal(classifyMnemonic('???'), null);
  assert.equal(classifyMnemonic('unimp'), null);
  assert.equal(classifyMnemonic(null), null);
  assert.equal(classifyMnemonic(''), null);
});

// --- structured output tests ---

test('disassembleRiscvLines with structured option returns objects', () => {
  const mem = {};
  const base = 0x80000000;
  placeInst32(mem, base, encodeI(0, 0, 0, 0b000, OP_IMM)); // nop
  placeInst32(mem, base + 4, encodeI(10, 0, 42, 0b000, OP_IMM)); // li a0, 42
  placeInst32(mem, base + 8, encodeI(0, 1, 0, 0b000, JALR)); // ret

  const lines = disassembleRiscvLines(
    base, 3, makeReadMemory(mem),
    { highlightPc: base + 4, addressSpace: 0x100000000, structured: true }
  );

  assert.equal(lines.length, 3);
  assert.equal(lines[0].type, 'asm');
  assert.equal(lines[0].category, 'imm'); // nop
  assert.match(lines[0].text, /nop$/);

  assert.equal(lines[1].type, 'asm');
  assert.equal(lines[1].category, 'imm'); // li
  assert.match(lines[1].text, /^>>/);

  assert.equal(lines[2].type, 'asm');
  assert.equal(lines[2].category, 'jump'); // ret
  assert.match(lines[2].text, /ret$/);
});
