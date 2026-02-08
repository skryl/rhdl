import { LitElement, css } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';

const SHELL_STYLES = css`
  :root {
    --bg-0: #07111f;
    --bg-1: #0f1e33;
    --bg-2: #132741;
    --line: #274261;
    --text: #eaf3ff;
    --muted: #99aec8;
    --accent: #3dd7c2;
    --warn: #ffbc5a;
    --danger: #ff6f6f;
  }

  * {
    box-sizing: border-box;
  }

  body {
    margin: 0;
    min-height: 100vh;
    font-family: 'Space Grotesk', sans-serif;
    color: var(--text);
    background: radial-gradient(circle at 10% 10%, #12345d 0%, var(--bg-0) 45%, #050a12 100%);
  }

  h1,
  h2 {
    margin: 0;
    font-weight: 700;
    letter-spacing: 0.02em;
  }

  h1 {
    font-size: 1.25rem;
  }

  h2 {
    font-size: 0.9rem;
    margin-bottom: 0.45rem;
    color: var(--accent);
    text-transform: uppercase;
  }

  .collapsible-panel {
    position: relative;
  }

  .panel-header-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 0.45rem;
  }

  .panel-header-row.panel-drag-handle {
    cursor: grab;
    user-select: none;
  }

  .panel-header-row.panel-drag-handle:active {
    cursor: grabbing;
  }

  .panel-header-row .panel-header-title {
    margin: 0;
    min-width: 0;
  }

  .panel-collapse-btn {
    margin-left: auto;
    width: 1.8rem;
    height: 1.8rem;
    border-radius: 6px;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 1px solid #274a67;
    background: #0f2238;
    color: #c6d8ec;
    cursor: pointer;
  }

  .panel-collapse-btn::before {
    content: '';
    width: 0.55rem;
    height: 0.55rem;
    border-radius: 50%;
    border: 1.5px solid currentColor;
    background: currentColor;
  }

  .panel-collapse-btn.is-collapsed::before {
    background: transparent;
  }

  .panel-collapse-btn:hover {
    background: #173559;
  }

  .panel-collapse-btn:focus-visible {
    outline: 1px solid #6fb9ff;
    outline-offset: 1px;
  }

  .collapsible-panel.is-collapsed > :not(.panel-header-row) {
    display: none !important;
  }

  .collapsible-panel.is-collapsed {
    min-height: 0 !important;
    height: auto !important;
  }

  .dashboard-layout-root {
    --dashboard-columns: 2;
    grid-template-columns: repeat(var(--dashboard-columns), minmax(0, 1fr));
    grid-auto-flow: row;
    gap: 10px;
    align-items: stretch;
    position: relative;
  }

  .controls-dashboard-root {
    display: grid;
  }

  .dashboard-layout-root > .dashboard-panel {
    min-width: 0;
    grid-column: span 1;
    align-self: stretch;
  }

  .dashboard-layout-root > .dashboard-panel[data-layout-span='full'] {
    grid-column: 1 / -1;
  }

  .dashboard-layout-root > .dashboard-static {
    min-width: 0;
    grid-column: 1 / -1;
  }

  .dashboard-panel.is-dragging {
    opacity: 0.62;
  }

  .dashboard-panel.dashboard-row-sized {
    min-height: var(--dashboard-row-height);
  }

  .dashboard-row-resize-handle {
    position: absolute;
    height: 8px;
    cursor: ns-resize;
    z-index: 35;
    border-radius: 999px;
    background: transparent;
  }

  .dashboard-row-resize-handle::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    top: 3px;
    border-top: 1px solid rgba(191, 212, 235, 0.24);
  }

  .dashboard-row-resize-handle:hover {
    background: transparent;
  }

  .dashboard-panel.dashboard-drop-target.drop-left {
    box-shadow: inset 5px 0 0 rgba(61, 215, 194, 0.95);
  }

  .dashboard-panel.dashboard-drop-target.drop-right {
    box-shadow: inset -5px 0 0 rgba(61, 215, 194, 0.95);
  }

  .dashboard-panel.dashboard-drop-target.drop-above {
    box-shadow: inset 0 5px 0 rgba(61, 215, 194, 0.95);
  }

  .dashboard-panel.dashboard-drop-target.drop-below {
    box-shadow: inset 0 -5px 0 rgba(61, 215, 194, 0.95);
  }

  .subtitle {
    margin: 0.25rem 0 0.9rem;
    color: var(--muted);
    font-size: 0.85rem;
  }

  .subtitle a {
    color: inherit;
    text-decoration: underline;
    text-decoration-thickness: 1px;
    text-underline-offset: 2px;
  }

  .app-shell {
    display: grid;
    grid-template-columns: 360px minmax(0, 1fr);
    gap: 14px;
    min-height: 100vh;
    padding: 14px;
  }

  .app-shell.controls-collapsed {
    grid-template-columns: minmax(0, 1fr);
  }

  .app-shell.controls-collapsed .controls {
    display: none;
  }

  .panel {
    background: linear-gradient(180deg, rgba(13, 27, 45, 0.95), rgba(7, 14, 23, 0.98));
    border: 1px solid var(--line);
    border-radius: 14px;
    backdrop-filter: blur(3px);
  }

  .controls {
    padding: 14px;
    overflow: auto;
  }

  .controls section {
    border-top: 1px solid #1f3651;
    margin-top: 0.9rem;
    padding-top: 0.9rem;
  }

  .viewer {
    padding: 10px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 0;
  }

  #terminalPanel[hidden] {
    display: none;
  }

  #canvasWrap {
    width: 100%;
    min-height: 340px;
    border: 1px solid #1e374f;
    border-radius: 10px;
    overflow: hidden;
  }

  .viewer-header {
    display: flex;
    gap: 10px;
    align-items: flex-end;
    justify-content: space-between;
    border-bottom: 1px solid #1f3651;
    padding-bottom: 8px;
    min-height: 42px;
  }

  .tabs {
    display: flex;
    gap: 8px;
    align-items: center;
    flex-wrap: wrap;
  }

  .viewer-toolbar {
    display: inline-flex;
    gap: 6px;
    align-items: center;
  }

  .toolbar-icon-btn {
    border: 1px solid #27597f;
    background: #123050;
    color: #d9ecff;
    font-weight: 700;
    width: 2rem;
    min-width: 2rem;
    height: 2rem;
    line-height: 1;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .toolbar-icon-btn.is-active {
    border-color: #2d9888;
    color: #e9fffa;
    background: #1f6b60;
  }

  .tab-btn {
    border: 1px solid #214566;
    background: #0f223a;
    color: #b7cde8;
  }

  .tab-btn.active {
    background: #1f6b60;
    color: #e9fffa;
    border-color: #2d9888;
  }

  .tab-panel {
    display: none;
    gap: 10px;
  }

  .tab-panel.active {
    display: grid;
    flex: 1 1 auto;
    min-height: 0;
  }

  .terminal-panel {
    border: 1px solid #1f3651;
    border-radius: 10px;
    background: rgba(7, 15, 25, 0.96);
    display: grid;
    grid-template-rows: auto minmax(130px, 1fr) auto;
    gap: 8px;
    padding: 10px;
    min-height: 210px;
    max-height: 42vh;
  }

  .terminal-panel-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
  }

  .terminal-panel-header h2 {
    margin: 0;
  }

  .terminal-output {
    margin: 0;
    border: 1px solid #28445d;
    border-radius: 8px;
    background: #071421;
    color: #b5d3ef;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.76rem;
    line-height: 1.35;
    padding: 8px;
    overflow: auto;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .terminal-input-row {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: 8px;
  }

  .terminal-prompt {
    font-family: 'IBM Plex Mono', monospace;
    color: #8fb8df;
    font-size: 0.9rem;
    line-height: 1;
  }

  .terminal-input-row input {
    font-family: 'IBM Plex Mono', monospace;
  }

  #vcdTab {
    grid-template-rows: minmax(320px, 1fr) auto auto;
  }

  #vcdTab.dashboard-layout-root {
    grid-template-rows: none;
    grid-auto-rows: auto;
  }

  .vcd-control-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }

  #componentTab {
    grid-template-rows: minmax(0, 1fr);
    min-height: 0;
  }

  #componentTab.dashboard-layout-root {
    grid-template-rows: none;
    grid-auto-rows: auto;
  }

  #componentTab.active {
    min-height: 0;
    height: 100%;
  }

  #componentGraphTab {
    grid-template-rows: minmax(560px, 1fr) auto;
    min-height: 620px;
  }

  #componentGraphTab.active {
    display: grid;
    flex: 1 1 auto;
    min-height: 620px;
  }

  #componentGraphTab.dashboard-layout-root {
    grid-template-rows: none;
    grid-auto-rows: auto;
  }

  .io-layout {
    display: grid;
    grid-template-columns: 1.2fr 0.9fr;
    gap: 10px;
    align-items: start;
  }

  .subpanel {
    border: 1px solid #1f3651;
    border-radius: 10px;
    padding: 10px;
    background: rgba(10, 20, 33, 0.75);
  }

  .screen-output {
    margin: 0;
    min-height: 470px;
    max-height: 64vh;
    overflow: auto;
    border: 1px solid #2a4a67;
    border-radius: 8px;
    padding: 10px;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.78rem;
    line-height: 1.3;
    letter-spacing: 0.01em;
    background: #041a20;
    color: #a4ffbf;
    outline: none;
    white-space: pre;
  }

  .screen-output:focus {
    border-color: #3dd7c2;
    box-shadow: 0 0 0 2px rgba(61, 215, 194, 0.16);
  }

  .io-toggle-row {
    margin-bottom: 10px;
  }

  .toggle-pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    border: 1px solid #2f5877;
    border-radius: 999px;
    padding: 4px 10px;
    background: #10273f;
    color: #bfd6f0;
    font-size: 0.75rem;
    min-width: 0;
  }

  .toggle-pill input[type='checkbox'] {
    width: auto;
    margin: 0;
  }

  .hires-canvas {
    width: 100%;
    max-width: 840px;
    aspect-ratio: 280 / 192;
    border: 1px solid #2a4a67;
    border-radius: 8px;
    background: #050c16;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }

  .memory-follow {
    min-width: 0;
  }

  .component-layout {
    display: grid;
    grid-template-columns: minmax(300px, 0.8fr) minmax(0, 1.2fr);
    gap: 10px;
    align-items: stretch;
    min-height: 0;
    height: 100%;
  }

  .component-left,
  .component-right {
    display: grid;
    gap: 10px;
    min-height: 0;
  }

  .component-left {
    grid-template-rows: minmax(260px, 1fr) auto;
  }

  .component-right {
    grid-template-rows: minmax(0, 1fr);
  }

  .component-tree-panel,
  .component-detail-panel,
  .component-visual-panel,
  .component-signal-panel {
    min-height: 0;
  }

  .component-detail-panel {
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    min-height: 0;
    height: 100%;
    overflow: hidden;
  }

  .component-code-viewer {
    min-height: 0;
    height: 100%;
  }

  .component-graph-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) auto;
    gap: 10px;
    min-height: 1040px;
    min-width: 720px;
    height: 100%;
    overflow: auto;
  }

  .component-graph-layout .component-visual-panel {
    min-height: 1000px;
    min-width: 700px;
    display: grid;
    grid-template-rows: auto auto auto minmax(0, 1fr);
  }

  .component-graph-layout .component-live-panel {
    min-height: 180px;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
  }

  .component-graph-layout .component-visual {
    min-height: 880px;
    min-width: 680px;
    max-height: none;
    height: 100%;
    overflow: hidden;
    padding: 0;
  }

  .component-graph-layout .component-live-signals {
    max-height: none;
    height: 100%;
  }

  .component-visual-panel {
    min-height: 1000px;
    min-width: 700px;
    display: grid;
    grid-template-rows: auto auto auto minmax(0, 1fr);
  }

  .component-live-panel {
    min-height: 180px;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
  }

  .component-visual-panel .component-visual {
    min-height: 880px;
    min-width: 680px;
    max-height: none;
    height: 100%;
    overflow: hidden;
    padding: 0;
  }

  .component-live-panel .component-live-signals {
    max-height: none;
    height: 100%;
  }

  .component-graph-controls {
    align-items: center;
    margin-bottom: 8px;
  }

  .component-graph-controls .status {
    margin-left: auto;
    white-space: nowrap;
  }

  .component-signal-scroll {
    max-height: 36vh;
    overflow: auto;
    border: 1px solid #29465f;
    border-radius: 8px;
    margin-bottom: 10px;
  }

  .component-connection-scroll {
    max-height: 28vh;
    overflow: auto;
    border: 1px solid #29465f;
    border-radius: 8px;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 7px;
  }

  .row.wrap {
    flex-wrap: wrap;
  }

  label {
    min-width: 64px;
    color: var(--muted);
    font-size: 0.82rem;
  }

  textarea,
  input,
  select,
  button {
    font-family: inherit;
    border-radius: 8px;
    border: 1px solid #244661;
    color: var(--text);
    background: #0d1e34;
  }

  textarea,
  input,
  select {
    padding: 0.45rem 0.55rem;
  }

  textarea {
    width: 100%;
    min-height: 160px;
    resize: vertical;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.76rem;
    line-height: 1.35;
  }

  input,
  select {
    width: 100%;
  }

  input[type='number'] {
    max-width: 90px;
  }

  button {
    cursor: pointer;
    padding: 0.45rem 0.65rem;
    font-size: 0.82rem;
    transition: background-color 120ms ease;
  }

  button:hover {
    background: #173559;
  }

  button.full {
    width: 100%;
    margin-top: 8px;
    background: #1f6b60;
    border-color: #2d9888;
  }

  .status {
    margin: 0.2rem 0;
    font-size: 0.76rem;
    color: var(--warn);
  }

  #eventLog {
    margin: 0;
    border: 1px solid #253e5e;
    border-radius: 8px;
    background: #0a1525;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.75rem;
    padding: 0.6rem;
    max-height: 200px;
    overflow: auto;
    color: #bfcbda;
  }

  .io-event-log #eventLog {
    min-height: 470px;
    max-height: 64vh;
  }

  @media (max-width: 980px) {
    .dashboard-layout-root {
      --dashboard-columns: 1;
    }

    .app-shell {
      grid-template-columns: 1fr;
    }

    .viewer-header {
      flex-direction: column;
      align-items: stretch;
    }

    .viewer-toolbar {
      justify-content: flex-end;
    }

    #vcdTab {
      grid-template-rows: 300px auto auto;
    }

    .vcd-control-grid {
      grid-template-columns: 1fr;
    }

    .io-layout {
      grid-template-columns: 1fr;
    }

    .component-layout {
      grid-template-columns: 1fr;
    }

    .component-graph-layout {
      grid-template-columns: 1fr;
      min-height: 0;
      min-width: 0;
      grid-template-rows: auto auto;
    }

    #componentGraphTab {
      grid-template-rows: auto auto;
      min-height: 0;
    }

    .component-left,
    .component-right {
      grid-template-rows: auto;
    }

    .screen-output,
    rhdl-memory-view,
    .component-code-viewer {
      min-height: 300px;
    }
  }

  body.theme-shenzhen {
    --bg-0: #0a1012;
    --bg-1: #111d1b;
    --bg-2: #162420;
    --line: #2f4a42;
    --text: #d8e3d8;
    --muted: #8ea398;
    --accent: #5ee3a1;
    --warn: #f4bf66;
    --danger: #e26f67;
    --mono: 'Share Tech Mono', monospace;
    --ui: 'Rajdhani', sans-serif;
  }

  body.theme-shenzhen {
    font-family: var(--ui);
    background:
      linear-gradient(180deg, rgba(0, 0, 0, 0.28), rgba(0, 0, 0, 0.58)),
      repeating-linear-gradient(
        180deg,
        rgba(116, 161, 133, 0.05) 0px,
        rgba(116, 161, 133, 0.05) 1px,
        transparent 1px,
        transparent 3px
      ),
      radial-gradient(circle at 15% -20%, #263a2f 0%, #121e1b 46%, #090f11 100%);
    color: var(--text);
  }

  body.theme-shenzhen h1,
  body.theme-shenzhen h2,
  body.theme-shenzhen label,
  body.theme-shenzhen .status,
  body.theme-shenzhen .tab-btn,
  body.theme-shenzhen .toolbar-icon-btn,
  body.theme-shenzhen button {
    font-family: var(--mono);
    letter-spacing: 0.05em;
  }

  body.theme-shenzhen h2 {
    color: #8ef2b8;
  }

  body.theme-shenzhen .subtitle {
    color: #9bb3a7;
  }

  body.theme-shenzhen .panel,
  body.theme-shenzhen .subpanel,
  body.theme-shenzhen .screen-output,
  body.theme-shenzhen #canvasWrap,
  body.theme-shenzhen textarea,
  body.theme-shenzhen input,
  body.theme-shenzhen select,
  body.theme-shenzhen button {
    border-radius: 2px;
  }

  body.theme-shenzhen .panel {
    background: linear-gradient(180deg, rgba(20, 33, 30, 0.96), rgba(9, 15, 16, 0.98));
    border: 1px solid #375248;
    box-shadow:
      inset 0 0 0 1px rgba(139, 196, 158, 0.08),
      0 14px 26px rgba(0, 0, 0, 0.36);
  }

  body.theme-shenzhen .controls section {
    border-top-color: #2a4038;
  }

  body.theme-shenzhen .viewer-header {
    border-bottom-color: #325043;
  }

  body.theme-shenzhen .tab-btn,
  body.theme-shenzhen .toolbar-icon-btn {
    background: linear-gradient(180deg, #1a2c28 0%, #111e1c 100%);
    border: 1px solid #3a5d4f;
    color: #c6d4cb;
    text-transform: uppercase;
  }

  body.theme-shenzhen .panel-collapse-btn {
    border-color: #3a5d4f;
    background: linear-gradient(180deg, #1a2c28 0%, #111e1c 100%);
    color: #c6d4cb;
  }

  body.theme-shenzhen .panel-collapse-btn:hover {
    background: #1d3630;
  }

  body.theme-shenzhen .dashboard-panel.dashboard-drop-target.drop-left {
    box-shadow: inset 5px 0 0 rgba(123, 226, 168, 0.95);
  }

  body.theme-shenzhen .dashboard-panel.dashboard-drop-target.drop-right {
    box-shadow: inset -5px 0 0 rgba(123, 226, 168, 0.95);
  }

  body.theme-shenzhen .dashboard-panel.dashboard-drop-target.drop-above {
    box-shadow: inset 0 5px 0 rgba(123, 226, 168, 0.95);
  }

  body.theme-shenzhen .dashboard-panel.dashboard-drop-target.drop-below {
    box-shadow: inset 0 -5px 0 rgba(123, 226, 168, 0.95);
  }

  body.theme-shenzhen .dashboard-row-resize-handle {
    background: transparent;
  }

  body.theme-shenzhen .dashboard-row-resize-handle::before {
    border-top-color: rgba(155, 179, 167, 0.26);
  }

  body.theme-shenzhen .tab-btn.active {
    background: linear-gradient(180deg, #365b44 0%, #223f33 100%);
    border-color: #70d89f;
    color: #f0fff6;
  }

  body.theme-shenzhen .toolbar-icon-btn.is-active {
    background: linear-gradient(180deg, #365b44 0%, #223f33 100%);
    border-color: #70d89f;
    color: #f0fff6;
  }

  body.theme-shenzhen .terminal-panel {
    border-color: #355147;
    background: linear-gradient(180deg, rgba(14, 27, 24, 0.96), rgba(10, 16, 15, 0.96));
  }

  body.theme-shenzhen .terminal-output {
    border-color: #3b5f52;
    background: #0b1917;
    color: #cee4d7;
  }

  body.theme-shenzhen .terminal-prompt {
    color: #8ef2b8;
  }

  body.theme-shenzhen .subpanel {
    border-color: #355147;
    background: linear-gradient(180deg, rgba(17, 30, 27, 0.9), rgba(10, 17, 17, 0.9));
  }

  body.theme-shenzhen #canvasWrap {
    border-color: #3c6554;
    background: #0b1917;
  }

  body.theme-shenzhen textarea,
  body.theme-shenzhen input,
  body.theme-shenzhen select,
  body.theme-shenzhen button {
    border: 1px solid #3b5f52;
    background: #142523;
    color: #dce7dd;
  }

  body.theme-shenzhen textarea:focus,
  body.theme-shenzhen input:focus,
  body.theme-shenzhen select:focus,
  body.theme-shenzhen button:focus {
    outline: 1px solid #7be2a8;
    outline-offset: 1px;
  }

  body.theme-shenzhen button:hover {
    background: #1d3630;
  }

  body.theme-shenzhen button.full {
    background: linear-gradient(180deg, #2f6c4d 0%, #1f4e39 100%);
    border-color: #8dedb6;
    color: #f3fff9;
  }

  body.theme-shenzhen .toggle-pill {
    border-color: #3b5f52;
    border-radius: 2px;
    background: #132420;
    color: #bdd0c5;
  }

  body.theme-shenzhen .screen-output,
  body.theme-shenzhen #eventLog,
  body.theme-shenzhen textarea {
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
  }

  body.theme-shenzhen .screen-output {
    border-color: #3f6c58;
    background:
      linear-gradient(180deg, rgba(0, 0, 0, 0.17), rgba(0, 0, 0, 0.24)),
      #041413;
    color: #8cfcb8;
  }

  body.theme-shenzhen .screen-output:focus {
    border-color: #78e9a9;
    box-shadow: 0 0 0 2px rgba(120, 233, 169, 0.18);
  }

  body.theme-shenzhen #eventLog,
  body.theme-shenzhen .component-signal-scroll,
  body.theme-shenzhen .component-connection-scroll {
    border-color: #335145;
    background: #0d1a1a;
  }
`;

class RhdlAppShell extends LitElement {
  createRenderRoot() {
    return this;
  }

  shouldUpdate() {
    return false;
  }

  connectedCallback() {
    super.connectedCallback();
    this.installStyles();
  }

  installStyles() {
    if (this.__shellStylesInstalled) {
      return;
    }
    const style = document.createElement('style');
    style.setAttribute('data-rhdl-app-shell-styles', '1');
    style.textContent = SHELL_STYLES.cssText;
    this.prepend(style);
    this.__shellStylesInstalled = true;
  }
}

if (!customElements.get('rhdl-app-shell')) {
  customElements.define('rhdl-app-shell', RhdlAppShell);
}
