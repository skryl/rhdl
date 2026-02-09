import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

export function bindMemoryBindings({
  dom,
  runtime,
  apple2,
  store,
  util,
  scheduleReduxUxSync
}) {
  const listeners = createListenerGroup();

  listeners.on(dom.memoryFollowPc, 'change', () => {
    store.setMemoryFollowPcState(!!dom.memoryFollowPc.checked);
    apple2.refreshMemoryView();
    scheduleReduxUxSync('memoryFollowPc');
  });

  listeners.on(dom.memoryRefreshBtn, 'click', () => {
    apple2.refreshMemoryView();
  });

  listeners.on(dom.memoryDumpLoadBtn, 'click', async () => {
    if (!runtime.sim || !apple2.isUiEnabled()) {
      apple2.setMemoryDumpStatus('Load the Apple II runner first.');
      return;
    }

    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      apple2.setMemoryDumpStatus('Select a dump/snapshot file first.');
      return;
    }

    const offsetRaw = dom.memoryDumpOffset?.value || '0';
    await apple2.loadDumpOrSnapshotFile(file, offsetRaw);
  });

  listeners.on(dom.memoryDumpSaveBtn, 'click', async () => {
    await apple2.saveMemoryDump();
  });

  listeners.on(dom.memorySnapshotSaveBtn, 'click', async () => {
    await apple2.saveMemorySnapshot();
  });

  listeners.on(dom.memoryDumpLoadLastBtn, 'click', async () => {
    await apple2.loadLastSavedDump();
  });

  listeners.on(dom.loadKaratekaBtn, 'click', async () => {
    await apple2.loadKaratekaDump();
  });

  listeners.on(dom.memoryResetBtn, 'click', async () => {
    apple2.setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await apple2.resetWithMemoryVectorOverride();
  });

  listeners.on(dom.memoryResetVector, 'keydown', async (event) => {
    if (event.key !== 'Enter') {
      return;
    }
    event.preventDefault();
    apple2.setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await apple2.resetWithMemoryVectorOverride();
  });

  listeners.on(dom.memoryDumpFile, 'change', () => {
    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      apple2.setMemoryDumpStatus('');
      return;
    }
    const label = util.isSnapshotFileName(file.name) ? 'snapshot' : 'dump';
    apple2.setMemoryDumpStatus(`Selected ${label}: ${file.name} (${file.size} bytes)`);
  });

  listeners.on(dom.memoryWriteBtn, 'click', () => {
    if (!runtime.sim || !apple2.isUiEnabled()) {
      return;
    }

    const addr = util.parseHexOrDec(dom.memoryWriteAddr?.value, -1);
    const value = util.parseHexOrDec(dom.memoryWriteValue?.value, -1);
    if (addr < 0 || value < 0) {
      if (dom.memoryStatus) {
        dom.memoryStatus.textContent = 'Invalid address or value';
      }
      return;
    }

    const ok = runtime.sim.apple2_write_ram(addr, new Uint8Array([value & 0xff]));
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = ok
        ? `Wrote $${util.hexByte(value & 0xff)} @ $${addr.toString(16).toUpperCase().padStart(4, '0')}`
        : 'Memory write failed';
    }
    apple2.refreshMemoryView();
    apple2.refreshScreen();
    scheduleReduxUxSync('memoryWrite');
  });

  return () => {
    listeners.dispose();
  };
}
