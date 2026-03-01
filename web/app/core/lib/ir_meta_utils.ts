import type {
  IrEntryModel,
  IrMetaModel,
  IrModel,
  IrProcessModel,
  IrSignalInfoModel
} from '../../types/models';

function asIrObject(value: unknown): IrModel {
  if (!value || typeof value !== 'object') {
    return {};
  }
  return value as IrModel;
}

export function parseIrMeta(irJson: string): IrMetaModel {
  const ir = asIrObject(JSON.parse(irJson));
  const widths = new Map<string, number>();
  const signalInfo = new Map<string, IrSignalInfoModel>();
  const names: string[] = [];

  for (const kind of ['ports', 'nets', 'regs'] as const) {
    const entries = Array.isArray(ir[kind]) ? (ir[kind] as IrEntryModel[]) : [];
    for (const entry of entries) {
      if (!entry || typeof entry.name !== 'string') {
        continue;
      }
      if (!widths.has(entry.name)) {
        names.push(entry.name);
      }
      const width = Number.parseInt(String(entry.width ?? ''), 10) || 1;
      widths.set(entry.name, width);
      signalInfo.set(entry.name, {
        name: entry.name,
        width,
        kind,
        direction: typeof entry.direction === 'string' ? entry.direction : null,
        entry
      });
    }
  }

  const clocks: string[] = [];
  const processes = Array.isArray(ir.processes) ? (ir.processes as IrProcessModel[]) : [];
  for (const process of processes) {
    if (
      process?.clocked
      && typeof process.clock === 'string'
      && !clocks.includes(process.clock)
    ) {
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

  const rankClock = (name: string) => {
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

export function currentIrSourceKey(irText: unknown) {
  const source = String(irText || '');
  if (!source) {
    return '';
  }
  const first = source.charCodeAt(0) || 0;
  const last = source.charCodeAt(source.length - 1) || 0;
  return `${source.length}:${first}:${last}`;
}
