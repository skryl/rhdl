import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

class RhdlApple2Debug extends LitElement {
  static properties = {
    rows: { state: true },
    enabled: { state: true }
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
    th:first-child,
    td:first-child {
      width: 9.5rem;
      white-space: nowrap;
    }
    th:last-child,
    td:last-child {
      width: 8.5rem;
      white-space: nowrap;
      font-variant-numeric: tabular-nums;
    }
    .empty {
      padding: 6px 8px;
      opacity: 0.8;
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
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
    this.enabled = false;
  }

  setData(rows, enabled) {
    this.rows = Array.isArray(rows) ? rows.slice() : [];
    this.enabled = !!enabled;
  }

  render() {
    if (!this.enabled) {
      return html`<div class="empty">Apple II runner inactive</div>`;
    }
    return html`
      <table class="runner-debug-table">
        <thead>
          <tr>
            <th>Signal</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          ${this.rows.map(([name, value]) => html`
            <tr>
              <td>${name}</td>
              <td>${value}</td>
            </tr>
          `)}
        </tbody>
      </table>
    `;
  }
}

if (!customElements.get('rhdl-apple2-debug')) {
  customElements.define('rhdl-apple2-debug', RhdlApple2Debug);
}

export function renderApple2DebugRows(dom, rows, speakerText, apple2Enabled) {
  const element = dom?.apple2DebugBody;
  if (element && typeof element.setData === 'function') {
    element.setData(rows, apple2Enabled);
  }

  if (dom?.apple2SpeakerToggles) {
    dom.apple2SpeakerToggles.textContent = apple2Enabled
      ? String(speakerText || 'Speaker toggles: -')
      : 'Speaker toggles: -';
  }
}
