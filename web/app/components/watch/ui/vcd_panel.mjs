import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

class RhdlWatchTable extends LitElement {
  static properties = {
    rows: { state: true }
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
    th:nth-child(1), td:nth-child(1) {
      width: 45%;
    }
    th:nth-child(2), td:nth-child(2) {
      width: 4.5rem;
      font-variant-numeric: tabular-nums;
    }
    th:nth-child(3), td:nth-child(3) {
      width: 45%;
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
  }

  setRows(rows, formatValue) {
    const formatter = typeof formatValue === 'function' ? formatValue : (value) => String(value ?? '');
    this.rows = (rows || []).map((row) => ({
      ...row,
      renderedValue: formatter(row.value, row.width)
    }));
  }

  render() {
    return html`
      <table class="watch-values-table">
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
              <td>${row.renderedValue}</td>
            </tr>
          `)}
        </tbody>
      </table>
    `;
  }
}

class RhdlWatchList extends LitElement {
  static properties = {
    names: { state: true }
  };

  static styles = css`
    :host { display: block; }
    ul {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: 6px;
    }
    li {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 6px 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 8px;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
      overflow: hidden;
    }
    .name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      flex: 1;
    }
    button {
      border: 1px solid rgba(255, 255, 255, 0.2);
      background: rgba(0, 0, 0, 0.25);
      color: inherit;
      border-radius: 6px;
      cursor: pointer;
      line-height: 1;
      width: 22px;
      height: 22px;
      padding: 0;
    }
    :host-context(body.theme-shenzhen) li {
      border-color: #40695a;
      background: #173129;
    }
  `;

  constructor() {
    super();
    this.names = [];
  }

  setNames(names) {
    this.names = Array.isArray(names) ? names.slice() : [];
  }

  onRemove(name) {
    this.dispatchEvent(new CustomEvent('watch-remove', {
      detail: { name },
      bubbles: true,
      composed: true
    }));
  }

  render() {
    return html`
      <ul class="pill-list">
        ${this.names.map((name) => html`
          <li>
            <span class="name">${name}</span>
            <button type="button" title="remove" @click=${() => this.onRemove(name)}>x</button>
          </li>
        `)}
      </ul>
    `;
  }
}

class RhdlBreakpointList extends LitElement {
  static properties = {
    rows: { state: true }
  };

  static styles = css`
    :host { display: block; }
    ul {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: 6px;
    }
    li {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 6px 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 8px;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
      overflow: hidden;
    }
    .name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      flex: 1;
    }
    button {
      border: 1px solid rgba(255, 255, 255, 0.2);
      background: rgba(0, 0, 0, 0.25);
      color: inherit;
      border-radius: 6px;
      cursor: pointer;
      line-height: 1;
      width: 22px;
      height: 22px;
      padding: 0;
    }
    :host-context(body.theme-shenzhen) li {
      border-color: #40695a;
      background: #173129;
    }
  `;

  constructor() {
    super();
    this.rows = [];
  }

  setBreakpoints(breakpoints, formatValue) {
    const formatter = typeof formatValue === 'function' ? formatValue : (value) => String(value ?? '');
    this.rows = (breakpoints || []).map((bp) => ({
      name: bp.name,
      label: `${bp.name}=${formatter(bp.value, bp.width)}`
    }));
  }

  onRemove(name) {
    this.dispatchEvent(new CustomEvent('breakpoint-remove', {
      detail: { name },
      bubbles: true,
      composed: true
    }));
  }

  render() {
    return html`
      <ul class="pill-list">
        ${this.rows.map((row) => html`
          <li>
            <span class="name">${row.label}</span>
            <button type="button" title="remove" @click=${() => this.onRemove(row.name)}>x</button>
          </li>
        `)}
      </ul>
    `;
  }
}

if (!customElements.get('rhdl-watch-table')) {
  customElements.define('rhdl-watch-table', RhdlWatchTable);
}
if (!customElements.get('rhdl-watch-list')) {
  customElements.define('rhdl-watch-list', RhdlWatchList);
}
if (!customElements.get('rhdl-breakpoint-list')) {
  customElements.define('rhdl-breakpoint-list', RhdlBreakpointList);
}

export function renderWatchTableRows(dom, rows, formatValue) {
  const element = dom?.watchTableBody;
  if (!element) {
    return;
  }
  if (typeof element.setRows === 'function') {
    element.setRows(rows, formatValue);
  }
}

export function renderWatchListItems(dom, names) {
  const element = dom?.watchList;
  if (!element) {
    return;
  }
  if (typeof element.setNames === 'function') {
    element.setNames(names);
  }
}

export function renderBreakpointListItems(dom, breakpoints, formatValue) {
  const element = dom?.bpList;
  if (!element) {
    return;
  }
  if (typeof element.setBreakpoints === 'function') {
    element.setBreakpoints(breakpoints, formatValue);
  }
}
