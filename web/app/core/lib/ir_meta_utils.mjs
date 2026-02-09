export function parseIrMeta(irJson) {
  const ir = JSON.parse(irJson);
  const widths = new Map();
  const signalInfo = new Map();
  const names = [];

  for (const kind of ['ports', 'nets', 'regs']) {
    const entries = Array.isArray(ir[kind]) ? ir[kind] : [];
    for (const entry of entries) {
      if (!entry || typeof entry.name !== 'string') {
        continue;
      }
      if (!widths.has(entry.name)) {
        names.push(entry.name);
      }
      const width = Number.parseInt(entry.width, 10) || 1;
      widths.set(entry.name, width);
      signalInfo.set(entry.name, {
        name: entry.name,
        width,
        kind,
        direction: entry.direction || null,
        entry
      });
    }
  }

  const clocks = [];
  const processes = Array.isArray(ir.processes) ? ir.processes : [];
  for (const process of processes) {
    if (process?.clocked && typeof process.clock === 'string' && !clocks.includes(process.clock)) {
      clocks.push(process.clock);
    }
  }

  const clockSet = new Set(clocks);
  for (const name of names) {
    if (/(\bclock\b|(^|[_./])clk([_./]|$))/i.test(name)) {
      clockSet.add(name);
    }
  }

  for (const preferred of ['clk', 'clock']) {
    if (widths.has(preferred)) {
      clockSet.add(preferred);
    }
  }

  const rankClock = (name) => {
    if (/^(clk|clock)$/i.test(name)) {
      return 0;
    }
    if (!name.includes('__')) {
      return 1;
    }
    if (/__clk$/i.test(name)) {
      return 2;
    }
    return 3;
  };

  const clockCandidates = Array.from(clockSet).sort((a, b) => {
    const rankDiff = rankClock(a) - rankClock(b);
    if (rankDiff !== 0) {
      return rankDiff;
    }
    return a.localeCompare(b);
  });

  return { ir, widths, signalInfo, names, clocks, clockCandidates };
}

export function currentIrSourceKey(irText) {
  const source = String(irText || '');
  if (!source) {
    return '';
  }
  const first = source.charCodeAt(0) || 0;
  const last = source.charCodeAt(source.length - 1) || 0;
  return `${source.length}:${first}:${last}`;
}
