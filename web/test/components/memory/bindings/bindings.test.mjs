import test from 'node:test';
import assert from 'node:assert/strict';

import { bindMemoryBindings } from '../../../../app/components/memory/bindings/bindings.mjs';

function makeTarget() {
  return new EventTarget();
}

function makeDom() {
  return {
    memoryFollowPc: Object.assign(makeTarget(), { checked: false }),
    memoryRefreshBtn: makeTarget(),
    memoryDumpLoadBtn: makeTarget(),
    memoryDumpSaveBtn: makeTarget(),
    memorySnapshotSaveBtn: makeTarget(),
    memoryDumpLoadLastBtn: makeTarget(),
    loadKaratekaBtn: makeTarget(),
    memoryResetBtn: makeTarget(),
    memoryResetVector: makeTarget(),
    memoryDumpFile: makeTarget(),
    memoryWriteBtn: makeTarget(),
    memoryStatus: { textContent: '' },
    memoryWriteAddr: { value: '' },
    memoryWriteValue: { value: '' },
    memoryDumpOffset: { value: '' }
  };
}

test('bindMemoryBindings wires follow-pc change and supports cleanup', () => {
  const dom = makeDom();
  const calls = [];
  const runtime = { sim: null };
  const teardown = bindMemoryBindings({
    dom,
    runtime,
    apple2: {
      refreshMemoryView: () => calls.push(['refreshMemoryView']),
      setMemoryDumpStatus: () => calls.push(['setMemoryDumpStatus']),
      loadDumpOrSnapshotFile: async () => {},
      saveMemoryDump: async () => {},
      saveMemorySnapshot: async () => {},
      loadLastSavedDump: async () => {},
      loadKaratekaDump: async () => {},
      resetWithMemoryVectorOverride: async () => {},
      refreshScreen: () => {},
      isUiEnabled: () => false
    },
    store: {
      setMemoryFollowPcState: (value) => calls.push(['setFollowPc', value])
    },
    util: {
      isSnapshotFileName: () => false,
      parseHexOrDec: () => -1,
      hexByte: () => '00'
    },
    scheduleReduxUxSync: (reason) => calls.push(['sync', reason])
  });

  dom.memoryFollowPc.checked = true;
  dom.memoryFollowPc.dispatchEvent(new Event('change'));

  assert.deepEqual(calls, [
    ['setFollowPc', true],
    ['refreshMemoryView'],
    ['sync', 'memoryFollowPc']
  ]);

  teardown();
  dom.memoryFollowPc.checked = false;
  dom.memoryFollowPc.dispatchEvent(new Event('change'));
  assert.equal(calls.length, 3);
});
