// RV32IMAC Disassembler for the web simulator.
// Decodes 32-bit and 16-bit compressed RISC-V instructions into mnemonics.

// ABI register names (x0..x31).
const REGS = [
  'zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
  's0', 's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
  'a6', 'a7', 's2', 's3', 's4', 's5', 's6', 's7',
  's8', 's9', 's10', 's11', 't3', 't4', 't5', 't6'
];

// Opcodes.
const OP_LUI      = 0b0110111;
const OP_AUIPC    = 0b0010111;
const OP_JAL      = 0b1101111;
const OP_JALR     = 0b1100111;
const OP_BRANCH   = 0b1100011;
const OP_LOAD     = 0b0000011;
const OP_STORE    = 0b0100011;
const OP_OP_IMM   = 0b0010011;
const OP_OP       = 0b0110011;
const OP_MISC_MEM = 0b0001111;
const OP_SYSTEM   = 0b1110011;
const OP_AMO      = 0b0101111;
const OP_LOAD_FP  = 0b0000111;
const OP_STORE_FP = 0b0100111;
const OP_OP_FP    = 0b1010011;

// Common CSR names used in xv6/Linux.
export const CSR_NAMES: Record<number, string> = {
  0x100: 'sstatus', 0x104: 'sie', 0x105: 'stvec',
  0x106: 'scounteren',
  0x140: 'sscratch', 0x141: 'sepc', 0x142: 'scause',
  0x143: 'stval', 0x144: 'sip', 0x180: 'satp',
  0x300: 'mstatus', 0x301: 'misa', 0x302: 'medeleg',
  0x303: 'mideleg', 0x304: 'mie', 0x305: 'mtvec',
  0x306: 'mcounteren', 0x310: 'mstatush',
  0x340: 'mscratch', 0x341: 'mepc', 0x342: 'mcause',
  0x343: 'mtval', 0x344: 'mip',
  0x3A0: 'pmpcfg0', 0x3A1: 'pmpcfg1',
  0x3A2: 'pmpcfg2', 0x3A3: 'pmpcfg3',
  0x3B0: 'pmpaddr0', 0x3B1: 'pmpaddr1',
  0x3B2: 'pmpaddr2', 0x3B3: 'pmpaddr3',
  0xB00: 'mcycle', 0xB02: 'minstret',
  0xC00: 'cycle', 0xC01: 'time', 0xC02: 'instret',
  0xC80: 'cycleh', 0xC81: 'timeh', 0xC82: 'instreth',
  0xF11: 'mvendorid', 0xF12: 'marchid',
  0xF13: 'mimpid', 0xF14: 'mhartid'
};

function reg(n: Unsafe) {
  return REGS[n & 0x1f];
}

function signExtend(value: Unsafe, bits: Unsafe) {
  const shift = 32 - bits;
  return (value << shift) >> shift;
}

function csrName(csr: Unsafe) {
  return CSR_NAMES[csr & 0xfff] || `0x${(csr & 0xfff).toString(16)}`;
}

function fenceFlags(val: Unsafe) {
  let s = '';
  if (val & 8) s += 'i';
  if (val & 4) s += 'o';
  if (val & 2) s += 'r';
  if (val & 1) s += 'w';
  return s || '0';
}

function amoSuffix(funct7: Unsafe) {
  const aq = (funct7 >> 1) & 1;
  const rl = funct7 & 1;
  if (aq && rl) return '.aqrl';
  if (aq) return '.aq';
  if (rl) return '.rl';
  return '';
}

function formatAddr(addr: Unsafe, wide: Unsafe) {
  return wide
    ? (addr >>> 0).toString(16).toUpperCase().padStart(8, '0')
    : (addr & 0xffff).toString(16).toUpperCase().padStart(4, '0');
}

// --- 32-bit instruction decoder ---

function decodeOpImm(inst: Unsafe) {
  const rd = (inst >> 7) & 0x1f;
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;
  const imm = signExtend((inst >> 20) & 0xfff, 12);
  const shamt = (inst >> 20) & 0x1f;

  if (funct3 === 0) {
    if (rd === 0 && rs1 === 0 && imm === 0) return 'nop';
    if (rs1 === 0) return `li ${reg(rd)}, ${imm}`;
    if (imm === 0) return `mv ${reg(rd)}, ${reg(rs1)}`;
    return `addi ${reg(rd)}, ${reg(rs1)}, ${imm}`;
  }
  if (funct3 === 0b100 && imm === -1) return `not ${reg(rd)}, ${reg(rs1)}`;
  if (funct3 === 0b011 && imm === 1) return `seqz ${reg(rd)}, ${reg(rs1)}`;

  const funct7 = (inst >> 25) & 0x7f;
  switch (funct3) {
    case 0b010: return `slti ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    case 0b011: return `sltiu ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    case 0b100: return `xori ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    case 0b110: return `ori ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    case 0b111: return `andi ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    case 0b001: return `slli ${reg(rd)}, ${reg(rs1)}, ${shamt}`;
    case 0b101:
      if (funct7 & 0b0100000) return `srai ${reg(rd)}, ${reg(rs1)}, ${shamt}`;
      return `srli ${reg(rd)}, ${reg(rs1)}, ${shamt}`;
    default: return '???';
  }
}

function decodeOp(inst: Unsafe) {
  const rd = (inst >> 7) & 0x1f;
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;
  const rs2 = (inst >> 20) & 0x1f;
  const funct7 = (inst >> 25) & 0x7f;
  const r = `${reg(rd)}, ${reg(rs1)}, ${reg(rs2)}`;

  if (funct7 === 0b0000001) {
    const mOps = ['mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu'];
    return `${mOps[funct3]} ${r}`;
  }

  if (funct7 === 0b0010000) {
    const zba: Record<number, string> = { 0b010: 'sh1add', 0b100: 'sh2add', 0b110: 'sh3add' };
    if (zba[funct3]) return `${zba[funct3]} ${r}`;
  }

  if (funct7 === 0b0100000) {
    if (funct3 === 0b000) {
      if (rs1 === 0) return `neg ${reg(rd)}, ${reg(rs2)}`;
      return `sub ${r}`;
    }
    if (funct3 === 0b101) return `sra ${r}`;
    if (funct3 === 0b111) return `andn ${r}`;
    if (funct3 === 0b110) return `orn ${r}`;
    if (funct3 === 0b100) return `xnor ${r}`;
  }

  if (funct7 === 0b0000101) {
    const ops: Record<number, string> = {
      0b001: 'clmul', 0b010: 'clmulr', 0b011: 'clmulh',
      0b100: 'min', 0b101: 'minu', 0b110: 'max', 0b111: 'maxu'
    };
    if (ops[funct3]) return `${ops[funct3]} ${r}`;
  }

  if (funct7 === 0b0000100) {
    if (funct3 === 0b100) return `pack ${r}`;
    if (funct3 === 0b111) return `packh ${r}`;
  }

  if (funct7 === 0b0000000) {
    if (funct3 === 0b011 && rs1 === 0) return `snez ${reg(rd)}, ${reg(rs2)}`;
    const ops = ['add', 'sll', 'slt', 'sltu', 'xor', 'srl', 'or', 'and'];
    return `${ops[funct3]} ${r}`;
  }

  return '???';
}

function decodeBranch(inst: Unsafe, addr: Unsafe) {
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;
  const rs2 = (inst >> 20) & 0x1f;
  const imm12 = (inst >> 31) & 1;
  const imm10_5 = (inst >> 25) & 0x3f;
  const imm4_1 = (inst >> 8) & 0xf;
  const imm11 = (inst >> 7) & 1;
  const offset = signExtend(
    (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1),
    13
  );
  const target = (addr + offset) >>> 0;
  const wide = true;
  const ops: Record<number, string> = { 0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge', 6: 'bltu', 7: 'bgeu' };
  const mn = ops[funct3];
  if (!mn) return '???';
  if (rs2 === 0) {
    const pseudo: Record<string, string> = { beq: 'beqz', bne: 'bnez' };
    if (pseudo[mn]) return `${pseudo[mn]} ${reg(rs1)}, ${formatAddr(target, wide)}`;
  }
  return `${mn} ${reg(rs1)}, ${reg(rs2)}, ${formatAddr(target, wide)}`;
}

function decodeSystem(inst: Unsafe) {
  const rd = (inst >> 7) & 0x1f;
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;
  const funct7 = (inst >> 25) & 0x7f;
  const rs2 = (inst >> 20) & 0x1f;
  const imm = (inst >> 20) & 0xfff;

  if (funct3 === 0) {
    if (imm === 0x000 && rs1 === 0 && rd === 0) return 'ecall';
    if (imm === 0x001 && rs1 === 0 && rd === 0) return 'ebreak';
    if (imm === 0x302 && rs1 === 0 && rd === 0) return 'mret';
    if (imm === 0x102 && rs1 === 0 && rd === 0) return 'sret';
    if (imm === 0x105 && rs1 === 0 && rd === 0) return 'wfi';
    if (funct7 === 0b0001001) return `sfence.vma ${reg(rs1)}, ${reg(rs2)}`;
    return '???';
  }

  const csr = imm;
  const cn = csrName(csr);
  switch (funct3) {
    case 0b001:
      if (rd === 0) return `csrw ${cn}, ${reg(rs1)}`;
      return `csrrw ${reg(rd)}, ${cn}, ${reg(rs1)}`;
    case 0b010:
      if (rs1 === 0) return `csrr ${reg(rd)}, ${cn}`;
      if (rd === 0) return `csrs ${cn}, ${reg(rs1)}`;
      return `csrrs ${reg(rd)}, ${cn}, ${reg(rs1)}`;
    case 0b011:
      if (rd === 0) return `csrc ${cn}, ${reg(rs1)}`;
      return `csrrc ${reg(rd)}, ${cn}, ${reg(rs1)}`;
    case 0b101:
      if (rd === 0) return `csrwi ${cn}, ${rs1}`;
      return `csrrwi ${reg(rd)}, ${cn}, ${rs1}`;
    case 0b110:
      if (rd === 0) return `csrsi ${cn}, ${rs1}`;
      return `csrrsi ${reg(rd)}, ${cn}, ${rs1}`;
    case 0b111:
      if (rd === 0) return `csrci ${cn}, ${rs1}`;
      return `csrrci ${reg(rd)}, ${cn}, ${rs1}`;
    default: return '???';
  }
}

function decodeAmo(inst: Unsafe) {
  const rd = (inst >> 7) & 0x1f;
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;
  const rs2 = (inst >> 20) & 0x1f;
  const funct7 = (inst >> 25) & 0x7f;
  if (funct3 !== 0b010) return '???';
  const funct5 = (funct7 >> 2) & 0x1f;
  const sfx = amoSuffix(funct7);
  const dst = `${reg(rd)}, `;
  const src = `(${reg(rs1)})`;

  switch (funct5) {
    case 0b00010: return `lr.w${sfx} ${reg(rd)}, ${src}`;
    case 0b00011: return `sc.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b00001: return `amoswap.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b00000: return `amoadd.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b00100: return `amoxor.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b01100: return `amoand.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b01000: return `amoor.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b10000: return `amomin.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b10100: return `amomax.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b11000: return `amominu.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    case 0b11100: return `amomaxu.w${sfx} ${dst}${reg(rs2)}, ${src}`;
    default: return '???';
  }
}

export function decode32(inst: Unsafe, addr: Unsafe) {
  const opcode = inst & 0x7f;
  const rd = (inst >> 7) & 0x1f;
  const funct3 = (inst >> 12) & 0x7;
  const rs1 = (inst >> 15) & 0x1f;

  switch (opcode) {
    case OP_LUI: {
      const upper = (inst >>> 12) & 0xfffff;
      return `lui ${reg(rd)}, 0x${upper.toString(16)}`;
    }
    case OP_AUIPC: {
      const upper = (inst >>> 12) & 0xfffff;
      return `auipc ${reg(rd)}, 0x${upper.toString(16)}`;
    }
    case OP_JAL: {
      const imm20 = (inst >> 31) & 1;
      const imm10_1 = (inst >> 21) & 0x3ff;
      const imm11 = (inst >> 20) & 1;
      const imm19_12 = (inst >> 12) & 0xff;
      const offset = signExtend(
        (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1),
        21
      );
      const target = (addr + offset) >>> 0;
      if (rd === 0) return `j ${formatAddr(target, true)}`;
      if (rd === 1) return `jal ${formatAddr(target, true)}`;
      return `jal ${reg(rd)}, ${formatAddr(target, true)}`;
    }
    case OP_JALR: {
      const imm = signExtend((inst >> 20) & 0xfff, 12);
      if (rd === 0 && rs1 === 1 && imm === 0) return 'ret';
      if (rd === 0 && imm === 0) return `jr ${reg(rs1)}`;
      if (rd === 1 && imm === 0) return `jalr ${reg(rs1)}`;
      return `jalr ${reg(rd)}, ${reg(rs1)}, ${imm}`;
    }
    case OP_BRANCH: return decodeBranch(inst, addr);
    case OP_LOAD: {
      const imm = signExtend((inst >> 20) & 0xfff, 12);
      const ops: Record<number, string> = { 0: 'lb', 1: 'lh', 2: 'lw', 4: 'lbu', 5: 'lhu' };
      const mn = ops[funct3] || '???';
      return `${mn} ${reg(rd)}, ${imm}(${reg(rs1)})`;
    }
    case OP_LOAD_FP: {
      const imm = signExtend((inst >> 20) & 0xfff, 12);
      if (funct3 === 0b010) return `flw f${rd}, ${imm}(${reg(rs1)})`;
      return '???';
    }
    case OP_STORE: {
      const rs2 = (inst >> 20) & 0x1f;
      const imm = signExtend(((inst >> 25) << 5) | ((inst >> 7) & 0x1f), 12);
      const ops: Record<number, string> = { 0: 'sb', 1: 'sh', 2: 'sw' };
      const mn = ops[funct3] || '???';
      return `${mn} ${reg(rs2)}, ${imm}(${reg(rs1)})`;
    }
    case OP_STORE_FP: {
      const rs2 = (inst >> 20) & 0x1f;
      const imm = signExtend(((inst >> 25) << 5) | ((inst >> 7) & 0x1f), 12);
      if (funct3 === 0b010) return `fsw f${rs2}, ${imm}(${reg(rs1)})`;
      return '???';
    }
    case OP_OP_IMM: return decodeOpImm(inst);
    case OP_OP: return decodeOp(inst);
    case OP_MISC_MEM: {
      if (funct3 === 0) {
        const pred = (inst >> 24) & 0xf;
        const succ = (inst >> 20) & 0xf;
        return `fence ${fenceFlags(pred)}, ${fenceFlags(succ)}`;
      }
      if (funct3 === 1) return 'fence.i';
      return '???';
    }
    case OP_SYSTEM: return decodeSystem(inst);
    case OP_AMO: return decodeAmo(inst);
    case OP_OP_FP: {
      const rs2 = (inst >> 20) & 0x1f;
      const funct7 = (inst >> 25) & 0x7f;
      if (funct7 === 0b1110000 && rs2 === 0 && funct3 === 0)
        return `fmv.x.w ${reg(rd)}, f${rs1}`;
      if (funct7 === 0b1111000 && rs2 === 0 && funct3 === 0)
        return `fmv.w.x f${rd}, ${reg(rs1)}`;
      return '???';
    }
    default: return '???';
  }
}

// --- 16-bit compressed instruction decoder ---

export function decode16(inst: Unsafe, addr: Unsafe) {
  const quadrant = inst & 0x3;
  const funct3 = (inst >> 13) & 0x7;
  const rdRs1 = (inst >> 7) & 0x1f;
  const rs2Field = (inst >> 2) & 0x1f;

  if (inst === 0) return 'unimp';

  if (quadrant === 0b00) return decodeQ0(inst, funct3);
  if (quadrant === 0b01) return decodeQ1(inst, funct3, addr);
  if (quadrant === 0b10) return decodeQ2(inst, funct3, rdRs1, rs2Field);
  return '???';
}

function decodeQ0(inst: Unsafe, funct3: Unsafe) {
  const rdp = reg(((inst >> 2) & 0x7) + 8);
  const rs1p = reg(((inst >> 7) & 0x7) + 8);

  if (funct3 === 0b000) {
    // C.ADDI4SPN
    const nzuimm =
      (((inst >> 5) & 0x1) << 3) |
      (((inst >> 6) & 0x1) << 2) |
      (((inst >> 7) & 0xf) << 6) |
      (((inst >> 11) & 0x3) << 4);
    if (nzuimm === 0) return 'unimp';
    return `c.addi4spn ${rdp}, ${nzuimm}`;
  }
  if (funct3 === 0b010) {
    // C.LW
    const offset =
      (((inst >> 5) & 0x1) << 6) |
      (((inst >> 6) & 0x1) << 2) |
      (((inst >> 10) & 0x7) << 3);
    return `c.lw ${rdp}, ${offset}(${rs1p})`;
  }
  if (funct3 === 0b110) {
    // C.SW
    const rs2p = reg(((inst >> 2) & 0x7) + 8);
    const offset =
      (((inst >> 5) & 0x1) << 6) |
      (((inst >> 6) & 0x1) << 2) |
      (((inst >> 10) & 0x7) << 3);
    return `c.sw ${rs2p}, ${offset}(${rs1p})`;
  }
  return '???';
}

function decodeQ1(inst: Unsafe, funct3: Unsafe, addr: Unsafe) {
  const rdRs1 = (inst >> 7) & 0x1f;
  const rdp = ((inst >> 7) & 0x7) + 8;
  const rs2p = ((inst >> 2) & 0x7) + 8;

  if (funct3 === 0b000) {
    // C.NOP / C.ADDI
    const nzimm = signExtend((((inst >> 12) & 0x1) << 5) | ((inst >> 2) & 0x1f), 6);
    if (rdRs1 === 0) return 'c.nop';
    return `c.addi ${reg(rdRs1)}, ${nzimm}`;
  }
  if (funct3 === 0b001) {
    // C.JAL (RV32)
    const offset = decodeCJOffset(inst);
    const target = (addr + offset) >>> 0;
    return `c.jal ${formatAddr(target, true)}`;
  }
  if (funct3 === 0b010) {
    // C.LI
    const imm = signExtend((((inst >> 12) & 0x1) << 5) | ((inst >> 2) & 0x1f), 6);
    return `c.li ${reg(rdRs1)}, ${imm}`;
  }
  if (funct3 === 0b011) {
    // C.ADDI16SP / C.LUI
    if (rdRs1 === 2) {
      const nzimm = signExtend(
        (((inst >> 12) & 0x1) << 9) |
        (((inst >> 3) & 0x3) << 7) |
        (((inst >> 5) & 0x1) << 6) |
        (((inst >> 2) & 0x1) << 5) |
        (((inst >> 6) & 0x1) << 4),
        10
      );
      return `c.addi16sp ${nzimm}`;
    }
    const nzimm = signExtend((((inst >> 12) & 0x1) << 5) | ((inst >> 2) & 0x1f), 6);
    return `c.lui ${reg(rdRs1)}, ${nzimm}`;
  }
  if (funct3 === 0b100) {
    // C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
    const funct2 = (inst >> 10) & 0x3;
    const shamt = ((inst >> 2) & 0x1f);
    if (funct2 === 0b00) return `c.srli ${reg(rdp)}, ${shamt}`;
    if (funct2 === 0b01) return `c.srai ${reg(rdp)}, ${shamt}`;
    if (funct2 === 0b10) {
      const imm = signExtend((((inst >> 12) & 0x1) << 5) | ((inst >> 2) & 0x1f), 6);
      return `c.andi ${reg(rdp)}, ${imm}`;
    }
    // funct2 === 0b11: sub/xor/or/and
    const funct = (inst >> 5) & 0x3;
    const ops = ['c.sub', 'c.xor', 'c.or', 'c.and'];
    return `${ops[funct]} ${reg(rdp)}, ${reg(rs2p)}`;
  }
  if (funct3 === 0b101) {
    // C.J
    const offset = decodeCJOffset(inst);
    const target = (addr + offset) >>> 0;
    return `c.j ${formatAddr(target, true)}`;
  }
  if (funct3 === 0b110) {
    // C.BEQZ
    const offset = decodeCBOffset(inst);
    const target = (addr + offset) >>> 0;
    return `c.beqz ${reg(rdp)}, ${formatAddr(target, true)}`;
  }
  if (funct3 === 0b111) {
    // C.BNEZ
    const offset = decodeCBOffset(inst);
    const target = (addr + offset) >>> 0;
    return `c.bnez ${reg(rdp)}, ${formatAddr(target, true)}`;
  }
  return '???';
}

function decodeQ2(inst: Unsafe, funct3: Unsafe, rdRs1: Unsafe, rs2: Unsafe) {
  if (funct3 === 0b000) {
    // C.SLLI
    const shamt = (inst >> 2) & 0x1f;
    return `c.slli ${reg(rdRs1)}, ${shamt}`;
  }
  if (funct3 === 0b010) {
    // C.LWSP
    const offset =
      (((inst >> 2) & 0x3) << 6) |
      (((inst >> 4) & 0x7) << 2) |
      (((inst >> 12) & 0x1) << 5);
    return `c.lwsp ${reg(rdRs1)}, ${offset}`;
  }
  if (funct3 === 0b100) {
    const bit12 = (inst >> 12) & 0x1;
    if (bit12 === 0) {
      if (rs2 === 0) return `c.jr ${reg(rdRs1)}`;
      return `c.mv ${reg(rdRs1)}, ${reg(rs2)}`;
    }
    if (rdRs1 === 0 && rs2 === 0) return 'c.ebreak';
    if (rs2 === 0) return `c.jalr ${reg(rdRs1)}`;
    return `c.add ${reg(rdRs1)}, ${reg(rs2)}`;
  }
  if (funct3 === 0b110) {
    // C.SWSP
    const offset =
      (((inst >> 7) & 0x3) << 6) |
      (((inst >> 9) & 0xf) << 2);
    return `c.swsp ${reg(rs2)}, ${offset}`;
  }
  return '???';
}

function decodeCJOffset(inst: Unsafe) {
  const b = (bit: Unsafe) => (inst >> bit) & 1;
  const raw =
    (b(12) << 11) | (b(11) << 4) | (b(10) << 9) | (b(9) << 8) |
    (b(8) << 10) | (b(7) << 6) | (b(6) << 7) | (b(5) << 3) |
    (b(4) << 2) | (b(3) << 1) | (b(2) << 5);
  return signExtend(raw, 12);
}

function decodeCBOffset(inst: Unsafe) {
  const b = (bit: Unsafe) => (inst >> bit) & 1;
  const raw =
    (b(12) << 8) | (b(11) << 4) | (b(10) << 3) |
    (b(6) << 7) | (b(5) << 6) | (b(4) << 2) |
    (b(3) << 1) | (b(2) << 5);
  return signExtend(raw, 9);
}

// --- Instruction category classifier ---

// Classify a mnemonic into a rendering category for syntax coloring.
// Returns one of: 'arith', 'load', 'store', 'branch', 'jump', 'imm', 'sys', 'amo', or null.
export function classifyMnemonic(mn: Unsafe) {
  if (!mn || mn === '???' || mn === 'unimp') return null;

  // Handle compressed special forms before stripping prefix.
  if (mn === 'c.addi4spn' || mn === 'c.addi16sp') return 'imm';
  if (mn === 'c.lwsp') return 'load';
  if (mn === 'c.swsp') return 'store';
  if (mn === 'c.ebreak') return 'sys';

  const base = mn.startsWith('c.') ? mn.slice(2) : mn;

  if (/^(j|jal|jalr|jr|ret)$/.test(base)) return 'jump';
  if (/^(beqz?|bnez?|bltu?|bgeu?)$/.test(base)) return 'branch';
  if (/^(lb|lh|lw|lbu|lhu|flw)$/.test(base)) return 'load';
  if (/^(sb|sh|sw|fsw)$/.test(base)) return 'store';
  if (/^(ecall|ebreak|mret|sret|wfi)$/.test(base)) return 'sys';
  if (/^[sf]?fence/.test(base)) return 'sys';
  if (/^csr/.test(mn)) return 'sys';
  if (/^(lr\.|sc\.|amo)/.test(base)) return 'amo';
  if (/^(li|lui|auipc|nop|mv)$/.test(base)) return 'imm';

  return 'arith';
}

// --- Main disassembly entry point ---

export function disassembleRiscvLines(
  startAddress: Unsafe,
  lineCount: Unsafe,
  readMemory: Unsafe,
  options: Unsafe = {}
) {
  const count = Math.max(1, Math.min(4096, Number.parseInt(lineCount, 10) || 1));
  const addressSpace = Math.max(1, Number.parseInt(options.addressSpace, 10) || 0x100000000);
  const wide = addressSpace > 0x10000;
  const start = (Number(startAddress) >>> 0) % addressSpace;
  const highlightPc = options.highlightPc == null
    ? null
    : (Number(options.highlightPc) >>> 0) % addressSpace;
  const sourceMap = options.sourceMap || null;
  const structured = !!options.structured;

  // Fetch enough bytes for count instructions (max 4 bytes each) plus a small buffer.
  const fetchLen = (count * 4) + 4;
  const memory = typeof readMemory === 'function'
    ? readMemory(start, fetchLen)
    : new Uint8Array(0);

  const readByte = (addr: Unsafe) => {
    const normalized = (addr >>> 0) % addressSpace;
    const offset = (normalized - start + addressSpace) % addressSpace;
    if (memory instanceof Uint8Array && offset < memory.length) {
      return memory[offset];
    }
    return 0;
  };

  const readHalf = (addr: Unsafe) =>
    readByte(addr) | (readByte(addr + 1) << 8);

  const readWord = (addr: Unsafe) =>
    readByte(addr) | (readByte(addr + 1) << 8) |
    (readByte(addr + 2) << 16) | (readByte(addr + 3) << 24);

  let addr = start;
  const lines = [];
  let lastFn = null;
  let lastFile = null;
  let lastLine = null;

  for (let i = 0; i < count; i += 1) {
    // Insert source annotations when source map is available.
    if (sourceMap) {
      const info = sourceMap.lookup(addr);
      if (info) {
        // Emit function header when entering a new function.
        if (info.function && info.function !== lastFn) {
          const fileSuffix = info.file ? ` -- ${info.file}` : '';
          const headerText = `-- ${info.function}()${fileSuffix} --`;
          lines.push(structured ? { text: headerText, type: 'fn' } : headerText);
          lastFn = info.function;
        }
        // Emit source line when the line number changes.
        if (info.line != null && (info.file !== lastFile || info.line !== lastLine)) {
          if (info.source != null) {
            const srcText = `  ${info.line}: ${info.source}`;
            lines.push(structured ? { text: srcText, type: 'src' } : srcText);
          }
          lastFile = info.file;
          lastLine = info.line;
        }
      }
    }

    const half = readHalf(addr) & 0xffff;
    const isCompressed = (half & 0x3) !== 0x3;
    let mnemonic;
    let instHex;
    let instBytes;

    if (isCompressed) {
      mnemonic = decode16(half, addr);
      instHex = (half & 0xffff).toString(16).padStart(4, '0');
      instBytes = 2;
    } else {
      const word = readWord(addr) >>> 0;
      mnemonic = decode32(word, addr);
      instHex = (word >>> 0).toString(16).padStart(8, '0');
      instBytes = 4;
    }

    const marker = highlightPc != null && (highlightPc >>> 0) === (addr >>> 0) ? '>>' : '  ';
    const addrStr = formatAddr(addr, wide);
    const lineText = `${marker} ${addrStr}: ${instHex.padEnd(8, ' ')}  ${mnemonic}`;
    if (structured) {
      const mnName = mnemonic.split(/\s/)[0];
      lines.push({ text: lineText, type: 'asm', category: classifyMnemonic(mnName) });
    } else {
      lines.push(lineText);
    }
    addr = ((addr + instBytes) >>> 0) % addressSpace;
  }

  return lines;
}
