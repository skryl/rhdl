export const SHELL_THEME_STYLE = String.raw`  body.theme-shenzhen {
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
  }`;
