function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2VisualController requires function: ${name}`);
  }
}

function apple2TextLineAddress(row) {
  const group = Math.floor(row / 8);
  const lineInGroup = row % 8;
  return 0x0400 + (lineInGroup * 0x80) + (group * 0x28);
}

function apple2DecodeChar(code) {
  const c = code & 0x7f;
  if (c >= 0x20 && c <= 0x7e) {
    return String.fromCharCode(c);
  }
  return ' ';
}

function decodeTextChar(code, textConfig = {}) {
  const charMask = Number.parseInt(textConfig.charMask, 10);
  const asciiMin = Number.parseInt(textConfig.asciiMin, 10);
  const asciiMax = Number.parseInt(textConfig.asciiMax, 10);
  const masked = Number.isFinite(charMask) ? (code & charMask) : (code & 0x7F);
  const min = Number.isFinite(asciiMin) ? asciiMin : 0x20;
  const max = Number.isFinite(asciiMax) ? asciiMax : 0x7E;
  if (masked >= min && masked <= max) {
    return String.fromCharCode(masked);
  }
  return ' ';
}

export function createApple2VisualController({
  dom,
  state,
  runtime,
  isApple2UiEnabled,
  updateIoToggleUi,
  renderApple2DebugRows,
  apple2HiresLineAddress
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2VisualController requires dom/state/runtime');
  }
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('renderApple2DebugRows', renderApple2DebugRows);
  requireFn('apple2HiresLineAddress', apple2HiresLineAddress);

  function currentIoConfig() {
    return state.apple2?.ioConfig || {};
  }

  function readRunnerMemory(offset, length, options = {}) {
    if (!runtime.sim) {
      return new Uint8Array(0);
    }
    if (typeof runtime.sim.memory_read === 'function') {
      return runtime.sim.memory_read(offset, length, options);
    }
    return new Uint8Array(0);
  }

  function readUartText(length) {
    const sim = runtime?.sim;
    if (!sim) {
      return new Uint8Array(0);
    }
    if (typeof sim.runner_riscv_uart_tx_len !== 'function'
      || typeof sim.runner_riscv_uart_tx_bytes !== 'function') {
      return new Uint8Array(0);
    }

    const txLen = Number(sim.runner_riscv_uart_tx_len());
    const txLimit = Number.isFinite(txLen) ? Math.max(0, txLen) : 0;
    const readLen = Math.max(0, Number.isFinite(length) ? Math.min(length, txLimit) : txLimit);
    return sim.runner_riscv_uart_tx_bytes(0, readLen);
  }

  function refreshApple2Screen() {
    if (!dom.apple2TextScreen) {
      return;
    }
    if (!isApple2UiEnabled()) {
      dom.apple2TextScreen.textContent = 'Load a runner with memory + I/O support to use this tab.';
      if (dom.apple2HiresCanvas) {
        const ctx = dom.apple2HiresCanvas.getContext('2d');
        if (ctx) {
          ctx.clearRect(0, 0, dom.apple2HiresCanvas.width, dom.apple2HiresCanvas.height);
        }
      }
      updateIoToggleUi();
      return;
    }

    updateIoToggleUi();
    const ioConfig = currentIoConfig();
    if (ioConfig.display && ioConfig.display.enabled === false) {
      dom.apple2TextScreen.textContent = 'Display is disabled for this runner configuration.';
      if (dom.apple2HiresCanvas) {
        const ctx = dom.apple2HiresCanvas.getContext('2d');
        if (ctx) {
          ctx.clearRect(0, 0, dom.apple2HiresCanvas.width, dom.apple2HiresCanvas.height);
        }
      }
      return;
    }
    const displayMode = String(
      ioConfig.display?.mode || (runtime.sim.runner_kind?.() === 'apple2' ? 'apple2' : 'text')
    );

    if (displayMode === 'apple2' && state.apple2.displayHires && dom.apple2HiresCanvas) {
      const mem = readRunnerMemory(0x2000, 0x2000, { mapped: false });
      if (!mem || mem.length === 0) {
        dom.apple2TextScreen.textContent = 'Apple II hi-res page unavailable';
        return;
      }

      const canvas = dom.apple2HiresCanvas;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        return;
      }

      const image = ctx.createImageData(canvas.width, canvas.height);
      const out = image.data;

      for (let row = 0; row < 192; row += 1) {
        const lineBase = apple2HiresLineAddress(row) - 0x2000;
        for (let byteCol = 0; byteCol < 40; byteCol += 1) {
          const b = mem[lineBase + byteCol] || 0;
          const palette = (b >> 7) & 1;

          for (let bit = 0; bit < 7; bit += 1) {
            const pixelOn = (b >> bit) & 1;
            const x = byteCol * 7 + bit;
            const idx = (row * canvas.width + x) * 4;

            if (!pixelOn) {
              out[idx + 0] = 5;
              out[idx + 1] = 12;
              out[idx + 2] = 20;
              out[idx + 3] = 255;
              continue;
            }

            if (!state.apple2.displayColor) {
              out[idx + 0] = 140;
              out[idx + 1] = 255;
              out[idx + 2] = 170;
              out[idx + 3] = 255;
              continue;
            }

            const parity = (x + palette) & 1;
            if (palette === 0) {
              if (parity === 0) {
                out[idx + 0] = 120;
                out[idx + 1] = 255;
                out[idx + 2] = 120;
              } else {
                out[idx + 0] = 255;
                out[idx + 1] = 120;
                out[idx + 2] = 210;
              }
            } else if (parity === 0) {
              out[idx + 0] = 120;
              out[idx + 1] = 170;
              out[idx + 2] = 255;
            } else {
              out[idx + 0] = 255;
              out[idx + 1] = 195;
              out[idx + 2] = 120;
            }
            out[idx + 3] = 255;
          }
        }
      }

      ctx.putImageData(image, 0, 0);
      return;
    }

    if (displayMode === 'uart') {
      const textConfig = ioConfig.display?.text || {};
      const width = Math.max(1, Number.parseInt(textConfig.width, 10) || 80);
      const height = Math.max(1, Number.parseInt(textConfig.height, 10) || 24);
      const maxBytes = width * height;
      const uartBytes = readUartText(maxBytes);
      if (!uartBytes || uartBytes.length === 0) {
        dom.apple2TextScreen.textContent = 'No UART output yet.';
        return;
      }

      const lines = [];
      for (let row = 0; row < height; row += 1) {
        let line = '';
        const offset = row * width;
        for (let col = 0; col < width; col += 1) {
          const byte = uartBytes[offset + col] || 0;
          line += decodeTextChar(byte, textConfig);
        }
        lines.push(line);
      }
      dom.apple2TextScreen.textContent = lines.join('\n');
      return;
    }

    const textConfig = ioConfig.display?.text || {};
    const textStart = Number.parseInt(textConfig.start, 10);
    const width = Math.max(1, Number.parseInt(textConfig.width, 10) || 40);
    const height = Math.max(1, Number.parseInt(textConfig.height, 10) || 24);
    const rowStride = Math.max(width, Number.parseInt(textConfig.rowStride, 10) || width);
    const rowLayout = String(textConfig.rowLayout || (displayMode === 'apple2' ? 'apple2' : 'linear'));

    const dumpStart = Number.isFinite(textStart) ? textStart : 0x0400;
    const dumpLength = Math.max(width * height, rowStride * height);
    const dump = readRunnerMemory(dumpStart, dumpLength, { mapped: true });
    if (!dump || dump.length === 0) {
      dom.apple2TextScreen.textContent = 'Runner text page unavailable';
      return;
    }

    const lines = [];
    for (let row = 0; row < height; row += 1) {
      const base = rowLayout === 'apple2'
        ? (apple2TextLineAddress(row) - dumpStart)
        : (row * rowStride);
      let line = '';
      for (let col = 0; col < width; col += 1) {
        const byte = dump[base + col] || 0;
        line += rowLayout === 'apple2'
          ? apple2DecodeChar(byte)
          : decodeTextChar(byte, textConfig);
      }
      lines.push(line);
    }
    dom.apple2TextScreen.textContent = lines.join('\n');
  }

  function refreshApple2Debug() {
    if (!isApple2UiEnabled()) {
      renderApple2DebugRows(dom, [], 'Speaker toggles: -', false);
      return;
    }

    const ioConfig = currentIoConfig();
    const watchSignals = Array.isArray(ioConfig.watchSignals) && ioConfig.watchSignals.length > 0
      ? ioConfig.watchSignals
      : ['pc_debug', 'opcode_debug', 'a_debug', 'x_debug', 'y_debug', 's_debug', 'p_debug', 'speaker'];
    const rows = [];
    for (const name of watchSignals.slice(0, 12)) {
      if (!runtime.sim.has_signal(name)) {
        continue;
      }
      const value = runtime.sim.peek(name);
      const width = name.includes('pc') || name.includes('addr') ? 4 : 2;
      const rendered = `0x${(value & (width === 4 ? 0xFFFF : 0xFF)).toString(16).toUpperCase().padStart(width, '0')}`;
      rows.push([name, rendered]);
    }
    if (rows.length === 0) {
      rows.push(['-', 'No configured debug signals']);
    }

    const toggles = state.apple2.lastCpuResult?.speaker_toggles || state.apple2.lastSpeakerToggles || 0;
    renderApple2DebugRows(dom, rows, `Speaker toggles (last batch): ${toggles}`, true);
  }

  return {
    refreshApple2Screen,
    refreshApple2Debug
  };
}
