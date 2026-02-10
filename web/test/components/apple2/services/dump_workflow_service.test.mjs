import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApple2SnapshotPayload } from '../../../../app/components/apple2/lib/snapshot.mjs';
import { createApple2DumpWorkflowService } from '../../../../app/components/apple2/services/dump_workflow_service.mjs';

test('apple2 dump workflow service saves memory dump and updates persisted state', async () => {
  let status = '';
  let download = null;
  const savedCalls = [];
  const state = { memory: {}, apple2: {} };
  const runtime = {
    sim: {
      memory_read: () => new Uint8Array([1, 2, 3, 4])
    }
  };
  const service = createApple2DumpWorkflowService({
    dom: {},
    state,
    runtime,
    APPLE2_RAM_BYTES: 64 * 1024,
    KARATEKA_PC: 0xB82A,
    dumpStorageService: {
      save: (...args) => {
        savedCalls.push(args);
        return true;
      },
      load: () => null
    },
    downloadService: {
      downloadMemoryDump: (_bytes, filename) => {
        download = filename;
      },
      downloadSnapshot: () => {}
    },
    romResetService: {
      applySnapshotStartPc: async () => ({ applied: false, reason: 'noop' }),
      patchApple2ResetVector: (bytes) => bytes
    },
    getApple2ProgramCounter: () => 0xB82A,
    ensureApple2Ready: () => true,
    setMemoryDumpStatus: (message) => {
      status = message;
    },
    setMemoryResetVectorInput: () => {},
    loadApple2MemoryDumpBytes: async () => true,
    log: () => {}
  });

  const ok = await service.saveApple2MemoryDump();
  assert.equal(ok, true);
  assert.match(download || '', /^apple2_dump_/);
  assert.equal(savedCalls.length, 1);
  assert.equal(state.memory.lastSavedDump.startPc, 0xB82A);
  assert.match(status, /Last dump updated/);
});

test('apple2 dump workflow service loads snapshot and applies start PC when available', async () => {
  const loaded = [];
  const dom = {
    memoryDumpOffset: { value: '' },
    memoryDumpStatus: { textContent: '' }
  };
  const snapshot = buildApple2SnapshotPayload(
    new Uint8Array([7, 8, 9]),
    0x2000,
    'snapshot',
    '2026-02-08T00:00:00.000Z',
    0xB82A
  );
  const service = createApple2DumpWorkflowService({
    dom,
    state: { memory: {}, apple2: {} },
    runtime: { sim: {} },
    APPLE2_RAM_BYTES: 64 * 1024,
    KARATEKA_PC: 0xB82A,
    dumpStorageService: { save: () => true, load: () => null },
    downloadService: { downloadMemoryDump: () => {}, downloadSnapshot: () => {} },
    romResetService: {
      applySnapshotStartPc: async () => ({ applied: true, pc: 0xB82A, reason: 'ok' }),
      patchApple2ResetVector: (bytes) => bytes
    },
    getApple2ProgramCounter: () => 0xB82A,
    ensureApple2Ready: () => true,
    setMemoryDumpStatus: () => {},
    setMemoryResetVectorInput: () => {},
    loadApple2MemoryDumpBytes: async (bytes, offset, opts) => {
      loaded.push({ bytes, offset, opts });
      return true;
    },
    log: () => {}
  });

  const ok = await service.loadApple2DumpOrSnapshotFile(
    {
      name: 'sample.rhdlsnap',
      text: async () => JSON.stringify(snapshot)
    },
    0
  );
  assert.equal(ok, true);
  assert.equal(dom.memoryDumpOffset.value, '0x2000');
  assert.equal(loaded.length, 1);
  assert.equal(loaded[0].offset, 0x2000);
  assert.equal(loaded[0].opts.resetAfterLoad, true);
});
