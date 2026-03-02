import { LitElement, html, css } from 'lit';
import { asRecord, type ExplorerDomRefs } from '../lib/types';

function ellipsizeText(value: unknown, maxLen = 88) {
  const text = String(value ?? '');
  if (text.length <= maxLen) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLen - 3))}...`;
}

type ValueFormatter = (value: unknown, width?: number) => string;

interface LiveSignalRow {
  name: string;
  value: string;
  matchesHighlight: boolean;
}

interface ConnectionRow {
  type: string;
  source: string;
  target: string;
  details: string;
}

class RhdlComponentLiveSignals extends LitElement {
  [key: string]: unknown;
  rows: LiveSignalRow[];
  highlightLabel: string;
  highlightMissing: boolean;
  extraSignals: number;
  static properties = {
    rows: { state: true },
    highlightLabel: { state: true },
    highlightMissing: { state: true },
    extraSignals: { state: true }
  };

  static styles = css`
    :host {
      display: block;
      border: 1px solid #253f59;
      border-radius: 8px;
      background: #081523;
      max-height: 28vh;
      overflow: auto;
      padding: 8px;
    }
    .empty {
      padding: 8px;
      opacity: 0.85;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
    }
    .row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 8px;
      align-items: center;
      padding: 6px 8px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
    }
    .row.highlight {
      background: rgba(255, 220, 120, 0.18);
    }
    .name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .value {
      white-space: nowrap;
      opacity: 0.95;
    }
    :host-context(body.theme-shenzhen) {
      border-color: #335145;
      background: #0d1a1a;
    }
    :host-context(body.theme-shenzhen) .value {
      color: #9df2c0;
    }
    :host-context(body.theme-shenzhen) .row.highlight {
      border-color: #87edb4;
      background: rgba(40, 78, 62, 0.62);
    }
  `;

  constructor() {
    super();
    this.rows = [] as LiveSignalRow[];
    this.highlightLabel = '';
    this.highlightMissing = false;
    this.extraSignals = 0;
  }

  setData(data: unknown, formatValue: unknown) {
    const formatter: ValueFormatter = typeof formatValue === 'function'
      ? (formatValue as ValueFormatter)
      : (value: unknown) => String(value ?? '');
    const dataRecord = asRecord(data) || {};
    const signals = Array.isArray(dataRecord.signals) ? dataRecord.signals : [];
    this.rows = signals.map((signal): LiveSignalRow => {
      const signalRecord = asRecord(signal) || {};
      return {
        name: String(signalRecord.fullName || signalRecord.name || ''),
        value:
          signalRecord.value == null
            ? '-'
            : formatter(signalRecord.value, Number(signalRecord.width) || 1),
        matchesHighlight: signalRecord.matchesHighlight === true
      };
    });
    this.highlightLabel = String(dataRecord.highlightLabel || '');
    this.highlightMissing = !!(dataRecord.highlight && Number(dataRecord.highlightedRows || 0) === 0 && this.highlightLabel);
    this.extraSignals = Math.max(0, Number(dataRecord.extraSignals || 0));
  }

  render() {
    if (!this.rows.length && !this.highlightMissing && this.extraSignals === 0) {
      return html`<div class="empty">No live signals to display.</div>`;
    }
    return html`
      ${this.rows.map((row: LiveSignalRow) => html`
        <div class=${`row${row.matchesHighlight ? ' highlight' : ''}`}>
          <span class="name">${row.name}</span>
          <span class="value">${row.value}</span>
        </div>
      `)}
      ${this.highlightMissing ? html`
        <div class="row">
          <span class="name">${this.highlightLabel}</span>
          <span class="value">-</span>
        </div>
      ` : ''}
      ${this.extraSignals > 0 ? html`
        <div class="row">
          <span class="name">${this.extraSignals} additional signals</span>
          <span class="value">...</span>
        </div>
      ` : ''}
    `;
  }
}

class RhdlComponentConnections extends LitElement {
  [key: string]: unknown;
  rows: ConnectionRow[];
  hiddenCount: number;
  static properties = {
    rows: { state: true },
    hiddenCount: { state: true }
  };

  static styles = css`
    :host { display: block; }
    table {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
    }
    th, td {
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      padding: 6px 8px;
      text-align: left;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    th { opacity: 0.85; }
    th:nth-child(1),
    td:nth-child(1) {
      width: 5.6rem;
      white-space: nowrap;
    }
    th:nth-child(2),
    td:nth-child(2),
    th:nth-child(3),
    td:nth-child(3) {
      width: 34%;
      font-variant-numeric: tabular-nums;
    }
    th:nth-child(4),
    td:nth-child(4) {
      width: 26%;
      font-variant-numeric: tabular-nums;
    }
    .empty {
      padding: 8px;
      opacity: 0.85;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
    }
    :host-context(body.theme-shenzhen) table {
      background: #10201d;
    }
    :host-context(body.theme-shenzhen) th,
    :host-context(body.theme-shenzhen) td {
      border-color: #35564a;
    }
    :host-context(body.theme-shenzhen) th {
      color: #94ad9f;
      background: #142724;
      text-transform: uppercase;
    }
  `;

  constructor() {
    super();
    this.rows = [] as ConnectionRow[];
    this.hiddenCount = 0;
  }

  setConnections(rows: unknown, hiddenCount = 0) {
    this.rows = Array.isArray(rows)
      ? rows.map((row): ConnectionRow => {
        const rowRecord = asRecord(row) || {};
        return {
          type: String(rowRecord.type || ''),
          source: String(rowRecord.source || ''),
          target: String(rowRecord.target || ''),
          details: String(rowRecord.details || '')
        };
      })
      : [];
    this.hiddenCount = Math.max(0, Number(hiddenCount) || 0);
  }

  clear() {
    this.rows = [];
    this.hiddenCount = 0;
  }

  render() {
    if (!this.rows.length) {
      return html`<div class="empty">No explicit wire/port connections available for this component.</div>`;
    }

    return html`
      <table class="component-connection-table">
        <thead>
          <tr>
            <th>Type</th>
            <th>Source</th>
            <th>Target</th>
            <th>Details</th>
          </tr>
        </thead>
        <tbody>
          ${this.rows.map((row: ConnectionRow) => html`
            <tr>
              <td>${row.type}</td>
              <td title=${row.source}>${ellipsizeText(row.source)}</td>
              <td title=${row.target}>${ellipsizeText(row.target)}</td>
              <td title=${row.details}>${ellipsizeText(row.details)}</td>
            </tr>
          `)}
          ${this.hiddenCount > 0 ? html`
            <tr>
              <td colspan="4">${`... ${this.hiddenCount} additional connections not shown`}</td>
            </tr>
          ` : ''}
        </tbody>
      </table>
    `;
  }
}

if (!customElements.get('rhdl-component-live-signals')) {
  customElements.define('rhdl-component-live-signals', RhdlComponentLiveSignals);
}
if (!customElements.get('rhdl-component-connections')) {
  customElements.define('rhdl-component-connections', RhdlComponentConnections);
}

export function renderComponentLiveSignalsView(
  dom: ExplorerDomRefs,
  data: unknown,
  formatValue: unknown
) {
  const element = dom.componentLiveSignals;
  if (!element || typeof element.setData !== 'function') {
    return;
  }
  element.setData(data, formatValue);
}

export function renderComponentConnectionsView(
  dom: ExplorerDomRefs,
  metaText: unknown,
  rows: unknown,
  hiddenCount = 0
) {
  if (!dom.componentConnectionMeta || !dom.componentConnectionBody) {
    return;
  }

  dom.componentConnectionMeta.textContent = String(metaText || '');
  if (typeof dom.componentConnectionBody.setConnections === 'function') {
    dom.componentConnectionBody.setConnections(rows, hiddenCount);
  }
}

export function clearComponentConnectionsView(dom: ExplorerDomRefs, metaText: unknown) {
  if (!dom.componentConnectionMeta || !dom.componentConnectionBody) {
    return;
  }
  dom.componentConnectionMeta.textContent = String(metaText || '');
  if (typeof dom.componentConnectionBody.clear === 'function') {
    dom.componentConnectionBody.clear();
  }
}
