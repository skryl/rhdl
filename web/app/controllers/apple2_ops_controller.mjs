import {
  buildApple2SnapshotPayload,
  parseApple2SnapshotPayload,
  parseApple2SnapshotText,
  isSnapshotFileName,
  parsePcLiteral
} from '../lib/apple2_snapshot.mjs';
import { parseHexOrDec, hexWord } from '../lib/numeric_utils.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2OpsController requires function: ${name}`);
  }
}

export function createApple2OpsController({
  dom,
  state,
  runtime,
  APPLE2_RAM_BYTES,
  KARATEKA_PC,
  LAST_APPLE2_DUMP_KEY,
  setApple2SoundEnabledState,
  setMemoryFollowPcState,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  refreshWatchTable,
  refreshStatus,
  getApple2ProgramCounter,
  currentRunnerPreset,
  log,
  fetchImpl = globalThis.fetch,
  windowRef = globalThis.window,
  documentRef = globalThis.document
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2OpsController requires dom/state/runtime');
  }
  requireFn('setApple2SoundEnabledState', setApple2SoundEnabledState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshStatus', refreshStatus);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('log', log);
  requireFn('fetchImpl', fetchImpl);

  function isApple2UiEnabled() {
    return state.apple2.enabled && runtime.sim?.apple2_mode?.();
  }
  
  function updateIoToggleUi() {
    const active = isApple2UiEnabled();
    if (dom.toggleHires) {
      dom.toggleHires.checked = !!state.apple2.displayHires;
      dom.toggleHires.disabled = !active;
    }
    if (dom.toggleColor) {
      dom.toggleColor.checked = !!state.apple2.displayColor;
      dom.toggleColor.disabled = !active || !state.apple2.displayHires;
    }
    if (dom.toggleSound) {
      dom.toggleSound.checked = !!state.apple2.soundEnabled;
      dom.toggleSound.disabled = !active;
    }
    if (dom.apple2TextScreen) {
      dom.apple2TextScreen.hidden = active && state.apple2.displayHires;
    }
    if (dom.apple2HiresCanvas) {
      dom.apple2HiresCanvas.hidden = !(active && state.apple2.displayHires);
    }
  }
  
  function apple2HiresLineAddress(row) {
    const section = Math.floor(row / 64);
    const rowInSection = row % 64;
    const group = Math.floor(rowInSection / 8);
    const lineInGroup = rowInSection % 8;
    return 0x2000 + (lineInGroup * 0x400) + (group * 0x80) + (section * 0x28);
  }
  
  function ensureApple2AudioGraph() {
    if (state.apple2.audioCtx && state.apple2.audioOsc && state.apple2.audioGain) {
      return true;
    }
  
    const AudioCtx = windowRef.AudioContext || windowRef.webkitAudioContext;
    if (!AudioCtx) {
      return false;
    }
  
    const ctx = new AudioCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
  
    osc.type = 'square';
    osc.frequency.value = 440;
    gain.gain.value = 0;
  
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
  
    state.apple2.audioCtx = ctx;
    state.apple2.audioOsc = osc;
    state.apple2.audioGain = gain;
    return true;
  }
  
  async function setApple2SoundEnabled(enabled) {
    setApple2SoundEnabledState(!!enabled);
    updateIoToggleUi();
  
    if (!state.apple2.soundEnabled) {
      if (state.apple2.audioCtx && state.apple2.audioGain) {
        state.apple2.audioGain.gain.setTargetAtTime(0, state.apple2.audioCtx.currentTime, 0.01);
      }
      return;
    }
  
    if (!ensureApple2AudioGraph()) {
      setApple2SoundEnabledState(false);
      updateIoToggleUi();
      log('WebAudio unavailable: SOUND toggle disabled');
      return;
    }
  
    try {
      await state.apple2.audioCtx.resume();
    } catch (err) {
      setApple2SoundEnabledState(false);
      updateIoToggleUi();
      log(`Failed to enable audio: ${err.message || err}`);
    }
  }
  
  function updateApple2SpeakerAudio(toggles, cyclesRun) {
    if (!state.apple2.soundEnabled) {
      return;
    }
    if (!state.apple2.audioCtx || !state.apple2.audioOsc || !state.apple2.audioGain) {
      return;
    }
  
    const ctx = state.apple2.audioCtx;
    const gain = state.apple2.audioGain.gain;
    const freq = state.apple2.audioOsc.frequency;
  
    if (!toggles || !cyclesRun) {
      gain.setTargetAtTime(0, ctx.currentTime, 0.012);
      return;
    }
  
    const hz = (toggles * 1_000_000) / (2 * Math.max(1, cyclesRun));
    const clampedHz = Math.max(40, Math.min(6000, hz));
    freq.setTargetAtTime(clampedHz, ctx.currentTime, 0.006);
    gain.setTargetAtTime(0.03, ctx.currentTime, 0.005);
  }
  
  function setMemoryDumpStatus(message) {
    if (dom.memoryDumpStatus) {
      dom.memoryDumpStatus.textContent = message || '';
    }
  }
  
  function setMemoryResetVectorInput(value) {
    if (!dom.memoryResetVector) {
      return;
    }
    const parsed = parsePcLiteral(value);
    dom.memoryResetVector.value = parsed == null ? '' : `0x${hexWord(parsed)}`;
  }
  
  function saveLastMemoryDumpToStorage(bytes, offset = 0, label = 'saved dump', savedAtIso = null, startPc = null) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    try {
      const payload = buildApple2SnapshotPayload(bytes, offset, label, savedAtIso, startPc);
      if (!payload) {
        return false;
      }
      windowRef.localStorage.setItem(LAST_APPLE2_DUMP_KEY, JSON.stringify(payload));
      return true;
    } catch (err) {
      log(`Could not persist last memory dump: ${err.message || err}`);
      return false;
    }
  }
  
  function loadLastMemoryDumpFromStorage() {
    try {
      const raw = windowRef.localStorage.getItem(LAST_APPLE2_DUMP_KEY);
      if (!raw) {
        return null;
      }
      return parseApple2SnapshotPayload(JSON.parse(raw));
    } catch (err) {
      log(`Could not read last memory dump: ${err.message || err}`);
      return null;
    }
  }
  
  function triggerDownload(blob, filename) {
    if (!blob || !filename) {
      return;
    }
    const url = windowRef.URL.createObjectURL(blob);
    const a = documentRef.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    windowRef.URL.revokeObjectURL(url);
  }
  
  function downloadMemoryDump(bytes, filename) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return;
    }
    triggerDownload(new Blob([bytes], { type: 'application/octet-stream' }), filename);
  }
  
  function downloadApple2Snapshot(snapshot, filename) {
    if (!snapshot || typeof snapshot !== 'object') {
      return;
    }
    const encoded = JSON.stringify(snapshot, null, 2);
    triggerDownload(new Blob([encoded], { type: 'application/json' }), filename);
  }
  
  async function saveApple2MemoryDump() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return false;
    }
  
    const bytes = runtime.sim.apple2_read_ram(0, APPLE2_RAM_BYTES);
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      setMemoryDumpStatus('Save failed: RAM read returned no data.');
      return false;
    }
  
    const now = new Date();
    const nowIso = now.toISOString();
    const startPc = getApple2ProgramCounter();
    const stamp = nowIso.replace(/[:.]/g, '-');
    const filename = `apple2_dump_${stamp}.bin`;
    downloadMemoryDump(bytes, filename);
  
    state.memory.lastSavedDump = {
      bytes: new Uint8Array(bytes),
      offset: 0,
      label: `apple2 ram snapshot ${nowIso}`,
      savedAtIso: nowIso,
      startPc
    };
  
    const persisted = saveLastMemoryDumpToStorage(bytes, 0, `apple2 ram snapshot ${nowIso}`, nowIso, startPc);
    const msg = persisted
      ? `Saved dump ${filename} (${bytes.length} bytes). Last dump updated.`
      : `Saved dump ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
  }
  
  async function saveApple2MemorySnapshot() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return false;
    }
  
    const bytes = runtime.sim.apple2_read_ram(0, APPLE2_RAM_BYTES);
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      setMemoryDumpStatus('Snapshot failed: RAM read returned no data.');
      return false;
    }
  
    const nowIso = new Date().toISOString();
    const startPc = getApple2ProgramCounter();
    const label = `apple2 ram snapshot ${nowIso}`;
    const snapshot = buildApple2SnapshotPayload(bytes, 0, label, nowIso, startPc);
    if (!snapshot) {
      setMemoryDumpStatus('Snapshot failed: could not encode payload.');
      return false;
    }
  
    const stamp = nowIso.replace(/[:.]/g, '-');
    const filename = `apple2_snapshot_${stamp}.rhdlsnap`;
    downloadApple2Snapshot(snapshot, filename);
  
    state.memory.lastSavedDump = {
      bytes: new Uint8Array(bytes),
      offset: 0,
      label,
      savedAtIso: nowIso,
      startPc
    };
  
    const persisted = saveLastMemoryDumpToStorage(bytes, 0, label, nowIso, startPc);
    const msg = persisted
      ? `Downloaded snapshot ${filename} (${bytes.length} bytes). Last dump updated.`
      : `Downloaded snapshot ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
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
      if (dom.memoryDumpOffset) {
        dom.memoryDumpOffset.value = `0x${hexWord(snapshot.offset)}`;
      }
  
      let pcStatus = null;
      let resetAfterLoad = false;
      if (snapshot.startPc != null) {
        pcStatus = await applyApple2SnapshotStartPc(snapshot.startPc);
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
  
    const bytes = new Uint8Array(await file.arrayBuffer());
    return loadApple2MemoryDumpBytes(bytes, offsetRaw, { label: file.name });
  }
  
  async function loadLastSavedApple2Dump() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return false;
    }
  
    const saved = loadLastMemoryDumpFromStorage();
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
      pcStatus = await applyApple2SnapshotStartPc(source.startPc);
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
  
  function fitApple2RamWindow(bytes, offset) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return { data: new Uint8Array(0), trimmed: false };
    }
    const off = Math.max(0, Math.trunc(offset));
    if (off >= APPLE2_RAM_BYTES) {
      return { data: new Uint8Array(0), trimmed: true };
    }
    const maxLen = APPLE2_RAM_BYTES - off;
    if (bytes.length <= maxLen) {
      return { data: bytes, trimmed: false };
    }
    return { data: bytes.subarray(0, maxLen), trimmed: true };
  }
  
  function patchApple2ResetVector(romBytes, pc) {
    const rom = new Uint8Array(romBytes);
    if (rom.length > 0x2FFD) {
      rom[0x2FFC] = pc & 0xff;
      rom[0x2FFD] = (pc >>> 8) & 0xff;
    }
    return rom;
  }
  
  async function ensureApple2BaseRomBytes() {
    if (state.apple2.baseRomBytes instanceof Uint8Array && state.apple2.baseRomBytes.length > 0) {
      return state.apple2.baseRomBytes;
    }
  
    const preset = currentRunnerPreset();
    const romPath = preset?.romPath || './assets/fixtures/apple2/appleiigo.rom';
  
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
  
  async function applyApple2SnapshotStartPc(startPc) {
    const pc = parsePcLiteral(startPc);
    if (pc == null) {
      return { applied: false, pc: null, reason: 'missing' };
    }
    if (!runtime.sim || !isApple2UiEnabled()) {
      return { applied: false, pc, reason: 'runner inactive' };
    }
  
    const baseRom = await ensureApple2BaseRomBytes();
    if (!(baseRom instanceof Uint8Array) || baseRom.length === 0) {
      return { applied: false, pc, reason: 'rom unavailable' };
    }
  
    const patchedRom = patchApple2ResetVector(baseRom, pc);
    const ok = runtime.sim.apple2_load_rom(patchedRom);
    return { applied: !!ok, pc, reason: ok ? 'ok' : 'rom load failed' };
  }
  
  async function resetApple2WithMemoryVectorOverride() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return false;
    }
  
    const pcBefore = getApple2ProgramCounter();
    const raw = String(dom.memoryResetVector?.value || '').trim();
    let requestedPc = null;
    let usedOverride = false;
  
    if (raw) {
      requestedPc = parsePcLiteral(raw);
      if (requestedPc == null) {
        const msg = `Invalid reset vector "${raw}". Use $B82A, 0xB82A, or decimal.`;
        setMemoryDumpStatus(msg);
        log(msg);
        return false;
      }
  
      const pcStatus = await applyApple2SnapshotStartPc(requestedPc);
      if (!pcStatus.applied) {
        const msg = `Could not apply reset vector $${hexWord(requestedPc)} (${pcStatus.reason}).`;
        setMemoryDumpStatus(msg);
        log(msg);
        return false;
      }
      usedOverride = true;
      setMemoryResetVectorInput(pcStatus.pc);
    }
  
    const resetInfo = performApple2ResetSequence({ releaseCycles: 0 });
    const pcAfter = Number.isFinite(resetInfo?.pcAfter) ? (resetInfo.pcAfter & 0xffff) : getApple2ProgramCounter();
  
    if (pcAfter != null) {
      setMemoryFollowPcState(true);
      if (dom.memoryFollowPc) {
        dom.memoryFollowPc.checked = true;
      }
      if (dom.memoryStart) {
        dom.memoryStart.value = `0x${hexWord(pcAfter)}`;
      }
    }
  
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    refreshWatchTable();
    refreshStatus();
  
    const beforePart = pcBefore != null ? `$${hexWord(pcBefore)}` : 'n/a';
    const afterPart = pcAfter != null ? `$${hexWord(pcAfter)}` : 'n/a';
    const transitionPart = ` PC ${beforePart} -> ${afterPart}.`;
    const msg = usedOverride
      ? `Reset complete using vector $${hexWord(requestedPc)}.${transitionPart}`
      : `Reset complete using current ROM reset vector.${transitionPart}`;
    setMemoryDumpStatus(msg);
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = msg;
    }
    log(msg);
    return true;
  }
  
  function performApple2ResetSequence(options = {}) {
    if (!runtime.sim) {
      return { pcBefore: null, pcAfter: null, releaseCycles: 0, usedResetSignal: false };
    }
    setRunningState(false);
    state.apple2.keyQueue = [];
    const parsedReleaseCycles = Number.parseInt(options.releaseCycles, 10);
    const releaseCycles = Number.isFinite(parsedReleaseCycles)
      ? Math.max(0, parsedReleaseCycles)
      : 10;
    const pcBefore = getApple2ProgramCounter();
    let usedResetSignal = false;
  
    if (runtime.sim.has_signal('reset')) {
      usedResetSignal = true;
      runtime.sim.poke('reset', 1);
      runtime.sim.apple2_run_cpu_cycles(1, 0, false);
      runtime.sim.poke('reset', 0);
      if (releaseCycles > 0) {
        runtime.sim.apple2_run_cpu_cycles(releaseCycles, 0, false);
      }
    } else {
      runtime.sim.reset();
    }
  
    setCycleState(0);
    setUiCyclesPendingState(0);
    if (runtime.sim.trace_enabled()) {
      runtime.sim.trace_capture();
    }
    const pcAfter = getApple2ProgramCounter();
    return { pcBefore, pcAfter, releaseCycles, usedResetSignal };
  }
  
  async function loadApple2MemoryDumpBytes(bytes, offset, options = {}) {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return false;
    }
  
    const off = Math.max(0, parseHexOrDec(offset, 0));
    const source = bytes instanceof Uint8Array ? bytes : new Uint8Array(0);
    const { data, trimmed } = fitApple2RamWindow(source, off);
  
    if (data.length === 0) {
      setMemoryDumpStatus('No bytes loaded (offset out of RAM window).');
      return false;
    }
  
    const ok = runtime.sim.apple2_load_ram(data, off);
    if (!ok) {
      setMemoryDumpStatus('Dump load failed (runner memory API unavailable).');
      return false;
    }
  
    if (options.resetAfterLoad) {
      const parsedResetReleaseCycles = Number.parseInt(options.resetReleaseCycles, 10);
      const resetReleaseCycles = Number.isFinite(parsedResetReleaseCycles)
        ? Math.max(0, parsedResetReleaseCycles)
        : 0;
      performApple2ResetSequence({ releaseCycles: resetReleaseCycles });
    }
  
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    refreshWatchTable();
    refreshStatus();
  
    const label = options.label || 'memory dump';
    const suffix = trimmed ? ` (trimmed to ${data.length} bytes)` : '';
    const msg = `Loaded ${label} at $${off.toString(16).toUpperCase().padStart(4, '0')} (${data.length} bytes)${suffix}`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
  }
  
  async function loadKaratekaDump() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return;
    }
  
    try {
      const [romResp, dumpResp, metaResp] = await Promise.all([
        fetchImpl('./assets/fixtures/apple2/appleiigo.rom'),
        fetchImpl('./assets/fixtures/apple2/karateka_mem.bin'),
        fetchImpl('./assets/fixtures/apple2/karateka_mem_meta.txt')
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
      const patchedRom = patchApple2ResetVector(romBytes, startPc);
      const romLoaded = runtime.sim.apple2_load_rom(patchedRom);
      if (!romLoaded) {
        throw new Error('apple2_load_rom returned false');
      }
      setMemoryResetVectorInput(startPc);
  
      const dumpBytes = new Uint8Array(await dumpResp.arrayBuffer());
      await loadApple2MemoryDumpBytes(dumpBytes, 0, {
        resetAfterLoad: true,
        resetReleaseCycles: 0,
        label: `Karateka dump (PC=$${startPc.toString(16).toUpperCase().padStart(4, '0')})`
      });
    } catch (err) {
      const msg = `Karateka load failed: ${err.message || err}`;
      setMemoryDumpStatus(msg);
      log(msg);
    }
  }

  return {
    isApple2UiEnabled,
    updateIoToggleUi,
    apple2HiresLineAddress,
    setApple2SoundEnabled,
    updateApple2SpeakerAudio,
    setMemoryDumpStatus,
    setMemoryResetVectorInput,
    saveApple2MemoryDump,
    saveApple2MemorySnapshot,
    loadApple2DumpOrSnapshotFile,
    loadLastSavedApple2Dump,
    resetApple2WithMemoryVectorOverride,
    performApple2ResetSequence,
    loadApple2MemoryDumpBytes,
    loadKaratekaDump
  };
}
