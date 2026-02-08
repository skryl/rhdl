import { createListenerGroup } from './listener_bindings.mjs';

export function bindMemoryBindings({ dom, runtime, actions }) {
  const listeners = createListenerGroup();

  listeners.on(dom.memoryFollowPc, 'change', () => {
    actions.setMemoryFollowPcState(!!dom.memoryFollowPc.checked);
    actions.refreshMemoryView();
    actions.scheduleReduxUxSync('memoryFollowPc');
  });

  listeners.on(dom.memoryRefreshBtn, 'click', () => {
    actions.refreshMemoryView();
  });

  listeners.on(dom.memoryDumpLoadBtn, 'click', async () => {
    if (!runtime.sim || !actions.isApple2UiEnabled()) {
      actions.setMemoryDumpStatus('Load the Apple II runner first.');
      return;
    }

    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      actions.setMemoryDumpStatus('Select a dump/snapshot file first.');
      return;
    }

    const offsetRaw = dom.memoryDumpOffset?.value || '0';
    await actions.loadApple2DumpOrSnapshotFile(file, offsetRaw);
  });

  listeners.on(dom.memoryDumpSaveBtn, 'click', async () => {
    await actions.saveApple2MemoryDump();
  });

  listeners.on(dom.memorySnapshotSaveBtn, 'click', async () => {
    await actions.saveApple2MemorySnapshot();
  });

  listeners.on(dom.memoryDumpLoadLastBtn, 'click', async () => {
    await actions.loadLastSavedApple2Dump();
  });

  listeners.on(dom.loadKaratekaBtn, 'click', async () => {
    await actions.loadKaratekaDump();
  });

  listeners.on(dom.memoryResetBtn, 'click', async () => {
    actions.setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await actions.resetApple2WithMemoryVectorOverride();
  });

  listeners.on(dom.memoryResetVector, 'keydown', async (event) => {
    if (event.key !== 'Enter') {
      return;
    }
    event.preventDefault();
    actions.setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await actions.resetApple2WithMemoryVectorOverride();
  });

  listeners.on(dom.memoryDumpFile, 'change', () => {
    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      actions.setMemoryDumpStatus('');
      return;
    }
    const label = actions.isSnapshotFileName(file.name) ? 'snapshot' : 'dump';
    actions.setMemoryDumpStatus(`Selected ${label}: ${file.name} (${file.size} bytes)`);
  });

  listeners.on(dom.memoryWriteBtn, 'click', () => {
    if (!runtime.sim || !actions.isApple2UiEnabled()) {
      return;
    }

    const addr = actions.parseHexOrDec(dom.memoryWriteAddr?.value, -1);
    const value = actions.parseHexOrDec(dom.memoryWriteValue?.value, -1);
    if (addr < 0 || value < 0) {
      if (dom.memoryStatus) {
        dom.memoryStatus.textContent = 'Invalid address or value';
      }
      return;
    }

    const ok = runtime.sim.apple2_write_ram(addr, new Uint8Array([value & 0xff]));
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = ok
        ? `Wrote $${actions.hexByte(value & 0xff)} @ $${addr.toString(16).toUpperCase().padStart(4, '0')}`
        : 'Memory write failed';
    }
    actions.refreshMemoryView();
    actions.refreshApple2Screen();
    actions.scheduleReduxUxSync('memoryWrite');
  });

  return () => {
    listeners.dispose();
  };
}
