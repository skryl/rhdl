import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2RomResetService } from '../../../../app/components/apple2/services/rom_reset_service.mjs';

test('apple2 rom reset service patches reset vector and applies start PC', async () => {
  const state = { apple2: { baseRomBytes: null } };
  const loadedRoms = [];
  const runtime = {
    sim: {
      runner_load_rom(bytes) {
        loadedRoms.push(new Uint8Array(bytes));
        return true;
      }
    }
  };

  const baseRom = new Uint8Array(0x3000);
  const service = createApple2RomResetService({
    state,
    runtime,
    currentRunnerPreset: () => ({ romPath: './rom.bin' }),
    fetchImpl: async () => ({
      ok: true,
      async arrayBuffer() {
        return baseRom.buffer.slice(0);
      }
    }),
    parsePcLiteral: (value) => Number(value) & 0xffff,
    isApple2UiEnabled: () => true
  });

  const status = await service.applySnapshotStartPc(0xB82A);
  assert.equal(status.applied, true);
  assert.equal(status.pc, 0xB82A);
  assert.equal(loadedRoms.length, 1);
  assert.equal(loadedRoms[0][0x2FFC], 0x2A);
  assert.equal(loadedRoms[0][0x2FFD], 0xB8);
});
