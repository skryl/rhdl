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

  function refreshApple2Screen() {
    if (!dom.apple2TextScreen) {
      return;
    }
    if (!isApple2UiEnabled()) {
      dom.apple2TextScreen.textContent = 'Load the Apple II runner to use this tab.';
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

    if (state.apple2.displayHires && dom.apple2HiresCanvas) {
      const mem = runtime.sim.apple2_read_ram(0x2000, 0x2000);
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

    const dump = runtime.sim.apple2_read_ram(0x0400, 0x0400);
    if (!dump || dump.length === 0) {
      dom.apple2TextScreen.textContent = 'Apple II text page unavailable';
      return;
    }

    const lines = [];
    for (let row = 0; row < 24; row += 1) {
      const base = apple2TextLineAddress(row) - 0x0400;
      let line = '';
      for (let col = 0; col < 40; col += 1) {
        line += apple2DecodeChar(dump[base + col] || 0);
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

    const get = (name) => (runtime.sim.has_signal(name) ? runtime.sim.peek(name) : 0);
    const rows = [
      ['pc_debug', `0x${(get('pc_debug') & 0xffff).toString(16).toUpperCase().padStart(4, '0')}`],
      ['opcode_debug', `0x${(get('opcode_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['a_debug', `0x${(get('a_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['x_debug', `0x${(get('x_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['y_debug', `0x${(get('y_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['s_debug', `0x${(get('s_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['p_debug', `0x${(get('p_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
      ['q3', `${get('clk_2m') & 0x1}`],
      ['speaker', `${get('speaker') & 0x1}`]
    ];

    const toggles = state.apple2.lastCpuResult?.speaker_toggles || 0;
    renderApple2DebugRows(dom, rows, `Speaker toggles (last batch): ${toggles}`, true);
  }

  return {
    refreshApple2Screen,
    refreshApple2Debug
  };
}
