function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2RomResetService requires function: ${name}`);
  }
}

function patchApple2ResetVector(romBytes, pc) {
  const rom = new Uint8Array(romBytes);
  if (rom.length > 0x2FFD) {
    rom[0x2FFC] = pc & 0xff;
    rom[0x2FFD] = (pc >>> 8) & 0xff;
  }
  return rom;
}

export function createApple2RomResetService({
  state,
  runtime,
  currentRunnerPreset,
  fetchImpl = globalThis.fetch,
  parsePcLiteral,
  isApple2UiEnabled,
  fixtureRoot = './assets/fixtures/apple2'
} = {}) {
  if (!state || !runtime) {
    throw new Error('createApple2RomResetService requires state/runtime');
  }
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('fetchImpl', fetchImpl);
  requireFn('parsePcLiteral', parsePcLiteral);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);

  async function ensureBaseRomBytes() {
    if (state.apple2.baseRomBytes instanceof Uint8Array && state.apple2.baseRomBytes.length > 0) {
      return state.apple2.baseRomBytes;
    }

    const preset = currentRunnerPreset();
    const romPath = preset?.romPath || `${fixtureRoot}/appleiigo.rom`;

    try {
      const romResp = await fetchImpl(romPath);
      if (!romResp.ok) {
        return null;
      }
      const romBytes = new Uint8Array(await romResp.arrayBuffer());
      if (romBytes.length === 0) {
        return null;
      }
      state.apple2.baseRomBytes = new Uint8Array(romBytes);
      return state.apple2.baseRomBytes;
    } catch (_err) {
      return null;
    }
  }

  async function applySnapshotStartPc(startPc) {
    const pc = parsePcLiteral(startPc);
    if (pc == null) {
      return { applied: false, pc: null, reason: 'missing' };
    }
    if (!runtime.sim || !isApple2UiEnabled()) {
      return { applied: false, pc, reason: 'runner inactive' };
    }

    const baseRom = await ensureBaseRomBytes();
    if (!(baseRom instanceof Uint8Array) || baseRom.length === 0) {
      return { applied: false, pc, reason: 'rom unavailable' };
    }

    const patchedRom = patchApple2ResetVector(baseRom, pc);
    const ok = runtime.sim.apple2_load_rom(patchedRom);
    return { applied: !!ok, pc, reason: ok ? 'ok' : 'rom load failed' };
  }

  return {
    patchApple2ResetVector,
    ensureBaseRomBytes,
    applySnapshotStartPc
  };
}
