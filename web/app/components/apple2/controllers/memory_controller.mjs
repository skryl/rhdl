function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2MemoryController requires function: ${name}`);
  }
}

export function createApple2MemoryController({
  dom,
  state,
  runtime,
  isApple2UiEnabled,
  parseHexOrDec,
  hexWord,
  hexByte,
  renderMemoryPanel,
  disassemble6502LinesWithMemory,
  setMemoryDumpStatus,
  addressSpace = 0x10000
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2MemoryController requires dom/state/runtime');
  }
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('parseHexOrDec', parseHexOrDec);
  requireFn('hexWord', hexWord);
  requireFn('hexByte', hexByte);
  requireFn('renderMemoryPanel', renderMemoryPanel);
  requireFn('disassemble6502LinesWithMemory', disassemble6502LinesWithMemory);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  const MAX_MEMORY_VIEW_LENGTH = 0x10000;
  const BYTES_PER_MEMORY_ROW = 16;
  const CHANGE_HIGHLIGHT_MS = 750;
  const previousWindowBytes = new Map();
  const changedByteExpiryMs = new Map();

  function resetHighlightState() {
    previousWindowBytes.clear();
    changedByteExpiryMs.clear();
  }

  function pruneExpiredHighlights(nowMs) {
    for (const [addr, expiryMs] of changedByteExpiryMs.entries()) {
      if (expiryMs <= nowMs) {
        changedByteExpiryMs.delete(addr);
      }
    }
  }

  function currentIoConfig() {
    return state.apple2?.ioConfig || {};
  }

  function currentAddressSpace() {
    const configured = Number.parseInt(currentIoConfig().memory?.addressSpace, 10);
    if (Number.isFinite(configured) && configured > 0) {
      return configured;
    }
    return addressSpace;
  }

  function getApple2ProgramCounter() {
    if (!runtime.sim || !isApple2UiEnabled()) {
      return null;
    }

    const configCandidates = currentIoConfig().pcSignalCandidates;
    const candidates = Array.isArray(configCandidates) && configCandidates.length > 0
      ? configCandidates
      : ['pc_debug', 'cpu__debug_pc', 'reg_pc'];
    for (const name of candidates) {
      if (runtime.sim.has_signal(name)) {
        return runtime.sim.peek(name) & 0xffff;
      }
    }
    return null;
  }

  function readApple2MappedMemory(start, length) {
    if (!runtime.sim || !isApple2UiEnabled()) {
      return new Uint8Array(0);
    }

    const len = Math.max(0, Number.parseInt(length, 10) || 0);
    if (len === 0) {
      return new Uint8Array(0);
    }

    const out = new Uint8Array(len);
    const addrSpace = currentAddressSpace();
    const useMapped = currentIoConfig().memory?.viewMapped !== false;
    let addr = Math.max(0, Number(start) || 0) % addrSpace;
    let cursor = 0;

    while (cursor < len) {
      const span = Math.min(len - cursor, Math.max(1, addrSpace - addr));
      const chunk = typeof runtime.sim.memory_read === 'function'
        ? runtime.sim.memory_read(addr, span, { mapped: useMapped })
        : new Uint8Array(0);
      if (chunk && chunk.length > 0) {
        out.set(chunk.subarray(0, Math.min(span, chunk.length)), cursor);
      }
      cursor += span;
      addr = (addr + span) % addrSpace;
    }

    return out;
  }

  function refreshMemoryView() {
    if (!dom.memoryDump || !runtime.sim) {
      resetHighlightState();
      renderMemoryPanel(dom, {
        followDisabled: !isApple2UiEnabled(),
        followChecked: !!state.memory.followPc,
        dumpText: '',
        disasmText: '',
        dumpRows: []
      });
      return;
    }

    if (!isApple2UiEnabled()) {
      resetHighlightState();
      renderMemoryPanel(dom, {
        followDisabled: true,
        followChecked: !!state.memory.followPc,
        dumpText: 'Load a runner with memory + I/O support to browse memory.',
        disasmText: 'Load a runner with memory + I/O support to view disassembly.',
        dumpRows: []
      });
      setMemoryDumpStatus('Memory dump loading requires a runner with memory + I/O support.');
      return;
    }

    const addrSpace = currentAddressSpace();
    const maxLength = Math.max(1, Math.min(addrSpace, MAX_MEMORY_VIEW_LENGTH));
    let start = Math.max(0, parseHexOrDec(dom.memoryStart?.value, 0)) % addrSpace;
    const length = Math.max(1, Math.min(maxLength, parseHexOrDec(dom.memoryLength?.value, maxLength)));
    const pc = getApple2ProgramCounter();

    if (state.memory.followPc && pc != null) {
      const maxStart = Math.max(0, addrSpace - length);
      const centered = Math.max(0, (pc & 0xffff) - Math.floor(length / 2));
      start = Math.min(maxStart, centered) & ~0x0f;
      if (dom.memoryStart) {
        dom.memoryStart.value = `0x${hexWord(start)}`;
      }
    }

    const data = readApple2MappedMemory(start, length);

    if (!data || data.length === 0) {
      resetHighlightState();
      renderMemoryPanel(dom, {
        followDisabled: false,
        followChecked: !!state.memory.followPc,
        dumpText: 'No memory data',
        disasmText: 'No disassembly data',
        dumpRows: []
      });
      return;
    }

    const nowMs = Date.now();
    pruneExpiredHighlights(nowMs);
    const nextWindowBytes = new Map();
    const lines = [];
    const dumpRows = [];
    for (let i = 0; i < data.length; i += 16) {
      const row = data.slice(i, i + 16);
      const rowBytes = [];
      for (let j = 0; j < row.length; j += 1) {
        const value = row[j] & 0xff;
        const byteAddr = (start + i + j) % addrSpace;
        const previous = previousWindowBytes.get(byteAddr);
        if (previous != null && previous !== value) {
          changedByteExpiryMs.set(byteAddr, nowMs + CHANGE_HIGHLIGHT_MS);
        }
        nextWindowBytes.set(byteAddr, value);
        const changed = (changedByteExpiryMs.get(byteAddr) || 0) > nowMs;
        rowBytes.push({
          hex: hexByte(value),
          changed
        });
      }
      const hex = rowBytes.map((entry) => entry.hex).join(' ');
      const ascii = Array.from(row, (b) => (b >= 32 && b <= 126 ? String.fromCharCode(b) : '.')).join('');
      const addr = (start + i) % addrSpace;
      const hasPc = pc != null && (((pc & 0xffff) - addr + addrSpace) % addrSpace) < row.length;
      const marker = hasPc ? '>>' : '  ';
      lines.push(`${marker} ${hexWord(addr)}: ${hex.padEnd(16 * 3 - 1, ' ')}  ${ascii}`);
      dumpRows.push({
        marker,
        addressHex: hexWord(addr),
        bytes: rowBytes,
        ascii
      });
    }

    previousWindowBytes.clear();
    for (const [addr, value] of nextWindowBytes.entries()) {
      previousWindowBytes.set(addr, value);
    }

    const disasmLineCount = Math.max(1, Math.ceil(length / BYTES_PER_MEMORY_ROW));
    const disasmStart = start;
    renderMemoryPanel(dom, {
      followDisabled: false,
      followChecked: !!state.memory.followPc,
      dumpText: lines.join('\n'),
      dumpRows,
      disasmText: disassemble6502LinesWithMemory(
        disasmStart,
        disasmLineCount,
        readApple2MappedMemory,
        { highlightPc: pc, addressSpace: addrSpace }
      ).join('\n'),
      followPc: !!state.memory.followPc,
      pcAddress: pc,
      windowStart: start,
      addressSpace: addrSpace,
      bytesPerRow: BYTES_PER_MEMORY_ROW
    });
  }

  return {
    getApple2ProgramCounter,
    readApple2MappedMemory,
    refreshMemoryView
  };
}
