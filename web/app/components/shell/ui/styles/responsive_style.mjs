export const SHELL_RESPONSIVE_STYLE = String.raw`  @media (max-width: 980px) {
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

    .editor-top-layout {
      grid-template-columns: 1fr;
    }

    #editorTab {
      grid-template-rows: auto auto;
    }

    .editor-vim-wrap,
    .editor-vim-canvas,
    .editor-terminal-output,
    .editor-canvas-wrap {
      min-height: 300px;
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
  }`;
