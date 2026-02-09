import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

class RhdlComponentTree extends LitElement {
  static properties = {
    rows: { state: true },
    parseError: { state: true },
    filterText: { state: true }
  };

  static styles = css`
    :host {
      display: block;
      margin: 0;
      border: 1px solid #253f59;
      border-radius: 8px;
      background: #081523;
      min-height: 420px;
      max-height: 70vh;
      overflow: auto;
      padding: 6px;
    }
    .search {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 6px;
      margin-bottom: 8px;
      position: sticky;
      top: 0;
      z-index: 1;
      padding-bottom: 6px;
      background: linear-gradient(180deg, rgba(8, 21, 35, 0.98), rgba(8, 21, 35, 0.86));
    }
    .search input {
      min-width: 0;
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 6px;
      background: rgba(0, 0, 0, 0.28);
      color: inherit;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
      padding: 6px 8px;
    }
    .search button {
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-radius: 6px;
      background: rgba(0, 0, 0, 0.22);
      color: inherit;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
      padding: 6px 10px;
      cursor: pointer;
    }
    .empty {
      padding: 8px;
      opacity: 0.85;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
    }
    .tree {
      display: grid;
      gap: 4px;
    }
    button {
      appearance: none;
      border: 1px solid rgba(255, 255, 255, 0.1);
      background: rgba(0, 0, 0, 0.2);
      color: inherit;
      border-radius: 8px;
      min-height: 30px;
      display: grid;
      grid-template-columns: 1fr auto auto;
      gap: 8px;
      align-items: center;
      width: 100%;
      cursor: pointer;
      text-align: left;
      font-size: 12px;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
    }
    button.active {
      border-color: rgba(255, 255, 255, 0.45);
      background: rgba(255, 255, 255, 0.09);
    }
    .kind,
    .count {
      opacity: 0.8;
      white-space: nowrap;
    }
    .name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    :host-context(body.theme-shenzhen) {
      border-color: #335145;
      background: #0d1a1a;
    }
    :host-context(body.theme-shenzhen) .search {
      background: linear-gradient(180deg, rgba(13, 26, 26, 0.98), rgba(13, 26, 26, 0.86));
    }
    :host-context(body.theme-shenzhen) .search input,
    :host-context(body.theme-shenzhen) .search button {
      border-color: #35564a;
      background: #142523;
      color: #dce7dd;
    }
    :host-context(body.theme-shenzhen) button {
      color: #cad9d0;
    }
    :host-context(body.theme-shenzhen) button:hover {
      border-color: #5eaa84;
      background: #1a342c;
    }
    :host-context(body.theme-shenzhen) button.active {
      border-color: #87edb4;
      background: #27523f;
      color: #f1fff7;
    }
    :host-context(body.theme-shenzhen) .kind {
      color: #98afa2;
    }
  `;

  constructor() {
    super();
    this.rows = [];
    this.parseError = '';
    this.filterText = '';
  }

  setTree(rows, parseError = '') {
    this.rows = Array.isArray(rows) ? rows.slice() : [];
    this.parseError = String(parseError || '');
  }

  setFilter(filterText = '', emit = false) {
    const next = String(filterText || '').trim();
    if (this.filterText === next) {
      return;
    }
    this.filterText = next;
    if (emit) {
      this.dispatchEvent(new CustomEvent('component-filter-change', {
        detail: { filter: next },
        bubbles: true,
        composed: true
      }));
    }
  }

  getFilter() {
    return String(this.filterText || '');
  }

  selectNode(nodeId) {
    this.dispatchEvent(new CustomEvent('component-select', {
      detail: { nodeId },
      bubbles: true,
      composed: true
    }));
  }

  onFilterInput(event) {
    this.setFilter(event?.target?.value || '', true);
  }

  clearFilter() {
    this.setFilter('', true);
  }

  render() {
    const body = this.parseError
      ? html`<div class="empty">${this.parseError}</div>`
      : (this.rows.length
        ? html`
            <div class="tree">
              ${this.rows.map((row) => html`
                <button
                  type="button"
                  class=${row.isActive ? 'active' : ''}
                  style=${`padding-left:${8 + (row.depth * 16)}px`}
                  @click=${() => this.selectNode(row.nodeId)}
                >
                  <span class="name">${row.name}</span>
                  <span class="kind">[${row.kind}]</span>
                  <span class="count">${row.childCount}c ${row.signalCount}s</span>
                </button>
              `)}
            </div>
          `
        : html`<div class="empty">Load valid IR to explore components.</div>`);

    return html`
      <div class="search">
        <input
          type="text"
          placeholder="Search components/signals"
          .value=${this.filterText}
          @input=${(event) => this.onFilterInput(event)}
        />
        <button type="button" @click=${() => this.clearFilter()}>Clear</button>
      </div>
      ${body}
    `;
  }
}

class RhdlComponentCodeViewer extends LitElement {
  static properties = {
    rhdlText: { state: true },
    verilogText: { state: true },
    view: { state: true }
  };

  static styles = css`
    :host {
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      gap: 8px;
      min-height: 0;
      height: 100%;
    }
    .header {
      display: flex;
      align-items: center;
      gap: 8px;
      margin: 0;
    }
    .title {
      margin: 0;
      font-size: 0.9rem;
      color: #3dd7c2;
      text-transform: uppercase;
      letter-spacing: 0.02em;
      font-weight: 700;
    }
    .btn {
      border: 1px solid #2a4f72;
      border-radius: 6px;
      background: #132846;
      color: #bed4ee;
      font-size: 0.75rem;
      padding: 0.28rem 0.6rem;
      cursor: pointer;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
    }
    .btn.active {
      background: #1f6b60;
      border-color: #2d9888;
      color: #e9fffa;
    }
    pre {
      margin: 0;
      min-height: 0;
      height: 100%;
      max-height: none;
      overflow: auto;
      border: 1px solid #2a4a67;
      border-radius: 8px;
      padding: 10px;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 0.75rem;
      line-height: 1.35;
      background: #081524;
      color: #d6e6f9;
      white-space: pre;
    }
    :host-context(body.theme-shenzhen) .title {
      color: #8ef2b8;
      font-family: var(--mono, 'Share Tech Mono', monospace);
      letter-spacing: 0.05em;
    }
    :host-context(body.theme-shenzhen) .btn {
      background: linear-gradient(180deg, #1a2f29 0%, #12201d 100%);
      border-color: #3e6656;
      color: #c8d8cf;
    }
    :host-context(body.theme-shenzhen) .btn.active {
      background: linear-gradient(180deg, #355e45 0%, #244337 100%);
      border-color: #83e9b2;
      color: #f0fff7;
    }
    :host-context(body.theme-shenzhen) pre {
      border-color: #335145;
      background: #0d1a1a;
      font-family: var(--mono, 'Share Tech Mono', monospace);
      font-variant-numeric: tabular-nums;
    }
  `;

  constructor() {
    super();
    this.rhdlText = 'Select a component to view details.';
    this.verilogText = 'Select a component to view details.';
    this.view = 'rhdl';
  }

  normalizeView(view) {
    return view === 'verilog' ? 'verilog' : 'rhdl';
  }

  getView() {
    return this.normalizeView(this.view);
  }

  setView(view, emit = false) {
    const next = this.normalizeView(view);
    if (this.view === next) {
      return;
    }
    this.view = next;
    if (emit) {
      this.dispatchEvent(new CustomEvent('component-code-view-change', {
        detail: { view: next },
        bubbles: true,
        composed: true
      }));
    }
  }

  setCodeTexts({ rhdl = '', verilog = '' } = {}) {
    this.rhdlText = String(rhdl || '');
    this.verilogText = String(verilog || '');
  }

  render() {
    const view = this.getView();
    const text = view === 'verilog' ? this.verilogText : this.rhdlText;
    return html`
      <div class="header">
        <h2 class="title">Source</h2>
        <button
          type="button"
          class=${`btn${view === 'rhdl' ? ' active' : ''}`}
          @click=${() => this.setView('rhdl', true)}
        >RHDL</button>
        <button
          type="button"
          class=${`btn${view === 'verilog' ? ' active' : ''}`}
          @click=${() => this.setView('verilog', true)}
        >Verilog</button>
      </div>
      <pre>${text}</pre>
    `;
  }
}

class RhdlComponentSignalTable extends LitElement {
  static properties = {
    rows: { state: true },
    hiddenSignalCount: { state: true }
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
      width: 48%;
    }
    th:nth-child(2),
    td:nth-child(2) {
      width: 4.5rem;
      font-variant-numeric: tabular-nums;
    }
    th:nth-child(3),
    td:nth-child(3) {
      width: 38%;
      font-variant-numeric: tabular-nums;
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
    this.rows = [];
    this.hiddenSignalCount = 0;
  }

  setSignals(signalRows, hiddenSignalCount, formatValue) {
    const formatter = typeof formatValue === 'function' ? formatValue : (value) => String(value ?? '');
    this.rows = (signalRows || []).map((signal) => ({
      name: signal.fullName || signal.name,
      width: String(signal.width || 1),
      value: signal.value == null ? '-' : formatter(signal.value, signal.width || 1)
    }));
    this.hiddenSignalCount = Math.max(0, Number(hiddenSignalCount) || 0);
  }

  render() {
    return html`
      <table class="component-signal-table">
        <thead>
          <tr>
            <th>Signal</th>
            <th>Width</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          ${this.rows.map((row) => html`
            <tr>
              <td>${row.name}</td>
              <td>${row.width}</td>
              <td>${row.value}</td>
            </tr>
          `)}
          ${this.hiddenSignalCount > 0 ? html`
            <tr>
              <td colspan="3">${`... ${this.hiddenSignalCount} additional signals not shown`}</td>
            </tr>
          ` : ''}
        </tbody>
      </table>
    `;
  }
}

if (!customElements.get('rhdl-component-tree')) {
  customElements.define('rhdl-component-tree', RhdlComponentTree);
}
if (!customElements.get('rhdl-component-signal-table')) {
  customElements.define('rhdl-component-signal-table', RhdlComponentSignalTable);
}
if (!customElements.get('rhdl-component-code-viewer')) {
  customElements.define('rhdl-component-code-viewer', RhdlComponentCodeViewer);
}

export function renderComponentTreeRows(dom, treeRows, parseError) {
  const element = dom?.componentTree;
  if (!element) {
    return;
  }
  if (typeof element.setTree === 'function') {
    element.setTree(treeRows, parseError);
  }
}

export function renderComponentInspectorView({
  dom,
  node,
  parseError,
  signalRows,
  hiddenSignalCount,
  codeTextRhdl,
  codeTextVerilog,
  title,
  metaText,
  signalMetaText,
  formatValue
}) {
  if (!dom?.componentTitle || !dom?.componentMeta || !dom?.componentSignalBody || !dom?.componentCode) {
    return;
  }

  if (!node) {
    dom.componentTitle.textContent = 'Component Details';
    dom.componentMeta.textContent = parseError || 'Load IR to inspect components.';
    if (dom.componentSignalMeta) {
      dom.componentSignalMeta.textContent = parseError || '';
    }
    if (typeof dom.componentSignalBody.setSignals === 'function') {
      dom.componentSignalBody.setSignals([], 0, formatValue);
    }
    if (typeof dom.componentCode.setCodeTexts === 'function') {
      dom.componentCode.setCodeTexts({
        rhdl: 'Select a component to view details.',
        verilog: 'Select a component to view details.'
      });
    } else {
      dom.componentCode.textContent = 'Select a component to view details.';
    }
    return;
  }

  dom.componentTitle.textContent = String(title || node.name || 'Component Details');
  dom.componentMeta.textContent = String(metaText || '');
  if (dom.componentSignalMeta) {
    dom.componentSignalMeta.textContent = String(signalMetaText || '');
  }

  if (typeof dom.componentSignalBody.setSignals === 'function') {
    dom.componentSignalBody.setSignals(signalRows, hiddenSignalCount, formatValue);
  }

  if (typeof dom.componentCode.setCodeTexts === 'function') {
    dom.componentCode.setCodeTexts({
      rhdl: String(codeTextRhdl || ''),
      verilog: String(codeTextVerilog || '')
    });
  } else {
    dom.componentCode.textContent = String(codeTextRhdl || '');
  }
}
