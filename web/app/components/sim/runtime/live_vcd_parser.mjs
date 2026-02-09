export class LiveVcdParser {
  constructor(maxPoints = 5000) {
    this.maxPoints = maxPoints;
    this.reset();
  }

  reset() {
    this.signalIds = new Map();
    this.signalWidths = new Map();
    this.traces = new Map();
    this.latestValues = new Map();
    this.time = 0;
    this.partial = '';
  }

  ingest(chunk) {
    if (!chunk) {
      return;
    }

    const data = this.partial + chunk;
    const lines = data.split('\n');
    this.partial = lines.pop() || '';

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }
      this.parseLine(line);
    }
  }

  parseLine(line) {
    if (line.startsWith('$var')) {
      const m = line.match(/^\$var\s+wire\s+(\d+)\s+(\S+)\s+(\S+)\s+\$end$/);
      if (m) {
        const width = Number.parseInt(m[1], 10);
        const id = m[2];
        const name = m[3];
        this.signalIds.set(id, name);
        this.signalWidths.set(name, width);
        if (!this.traces.has(name)) {
          this.traces.set(name, []);
        }
      }
      return;
    }

    if (line[0] === '#') {
      const t = Number.parseInt(line.slice(1), 10);
      if (Number.isFinite(t)) {
        this.time = t;
      }
      return;
    }

    if (line[0] === 'b') {
      const m = line.match(/^b([01xz]+)\s+(\S+)$/i);
      if (!m) {
        return;
      }
      const bits = m[1].replace(/[xz]/gi, '0');
      const id = m[2];
      const value = bits.length > 30 ? Number.parseInt(bits.slice(-30), 2) : Number.parseInt(bits, 2);
      this.record(id, Number.isFinite(value) ? value : 0);
      return;
    }

    if (line[0] === '0' || line[0] === '1') {
      const value = line[0] === '1' ? 1 : 0;
      const id = line.slice(1);
      this.record(id, value);
    }
  }

  record(id, value) {
    const name = this.signalIds.get(id);
    if (!name) {
      return;
    }

    const trace = this.traces.get(name) || [];
    const last = trace[trace.length - 1];
    if (!last || last.t !== this.time || last.v !== value) {
      trace.push({ t: this.time, v: value });
      if (trace.length > this.maxPoints) {
        trace.splice(0, trace.length - this.maxPoints);
      }
      this.traces.set(name, trace);
    }

    this.latestValues.set(name, value);
  }

  series(name) {
    return this.traces.get(name) || [];
  }

  value(name) {
    return this.latestValues.get(name);
  }

  latestTime() {
    return this.time;
  }
}
