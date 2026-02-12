import { LitElement, html, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

class RhdlMemoryView extends LitElement {
  static properties = {
    dumpText: { state: true },
    disasmText: { state: true },
    dumpRows: { state: true },
    followPc: { state: true },
    pcAddress: { state: true },
    windowStart: { state: true },
    addressSpace: { state: true },
    bytesPerRow: { state: true }
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
      max-height: 62vh;
      white-space: pre;
    }
    .changed-byte {
      border-radius: 3px;
      font-weight: 600;
      text-shadow: 0 0 6px rgba(255, 255, 255, 0.15);
    }
    .byte-read {
      background: rgba(57, 255, 20, 0.82);
      color: #001407;
      box-shadow: 0 0 0 1px rgba(57, 255, 20, 0.95), 0 0 12px rgba(57, 255, 20, 0.75);
    }
    .byte-write {
      background: rgba(255, 48, 48, 0.82);
      color: #1a0303;
      box-shadow: 0 0 0 1px rgba(255, 48, 48, 0.95), 0 0 12px rgba(255, 48, 48, 0.75);
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
    this.dumpRows = [];
    this.followPc = false;
    this.pcAddress = null;
    this.windowStart = 0;
    this.addressSpace = 0x10000;
    this.bytesPerRow = 16;
  }

  setViewModel(viewModel) {
    this.dumpText = String(viewModel?.dumpText || '');
    this.disasmText = String(viewModel?.disasmText || '');
    this.dumpRows = Array.isArray(viewModel?.dumpRows) ? viewModel.dumpRows : [];
    this.followPc = !!viewModel?.followPc;
    this.pcAddress = Number.isFinite(viewModel?.pcAddress) ? Number(viewModel.pcAddress) : null;
    this.windowStart = Number.isFinite(viewModel?.windowStart) ? Number(viewModel.windowStart) : 0;
    this.addressSpace = Number.isFinite(viewModel?.addressSpace) && Number(viewModel.addressSpace) > 0
      ? Number(viewModel.addressSpace)
      : 0x10000;
    this.bytesPerRow = Number.isFinite(viewModel?.bytesPerRow) && Number(viewModel.bytesPerRow) > 0
      ? Number(viewModel.bytesPerRow)
      : 16;
  }

  updated(changed) {
    if (!this.followPc || this.pcAddress == null) {
      return;
    }
    if (
      changed.has('followPc')
      || changed.has('pcAddress')
      || changed.has('windowStart')
      || changed.has('dumpRows')
      || changed.has('disasmText')
    ) {
      this.scrollToPcRow();
    }
  }

  scrollPreToLine(pre, lineIndex) {
    if (!pre || !Number.isFinite(lineIndex) || lineIndex < 0) {
      return;
    }
    const lineHeight = Number.parseFloat(globalThis.getComputedStyle(pre).lineHeight) || 16;
    const target = Math.max(0, (lineIndex * lineHeight) - ((pre.clientHeight - lineHeight) / 2));
    pre.scrollTop = target;
  }

  scrollToPcRow() {
    const memoryPre = this.renderRoot?.querySelector('#memoryDumpPre');
    const disasmPre = this.renderRoot?.querySelector('#memoryDisasmPre');
    if (!memoryPre && !disasmPre) {
      return;
    }

    const addrSpace = Math.max(1, Number(this.addressSpace) || 0x10000);
    const start = ((Number(this.windowStart) % addrSpace) + addrSpace) % addrSpace;
    const pc = ((Number(this.pcAddress) % addrSpace) + addrSpace) % addrSpace;
    const rowSpan = Math.max(1, Number(this.bytesPerRow) || 16);
    const rowIndex = Math.floor(((pc - start + addrSpace) % addrSpace) / rowSpan);

    this.scrollPreToLine(memoryPre, rowIndex);
    this.scrollPreToLine(disasmPre, rowIndex);
  }

  renderDumpRows() {
    if (!Array.isArray(this.dumpRows) || this.dumpRows.length === 0) {
      return this.dumpText;
    }

    return this.dumpRows.map((row, rowIndex) => html`${row.marker} ${row.addressHex}: ${row.bytes.map((byte, idx) => {
      const classes = [];
      if (byte.changed) {
        classes.push('changed-byte');
      }
      if (byte.accessType === 'read') {
        classes.push('byte-read');
      }
      if (byte.accessType === 'write') {
        classes.push('byte-write');
      }
      return html`${classes.length > 0 ? html`<span class=${classes.join(' ')}>${byte.hex}</span>` : byte.hex}${idx < row.bytes.length - 1 ? ' ' : ''}`;
    })}  ${row.ascii}${rowIndex < this.dumpRows.length - 1 ? '\n' : ''}`);
  }

  render() {
    return html`
      <div class="memory-split">
        <pre id="memoryDumpPre">${this.renderDumpRows()}</pre>
        <pre id="memoryDisasmPre">${this.disasmText}</pre>
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
