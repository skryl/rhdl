import { BrowserWindow, type BrowserWindowConfig } from "electrobun/bun";

const windowConfig: BrowserWindowConfig = {
  title: "RHDL Simulator",
  url: "views://simulator/index.html",
  frame: {
    width: 1400,
    height: 900,
    x: 100,
    y: 100,
  },
};

const mainWindow = new BrowserWindow(windowConfig);

mainWindow.on("dom-ready", () => {
  // Enable cross-origin isolation for SharedArrayBuffer (required by WASM backends).
  // The native webview should handle this via response headers, but we also inject
  // the meta tags as a belt-and-suspenders approach.
  mainWindow.webview.executeJavaScript(`
    if (!window.crossOriginIsolated) {
      console.warn('[RHDL Desktop] crossOriginIsolated is false; WASM SharedArrayBuffer may not work.');
    }
  `);
});
