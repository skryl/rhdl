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
    memoryDumpAssetTree: makeTarget(),
    memoryDumpAssetPath: Object.assign(makeTarget(), { value: '' }),
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

async function dispatchAndDrain(target, type) {
  target.dispatchEvent(new Event(type));
  await Promise.resolve();
  await Promise.resolve();
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

test('bindMemoryBindings loads selected local dump file when clicking load', async () => {
  const dom = makeDom();
  const selectedFile = { name: 'sample.bin', size: 3 };
  dom.memoryDumpFile.files = [selectedFile];
  dom.memoryDumpOffset.value = '0x1000';

  const calls = [];
  bindMemoryBindings({
    dom,
    runtime: { sim: {} },
    apple2: {
      refreshMemoryView: () => {},
      setMemoryDumpStatus: (msg) => calls.push(['status', msg]),
      loadDumpOrSnapshotFile: async (file, offsetRaw) => calls.push(['file', file, offsetRaw]),
      loadDumpOrSnapshotAssetPath: async (assetPath, offsetRaw) => calls.push(['asset', assetPath, offsetRaw]),
      saveMemoryDump: async () => {},
      saveMemorySnapshot: async () => {},
      loadLastSavedDump: async () => {},
      loadKaratekaDump: async () => {},
      resetWithMemoryVectorOverride: async () => {},
      refreshScreen: () => {},
      isUiEnabled: () => true
    },
    store: {
      setMemoryFollowPcState: () => {}
    },
    util: {
      isSnapshotFileName: () => false,
      parseHexOrDec: () => -1,
      hexByte: () => '00'
    },
    scheduleReduxUxSync: () => {}
  });

  await dispatchAndDrain(dom.memoryDumpLoadBtn, 'click');
  assert.deepEqual(calls, [['file', selectedFile, '0x1000']]);
});

test('bindMemoryBindings loads selected dump asset path when no local file is selected', async () => {
  const dom = makeDom();
  dom.memoryDumpFile.files = [];
  dom.memoryDumpAssetPath.value = './assets/fixtures/cpu/software/conway_glider_80x24.bin';
  dom.memoryDumpOffset.value = '0x0000';

  const calls = [];
  bindMemoryBindings({
    dom,
    runtime: { sim: {} },
    apple2: {
      refreshMemoryView: () => {},
      setMemoryDumpStatus: (msg) => calls.push(['status', msg]),
      loadDumpOrSnapshotFile: async (file, offsetRaw) => calls.push(['file', file, offsetRaw]),
      loadDumpOrSnapshotAssetPath: async (assetPath, offsetRaw) => calls.push(['asset', assetPath, offsetRaw]),
      saveMemoryDump: async () => {},
      saveMemorySnapshot: async () => {},
      loadLastSavedDump: async () => {},
      loadKaratekaDump: async () => {},
      resetWithMemoryVectorOverride: async () => {},
      refreshScreen: () => {},
      isUiEnabled: () => true
    },
    store: {
      setMemoryFollowPcState: () => {}
    },
    util: {
      isSnapshotFileName: () => false,
      parseHexOrDec: () => -1,
      hexByte: () => '00'
    },
    scheduleReduxUxSync: () => {}
  });

  await dispatchAndDrain(dom.memoryDumpLoadBtn, 'click');
  assert.deepEqual(calls, [['asset', './assets/fixtures/cpu/software/conway_glider_80x24.bin', '0x0000']]);
});

test('bindMemoryBindings reports missing selection when neither local file nor asset path is set', async () => {
  const dom = makeDom();
  dom.memoryDumpFile.files = [];
  dom.memoryDumpAssetPath.value = '';

  const calls = [];
  bindMemoryBindings({
    dom,
    runtime: { sim: {} },
    apple2: {
      refreshMemoryView: () => {},
      setMemoryDumpStatus: (msg) => calls.push(msg),
      loadDumpOrSnapshotFile: async () => {},
      loadDumpOrSnapshotAssetPath: async () => {},
      saveMemoryDump: async () => {},
      saveMemorySnapshot: async () => {},
      loadLastSavedDump: async () => {},
      loadKaratekaDump: async () => {},
      resetWithMemoryVectorOverride: async () => {},
      refreshScreen: () => {},
      isUiEnabled: () => true
    },
    store: {
      setMemoryFollowPcState: () => {}
    },
    util: {
      isSnapshotFileName: () => false,
      parseHexOrDec: () => -1,
      hexByte: () => '00'
    },
    scheduleReduxUxSync: () => {}
  });

  await dispatchAndDrain(dom.memoryDumpLoadBtn, 'click');
  assert.deepEqual(calls, ['Select a dump/snapshot file first.']);
});
