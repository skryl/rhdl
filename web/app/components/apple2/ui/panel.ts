import { LitElement, html, css } from 'lit';

class RhdlApple2Debug extends LitElement {
  [key: string]: unknown;
  declare rows: Array<[string, string]>;
  declare enabled: boolean;
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

  setData(rows: unknown, enabled: unknown) {
    this.rows = Array.isArray(rows)
      ? rows.map((row) => {
          const pair = Array.isArray(row) ? row : [];
          const name = String(pair[0] ?? '-');
          const value = String(pair[1] ?? '');
          return [name, value] as [string, string];
        })
      : [];
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

export function renderApple2DebugRows(dom: Unsafe, rows: unknown, speakerText: unknown, apple2Enabled: unknown) {
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
