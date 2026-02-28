function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`setupWaveformP5 requires function: ${name}`);
  }
}

export function setupWaveformP5({
  dom,
  state,
  runtime,
  mountElement = null,
  runtimeKey = 'waveformP5',
  waveformFontFamily,
  waveformPalette,
  formatValue,
  p5Ctor = globalThis.p5
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('setupWaveformP5 requires dom/state/runtime');
  }
  requireFn('waveformFontFamily', waveformFontFamily);
  requireFn('waveformPalette', waveformPalette);
  requireFn('formatValue', formatValue);

  if (typeof p5Ctor !== 'function') {
    throw new Error('setupWaveformP5 requires p5Ctor');
  }

  const hostElement = mountElement || dom.canvasWrap;
  if (!hostElement) {
    throw new Error('setupWaveformP5 requires a mount element');
  }

  const sketch = (p) => {
    const leftPad = 170;

    const resize = () => {
      const w = Math.max(300, hostElement.clientWidth);
      const h = Math.max(220, hostElement.clientHeight);
      p.resizeCanvas(w, h);
    };

    p.setup = () => {
      const width = Math.max(300, hostElement.clientWidth);
      const height = Math.max(220, hostElement.clientHeight);
      p.createCanvas(width, height).parent(hostElement);
      runtime[runtimeKey] = p;
      p.textFont(waveformFontFamily(state.theme));
      p.textSize(11);
    };

    p.windowResized = resize;

    p.draw = () => {
      const palette = waveformPalette(state.theme);
      p.background(...palette.bg);
      p.stroke(...palette.axis);
      p.line(leftPad, 0, leftPad, p.height);

      if (!runtime.sim) {
        p.noStroke();
        p.fill(...palette.hint);
        p.text('Initialize simulator to view waveforms', 16, 24);
        return;
      }

      const rows = state.watchRows;
      if (!rows || rows.length === 0) {
        p.noStroke();
        p.fill(...palette.hint);
        p.text('Add watch signals to render traces', 16, 24);
        return;
      }

      const latest = Math.max(1, runtime.parser.latestTime());
      const visibleTicks = 1200;
      const startT = Math.max(0, latest - visibleTicks);
      const rowH = Math.max(28, Math.floor((p.height - 20) / rows.length));
      const plotW = p.width - leftPad - 8;

      const xFor = (t) => leftPad + ((t - startT) / Math.max(1, latest - startT)) * plotW;
      const yFor = (rowTop, rowHeight, value, width) => {
        if (width <= 1) {
          return value ? rowTop + 6 : rowTop + rowHeight - 6;
        }

        const bits = Math.min(width, 20);
        const max = Math.max(1, (2 ** bits) - 1);
        const clamped = Math.min(value, max);
        return rowTop + rowHeight - 6 - (clamped / max) * (rowHeight - 12);
      };

      rows.forEach((row, i) => {
        const top = 10 + i * rowH;
        const bottom = top + rowH;

        p.stroke(...palette.grid);
        p.line(0, bottom, p.width, bottom);

        p.noStroke();
        p.fill(...palette.label);
        p.text(`${row.name} [${row.width}]`, 8, top + 12);

        const series = runtime.parser.series(row.name);
        const fallback = runtime.parser.value(row.name);
        const initial = fallback == null ? Number(row.value) : fallback;

        let prevT = startT;
        let prevV = initial;

        for (const sample of series) {
          if (sample.t < startT) {
            prevT = startT;
            prevV = sample.v;
            continue;
          }

          const x0 = xFor(prevT);
          const x1 = xFor(sample.t);
          const y0 = yFor(top, rowH, prevV, row.width);
          const y1 = yFor(top, rowH, sample.v, row.width);

          p.stroke(...palette.trace);
          p.line(x0, y0, x1, y0);
          p.line(x1, y0, x1, y1);

          prevT = sample.t;
          prevV = sample.v;
        }

        const xTail = xFor(prevT);
        const xEnd = xFor(latest);
        const yTail = yFor(top, rowH, prevV, row.width);
        p.stroke(...palette.trace);
        p.line(xTail, yTail, xEnd, yTail);

        p.noStroke();
        p.fill(...palette.value);
        p.text(formatValue(row.value, row.width), p.width - 95, top + 12);
      });

      p.noStroke();
      p.fill(...palette.time);
      p.text(`t=${latest}`, p.width - 70, p.height - 8);
    };
  };

  return new p5Ctor(sketch);
}
