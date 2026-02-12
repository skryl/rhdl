import {
  buildApple2SnapshotPayload,
  parseApple2SnapshotText,
  isSnapshotFileName
} from '../lib/snapshot.mjs';
import { hexWord } from '../../../core/lib/numeric_utils.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2DumpWorkflowService requires function: ${name}`);
  }
}

export function createApple2DumpWorkflowService({
  dom,
  state,
  runtime,
  APPLE2_RAM_BYTES,
  KARATEKA_PC,
  dumpStorageService,
  downloadService,
  romResetService,
  getApple2ProgramCounter,
  ensureApple2Ready,
  setMemoryDumpStatus,
  setMemoryResetVectorInput,
  loadApple2MemoryDumpBytes,
  log,
  fetchImpl = globalThis.fetch,
  fixtureRoot = './assets/fixtures/apple2'
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2DumpWorkflowService requires dom/state/runtime');
  }
  const defaultRamBytes = Number.isFinite(APPLE2_RAM_BYTES) && APPLE2_RAM_BYTES > 0
    ? APPLE2_RAM_BYTES
    : 0x10000;
  if (!dumpStorageService || typeof dumpStorageService.save !== 'function' || typeof dumpStorageService.load !== 'function') {
    throw new Error('createApple2DumpWorkflowService requires dumpStorageService');
  }
  if (!downloadService || typeof downloadService.downloadMemoryDump !== 'function' || typeof downloadService.downloadSnapshot !== 'function') {
    throw new Error('createApple2DumpWorkflowService requires downloadService');
  }
  if (!romResetService || typeof romResetService.applySnapshotStartPc !== 'function') {
    throw new Error('createApple2DumpWorkflowService requires romResetService');
  }
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('ensureApple2Ready', ensureApple2Ready);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('setMemoryResetVectorInput', setMemoryResetVectorInput);
  requireFn('loadApple2MemoryDumpBytes', loadApple2MemoryDumpBytes);
  requireFn('log', log);
  requireFn('fetchImpl', fetchImpl);

  function currentRunnerId() {
    return String(state.runnerPreset || 'apple2');
  }

  function currentMemoryConfig() {
    return state.apple2?.ioConfig?.memory || {};
  }

  function dumpWindowConfig() {
    const memoryCfg = currentMemoryConfig();
    const dumpStart = Math.max(0, Number.parseInt(memoryCfg.dumpStart, 10) || 0);
    const dumpLength = Math.max(1, Number.parseInt(memoryCfg.dumpLength, 10) || defaultRamBytes);
    const dumpReadMapped = memoryCfg.dumpReadMapped !== false;
    return { dumpStart, dumpLength, dumpReadMapped };
  }

  function readDumpWindowBytes() {
    const { dumpStart, dumpLength, dumpReadMapped } = dumpWindowConfig();
    if (typeof runtime.sim.memory_read === 'function') {
      return {
        bytes: runtime.sim.memory_read(dumpStart, dumpLength, { mapped: dumpReadMapped }),
        dumpStart
      };
    }
    return { bytes: new Uint8Array(0), dumpStart };
  }

  async function saveApple2MemoryDump() {
    if (!ensureApple2Ready()) {
      return false;
    }

    const { bytes, dumpStart } = readDumpWindowBytes();
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      setMemoryDumpStatus('Save failed: RAM read returned no data.');
      return false;
    }

    const now = new Date();
    const nowIso = now.toISOString();
    const startPc = getApple2ProgramCounter();
    const stamp = nowIso.replace(/[:.]/g, '-');
    const runnerId = currentRunnerId();
    const filename = `${runnerId}_dump_${stamp}.bin`;
    downloadService.downloadMemoryDump(bytes, filename);

    const label = `${runnerId} ram snapshot ${nowIso}`;
    state.memory.lastSavedDump = {
      bytes: new Uint8Array(bytes),
      offset: dumpStart,
      label,
      savedAtIso: nowIso,
      startPc
    };

    const persisted = dumpStorageService.save(
      bytes,
      dumpStart,
      label,
      nowIso,
      startPc
    );
    const msg = persisted
      ? `Saved dump ${filename} (${bytes.length} bytes). Last dump updated.`
      : `Saved dump ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
  }

  async function saveApple2MemorySnapshot() {
    if (!ensureApple2Ready()) {
      return false;
    }

    const { bytes, dumpStart } = readDumpWindowBytes();
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      setMemoryDumpStatus('Snapshot failed: RAM read returned no data.');
      return false;
    }

    const nowIso = new Date().toISOString();
    const startPc = getApple2ProgramCounter();
    const runnerId = currentRunnerId();
    const label = `${runnerId} ram snapshot ${nowIso}`;
    const snapshot = buildApple2SnapshotPayload(bytes, dumpStart, label, nowIso, startPc, {
      kind: 'rhdl.memory.snapshot'
    });
    if (!snapshot) {
      setMemoryDumpStatus('Snapshot failed: could not encode payload.');
      return false;
    }

    const stamp = nowIso.replace(/[:.]/g, '-');
    const filename = `${runnerId}_snapshot_${stamp}.rhdlsnap`;
    downloadService.downloadSnapshot(snapshot, filename);

    state.memory.lastSavedDump = {
      bytes: new Uint8Array(bytes),
      offset: dumpStart,
      label,
      savedAtIso: nowIso,
      startPc
    };

    const persisted = dumpStorageService.save(bytes, dumpStart, label, nowIso, startPc);
    const msg = persisted
      ? `Downloaded snapshot ${filename} (${bytes.length} bytes). Last dump updated.`
      : `Downloaded snapshot ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
  }

  function basenameFromPath(pathValue) {
    const token = String(pathValue || '').trim().replace(/\\/g, '/');
    if (!token) {
      return 'asset dump';
    }
    const parts = token.split('/').filter(Boolean);
    return parts[parts.length - 1] || token;
  }

  async function loadApple2Snapshot(snapshot) {
    if (!snapshot) {
      return false;
    }

    if (dom.memoryDumpOffset) {
      dom.memoryDumpOffset.value = `0x${hexWord(snapshot.offset)}`;
    }

    let pcStatus = null;
    let resetAfterLoad = false;
    if (snapshot.startPc != null) {
      pcStatus = await romResetService.applySnapshotStartPc(snapshot.startPc);
      resetAfterLoad = !!pcStatus.applied;
      if (pcStatus?.pc != null) {
        setMemoryResetVectorInput(pcStatus.pc);
      }
    }

    const suffix = snapshot.savedAtIso ? ` @ ${snapshot.savedAtIso}` : '';
    const pcSuffix = pcStatus?.pc != null ? ` (PC=$${hexWord(pcStatus.pc)})` : '';
    const loaded = await loadApple2MemoryDumpBytes(snapshot.bytes, snapshot.offset, {
      label: `${snapshot.label}${suffix}${pcSuffix}`,
      resetAfterLoad
    });

    if (loaded && pcStatus && !pcStatus.applied) {
      const warn = `Snapshot requested PC=$${hexWord(pcStatus.pc)} but could not apply it (${pcStatus.reason}).`;
      log(warn);
      if (dom.memoryDumpStatus) {
        dom.memoryDumpStatus.textContent = `${dom.memoryDumpStatus.textContent} ${warn}`;
      }
    }
    return loaded;
  }

  async function loadApple2DumpOrSnapshotFile(file, offsetRaw) {
    if (!file) {
      setMemoryDumpStatus('Select a dump/snapshot file first.');
      return false;
    }

    if (isSnapshotFileName(file.name)) {
      const snapshot = parseApple2SnapshotText(await file.text());
      if (!snapshot) {
        setMemoryDumpStatus(`Invalid snapshot file: ${file.name}`);
        return false;
      }
      return loadApple2Snapshot(snapshot);
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    return loadApple2MemoryDumpBytes(bytes, offsetRaw, { label: file.name });
  }

  async function loadApple2DumpOrSnapshotAssetPath(assetPath, offsetRaw) {
    const pathToken = String(assetPath || '').trim();
    if (!pathToken) {
      setMemoryDumpStatus('Select an asset path first.');
      return false;
    }

    try {
      const response = await fetchImpl(pathToken);
      if (!response?.ok) {
        const status = response ? response.status : 'n/a';
        throw new Error(`asset fetch failed (${status})`);
      }

      if (isSnapshotFileName(pathToken)) {
        const snapshot = parseApple2SnapshotText(await response.text());
        if (!snapshot) {
          setMemoryDumpStatus(`Invalid snapshot asset: ${pathToken}`);
          return false;
        }
        return loadApple2Snapshot(snapshot);
      }

      const bytes = new Uint8Array(await response.arrayBuffer());
      return loadApple2MemoryDumpBytes(bytes, offsetRaw, { label: basenameFromPath(pathToken) });
    } catch (err) {
      const msg = `Asset load failed (${pathToken}): ${err.message || err}`;
      setMemoryDumpStatus(msg);
      log(msg);
      return false;
    }
  }

  async function loadLastSavedApple2Dump() {
    if (!ensureApple2Ready()) {
      return false;
    }

    const saved = dumpStorageService.load();
    const source = saved || state.memory.lastSavedDump;
    if (!source) {
      setMemoryDumpStatus('No saved dump found.');
      return false;
    }

    if (dom.memoryDumpOffset) {
      dom.memoryDumpOffset.value = `0x${hexWord(source.offset)}`;
    }

    let pcStatus = null;
    let resetAfterLoad = false;
    if (source.startPc != null) {
      pcStatus = await romResetService.applySnapshotStartPc(source.startPc);
      resetAfterLoad = !!pcStatus.applied;
      if (pcStatus?.pc != null) {
        setMemoryResetVectorInput(pcStatus.pc);
      }
    }

    const suffix = source.savedAtIso ? ` @ ${source.savedAtIso}` : '';
    const pcSuffix = pcStatus?.pc != null ? ` (PC=$${hexWord(pcStatus.pc)})` : '';
    const loaded = await loadApple2MemoryDumpBytes(source.bytes, source.offset, {
      label: `${source.label}${suffix}${pcSuffix}`,
      resetAfterLoad
    });

    if (loaded && pcStatus && !pcStatus.applied) {
      const warn = `Saved dump requested PC=$${hexWord(pcStatus.pc)} but could not apply it (${pcStatus.reason}).`;
      log(warn);
      if (dom.memoryDumpStatus) {
        dom.memoryDumpStatus.textContent = `${dom.memoryDumpStatus.textContent} ${warn}`;
      }
    }
    return loaded;
  }

  async function loadKaratekaDump() {
    if (!ensureApple2Ready()) {
      return;
    }
    const runnerKind = typeof runtime.sim.runner_kind === 'function'
      ? runtime.sim.runner_kind()
      : runtime.sim.memory_mode?.();
    if (runnerKind !== 'apple2') {
      setMemoryDumpStatus('Karateka dump is only available for Apple II runner mode.');
      return;
    }

    try {
      const [romResp, dumpResp, metaResp] = await Promise.all([
        fetchImpl(`${fixtureRoot}/memory/appleiigo.rom`),
        fetchImpl(`${fixtureRoot}/memory/karateka_mem.bin`),
        fetchImpl(`${fixtureRoot}/memory/karateka_mem_meta.txt`)
      ]);

      if (!romResp.ok || !dumpResp.ok) {
        throw new Error(`asset fetch failed (rom=${romResp.status}, dump=${dumpResp.status})`);
      }

      let startPc = KARATEKA_PC;
      if (metaResp.ok) {
        const meta = await metaResp.text();
        const m = meta.match(/PC at dump:\s*\$([0-9A-Fa-f]+)/);
        if (m) {
          const parsedPc = Number.parseInt(m[1], 16);
          if (Number.isFinite(parsedPc)) {
            startPc = parsedPc & 0xffff;
          }
        }
      }

      const romBytes = new Uint8Array(await romResp.arrayBuffer());
      state.apple2.baseRomBytes = new Uint8Array(romBytes);
      const patchedRom = romResetService.patchApple2ResetVector(romBytes, startPc);
      const romLoaded = runtime.sim.runner_load_rom(patchedRom);
      if (!romLoaded) {
        throw new Error('runner_load_rom returned false');
      }
      setMemoryResetVectorInput(startPc);

      const dumpBytes = new Uint8Array(await dumpResp.arrayBuffer());
      await loadApple2MemoryDumpBytes(dumpBytes, 0, {
        resetAfterLoad: true,
        resetReleaseCycles: 0,
        label: `Karateka dump (PC=$${hexWord(startPc)})`
      });
    } catch (err) {
      const msg = `Karateka load failed: ${err.message || err}`;
      setMemoryDumpStatus(msg);
      log(msg);
    }
  }

  return {
    saveApple2MemoryDump,
    saveApple2MemorySnapshot,
    loadApple2DumpOrSnapshotFile,
    loadApple2DumpOrSnapshotAssetPath,
    loadLastSavedApple2Dump,
    loadKaratekaDump
  };
}
