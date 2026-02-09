import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

class RhdlMemoryView extends LitElement {
  static properties = {
    dumpText: { state: true },
    disasmText: { state: true }
  };

  static styles = css`
    :host {
      display: block;
      min-height: 280px;
    }
    .memory-split {
      display: grid;
      gap: 10px;
      grid-template-columns: 1fr 1fr;
      min-height: 280px;
    }
    pre {
      margin: 0;
      padding: 10px;
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 10px;
      background: rgba(0, 0, 0, 0.2);
      font-family: 'IBM Plex Mono', 'Share Tech Mono', monospace;
      font-size: 12px;
      line-height: 1.45;
      overflow: auto;
      min-height: 280px;
      white-space: pre;
    }
    @media (max-width: 980px) {
      .memory-split {
        grid-template-columns: 1fr;
      }
      pre {
        min-height: 180px;
      }
    }
  `;

  constructor() {
    super();
    this.dumpText = '';
    this.disasmText = '';
  }

  setViewModel(viewModel) {
    this.dumpText = String(viewModel?.dumpText || '');
    this.disasmText = String(viewModel?.disasmText || '');
  }

  render() {
    return html`
      <div class="memory-split">
        <pre>${this.dumpText}</pre>
        <pre>${this.disasmText}</pre>
      </div>
    `;
  }
}

if (!customElements.get('rhdl-memory-view')) {
  customElements.define('rhdl-memory-view', RhdlMemoryView);
}

export function renderMemoryPanel(dom, viewModel) {
  if (!dom) {
    return;
  }

  if (dom.memoryFollowPc) {
    dom.memoryFollowPc.disabled = !!viewModel.followDisabled;
    dom.memoryFollowPc.checked = !!viewModel.followChecked;
  }

  const element = dom.memoryDump;
  if (element && typeof element.setViewModel === 'function') {
    element.setViewModel(viewModel);
  }
}
