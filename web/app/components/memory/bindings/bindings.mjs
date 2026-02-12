import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';
import { GENERATED_MEMORY_DUMP_ASSET_FILES } from '../config/generated_dump_assets.mjs';
import { createDumpAssetTree, isDumpAssetPath, normalizeDumpAssetPath } from '../lib/dump_assets.mjs';

function updateSelectedAssetButton(container, selectedPath) {
  if (!container || typeof container.querySelectorAll !== 'function') {
    return;
  }
  const normalized = normalizeDumpAssetPath(selectedPath);
  const buttons = container.querySelectorAll('button[data-asset-path]');
  buttons.forEach((button) => {
    const buttonPath = normalizeDumpAssetPath(button.dataset?.assetPath || '');
    button.classList.toggle('selected', !!normalized && buttonPath === normalized);
  });
}

function renderDumpAssetTree(container, paths) {
  if (!container || typeof container.replaceChildren !== 'function') {
    return;
  }

  const documentRef = container.ownerDocument || globalThis.document;
  if (!documentRef || typeof documentRef.createElement !== 'function') {
    return;
  }

  const tree = createDumpAssetTree(paths);
  const rootList = documentRef.createElement('ul');
  rootList.className = 'memory-dump-tree-root';

  const appendNode = (listElement, node) => {
    for (const dir of node.dirs) {
      const dirItem = documentRef.createElement('li');
      dirItem.className = 'memory-dump-tree-dir';
      const details = documentRef.createElement('details');
      details.open = true;
      const summary = documentRef.createElement('summary');
      summary.textContent = dir.name;
      details.append(summary);

      const childList = documentRef.createElement('ul');
      childList.className = 'memory-dump-tree-branch';
      appendNode(childList, dir);
      details.append(childList);
      dirItem.append(details);
      listElement.append(dirItem);
    }

    for (const file of node.files) {
      const fileItem = documentRef.createElement('li');
      fileItem.className = 'memory-dump-tree-file-item';
      const fileButton = documentRef.createElement('button');
      fileButton.type = 'button';
      fileButton.className = 'memory-dump-tree-file';
      fileButton.textContent = file.name;
      fileButton.dataset.assetPath = file.path;
      fileButton.title = file.path;
      fileItem.append(fileButton);
      listElement.append(fileItem);
    }
  };

  appendNode(rootList, tree);

  if (rootList.childElementCount === 0) {
    const empty = documentRef.createElement('p');
    empty.className = 'status';
    empty.textContent = 'No dump assets found under ./assets.';
    container.replaceChildren(empty);
    return;
  }

  container.replaceChildren(rootList);
}

export function bindMemoryBindings({
  dom,
  runtime,
  apple2,
  store,
  util,
  scheduleReduxUxSync
}) {
  const listeners = createListenerGroup();

  renderDumpAssetTree(dom.memoryDumpAssetTree, GENERATED_MEMORY_DUMP_ASSET_FILES);
  updateSelectedAssetButton(dom.memoryDumpAssetTree, dom.memoryDumpAssetPath?.value || '');

  listeners.on(dom.memoryFollowPc, 'change', () => {
    store.setMemoryFollowPcState(!!dom.memoryFollowPc.checked);
    apple2.refreshMemoryView();
    scheduleReduxUxSync('memoryFollowPc');
  });

  listeners.on(dom.memoryRefreshBtn, 'click', () => {
    apple2.refreshMemoryView();
  });

  listeners.on(dom.memoryDumpAssetTree, 'click', (event) => {
    const target = event?.target;
    if (!target || typeof target.closest !== 'function') {
      return;
    }
    const button = target.closest('button[data-asset-path]');
    if (!button || typeof button.getAttribute !== 'function') {
      return;
    }
    const assetPath = normalizeDumpAssetPath(button.dataset?.assetPath || '');
    if (!assetPath) {
      return;
    }

    if (dom.memoryDumpAssetPath) {
      dom.memoryDumpAssetPath.value = assetPath;
    }
    if (dom.memoryDumpFile && typeof dom.memoryDumpFile.value === 'string') {
      dom.memoryDumpFile.value = '';
    }
    updateSelectedAssetButton(dom.memoryDumpAssetTree, assetPath);
    const label = util.isSnapshotFileName(assetPath) ? 'snapshot' : 'dump';
    apple2.setMemoryDumpStatus(`Selected asset ${label}: ${assetPath}`);
  });

  listeners.on(dom.memoryDumpAssetPath, 'input', () => {
    const assetPath = normalizeDumpAssetPath(dom.memoryDumpAssetPath?.value || '');
    updateSelectedAssetButton(dom.memoryDumpAssetTree, assetPath);
  });

  listeners.on(dom.memoryDumpLoadBtn, 'click', async () => {
    if (!runtime.sim || !apple2.isUiEnabled()) {
      apple2.setMemoryDumpStatus('Load a runner with memory + I/O support first.');
      return;
    }

    const offsetRaw = dom.memoryDumpOffset?.value || '0';
    const localFile = dom.memoryDumpFile?.files?.[0];
    if (localFile) {
      await apple2.loadDumpOrSnapshotFile(localFile, offsetRaw);
      return;
    }

    const assetPath = normalizeDumpAssetPath(dom.memoryDumpAssetPath?.value || '');
    if (!assetPath) {
      apple2.setMemoryDumpStatus('Select a dump/snapshot file first.');
      return;
    }
    if (!isDumpAssetPath(assetPath)) {
      apple2.setMemoryDumpStatus(`Invalid asset path: ${assetPath}`);
      return;
    }
    if (typeof apple2.loadDumpOrSnapshotAssetPath !== 'function') {
      apple2.setMemoryDumpStatus('Asset loading is unavailable in this runner mode.');
      return;
    }

    await apple2.loadDumpOrSnapshotAssetPath(assetPath, offsetRaw);
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
      if (!normalizeDumpAssetPath(dom.memoryDumpAssetPath?.value || '')) {
        apple2.setMemoryDumpStatus('');
      }
      return;
    }
    if (dom.memoryDumpAssetPath) {
      dom.memoryDumpAssetPath.value = '';
    }
    updateSelectedAssetButton(dom.memoryDumpAssetTree, '');
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

    let ok = false;
    if (typeof runtime.sim.memory_write_byte === 'function') {
      ok = runtime.sim.memory_write_byte(addr, value & 0xff, { mapped: true });
    } else if (typeof runtime.sim.memory_write === 'function') {
      ok = runtime.sim.memory_write(addr, new Uint8Array([value & 0xff]), { mapped: true });
    }
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
