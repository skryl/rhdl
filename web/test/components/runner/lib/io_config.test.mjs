import test from 'node:test';
import assert from 'node:assert/strict';

import { resolveRunnerIoConfig } from '../../../../app/components/runner/lib/io_config.mjs';

test('resolveRunnerIoConfig falls back to legacy Apple II mapping', () => {
  const config = resolveRunnerIoConfig({
    enableApple2Ui: true,
    romPath: '/roms/apple2.rom'
  });

  assert.equal(config.enabled, true);
  assert.equal(config.api, 'apple2');
  assert.equal(config.display.mode, 'apple2');
  assert.equal(config.keyboard.mode, 'apple2_special');
  assert.equal(config.memory.dumpLength, 48 * 1024);
  assert.equal(config.rom.path, '/roms/apple2.rom');
});

test('resolveRunnerIoConfig normalizes memory-mapped runner config', () => {
  const config = resolveRunnerIoConfig({
    io: {
      enabled: true,
      api: 'memory',
      memory: {
        dumpStart: 0x200,
        dumpLength: 0x400,
        addressSpace: 0x10000,
        viewMapped: true,
        dumpReadMapped: true,
        directWriteMapped: true
      },
      display: {
        enabled: true,
        mode: 'text',
        text: {
          start: 0x400,
          width: 32,
          height: 16,
          rowStride: 32,
          rowLayout: 'linear'
        }
      },
      keyboard: {
        enabled: true,
        mode: 'memory_mapped',
        dataAddr: 0xFF00,
        strobeAddr: 0xFF02,
        strobeValue: 1
      },
      sound: {
        enabled: true,
        mode: 'memory_mapped',
        addr: 0xFF10,
        mask: 1
      },
      pcSignalCandidates: ['pc_out', 'cpu_pc'],
      watchSignals: ['pc_debug', 'speaker']
    }
  });

  assert.equal(config.enabled, true);
  assert.equal(config.api, 'memory');
  assert.equal(config.display.mode, 'text');
  assert.equal(config.keyboard.dataAddr, 0xFF00);
  assert.equal(config.sound.addr, 0xFF10);
  assert.deepEqual(config.pcSignalCandidates, ['pc_out', 'cpu_pc']);
  assert.deepEqual(config.watchSignals, ['pc_debug', 'speaker']);
});

test('resolveRunnerIoConfig preserves 32-bit full address space for riscv-style memory maps', () => {
  const config = resolveRunnerIoConfig({
    io: {
      enabled: true,
      api: 'generic',
      memory: {
        dumpStart: 0x80000000,
        dumpLength: 1024,
        addressSpace: 0x100000000
      }
    }
  });

  assert.equal(config.memory.dumpStart, 0x80000000);
  assert.equal(config.memory.addressSpace, 0x100000000);
});
