import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

const TERMINAL_MIN_HEIGHT_PX = 260;
const TERMINAL_VIEWPORT_MARGIN_PX = 140;

function isTerminalTextEntryKey(event) {
  if (!event || typeof event.key !== 'string') {
    return false;
  }
  if (event.ctrlKey || event.metaKey || event.altKey) {
    return false;
  }
  return event.key.length === 1;
}

export function bindCoreBindings({
  dom,
  state,
  shell,
  runner,
  sim,
  apple2,
  components,
  store,
  util,
  log
}) {
  const listeners = createListenerGroup();
  const globalWindow = globalThis.window;
  const globalDocument = globalThis.document;
  const resizeState = {
    active: false,
    startY: 0,
    startHeight: 0
  };

  function terminalMaxHeightPx() {
    const viewportHeight = Number(globalWindow?.innerHeight || 0);
    if (!Number.isFinite(viewportHeight) || viewportHeight <= 0) {
      return TERMINAL_MIN_HEIGHT_PX;
    }
    return Math.max(
      TERMINAL_MIN_HEIGHT_PX,
      viewportHeight - TERMINAL_VIEWPORT_MARGIN_PX
    );
  }

  function clampTerminalHeight(px) {
    const maxPx = terminalMaxHeightPx();
    return Math.max(TERMINAL_MIN_HEIGHT_PX, Math.min(maxPx, Math.round(px)));
  }

  function stopTerminalResize() {
    if (!resizeState.active) {
      return;
    }
    resizeState.active = false;
    globalDocument?.body?.classList?.remove('terminal-resizing');
    if (globalWindow && typeof globalWindow.dispatchEvent === 'function') {
      const ResizeEventCtor = globalWindow.Event || globalThis.Event;
      if (typeof ResizeEventCtor === 'function') {
        globalWindow.dispatchEvent(new ResizeEventCtor('resize'));
      }
    }
  }

  listeners.on(dom.loadRunnerBtn, 'click', () => {
    runner.loadPreset();
  });

  listeners.on(dom.sidebarToggleBtn, 'click', () => {
    shell.setSidebarCollapsed(!state.sidebarCollapsed);
  });

  listeners.on(dom.terminalToggleBtn, 'click', () => {
    shell.setTerminalOpen(!state.terminalOpen, { focus: true });
  });

  listeners.on(dom.terminalResizeHandle, 'mousedown', (event) => {
    if (!dom.terminalPanel || event.button !== 0) {
      return;
    }
    const rect = dom.terminalPanel.getBoundingClientRect();
    resizeState.active = true;
    resizeState.startY = event.clientY;
    resizeState.startHeight = rect.height;
    globalDocument?.body?.classList?.add('terminal-resizing');
    event.preventDefault();
  });

  listeners.on(globalWindow, 'mousemove', (event) => {
    if (!resizeState.active || !dom.terminalPanel) {
      return;
    }
    const delta = resizeState.startY - event.clientY;
    const nextHeight = clampTerminalHeight(resizeState.startHeight + delta);
    dom.terminalPanel.style.height = `${nextHeight}px`;
    dom.terminalPanel.style.maxHeight = `${terminalMaxHeightPx()}px`;
  });

  listeners.on(globalWindow, 'mouseup', () => {
    stopTerminalResize();
  });

  listeners.on(globalWindow, 'blur', () => {
    stopTerminalResize();
  });

  listeners.on(globalWindow, 'resize', () => {
    if (!dom.terminalPanel?.style?.height) {
      return;
    }
    const currentHeight = Number.parseFloat(dom.terminalPanel.style.height);
    if (!Number.isFinite(currentHeight)) {
      return;
    }
    dom.terminalPanel.style.height = `${clampTerminalHeight(currentHeight)}px`;
    dom.terminalPanel.style.maxHeight = `${terminalMaxHeightPx()}px`;
  });

  listeners.on(dom.terminalOutput, 'keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await shell.submitTerminalInput();
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      shell.terminalHistoryNavigate(-1);
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      shell.terminalHistoryNavigate(1);
      return;
    }
    if (event.key === 'Backspace') {
      event.preventDefault();
      shell.terminalBackspaceInput();
      return;
    }
    if (
      event.key === 'ArrowLeft'
      || event.key === 'ArrowRight'
      || event.key === 'Home'
      || event.key === 'End'
      || event.key === 'PageUp'
      || event.key === 'PageDown'
    ) {
      event.preventDefault();
      shell.terminalFocusInput();
      return;
    }
    if (isTerminalTextEntryKey(event)) {
      event.preventDefault();
      shell.terminalAppendInput(event.key);
    }
  });

  listeners.on(dom.terminalOutput, 'paste', (event) => {
    const pasted = String(event.clipboardData?.getData('text') || '');
    if (!pasted) {
      return;
    }
    event.preventDefault();
    shell.terminalAppendInput(pasted);
  });

  listeners.on(dom.terminalOutput, 'focus', () => {
    shell.terminalFocusInput();
  });

  listeners.on(dom.terminalOutput, 'mousedown', () => {
    setTimeout(() => {
      shell.terminalFocusInput();
    }, 0);
  });

  listeners.on(dom.themeSelect, 'change', () => {
    shell.applyTheme(dom.themeSelect.value);
  });

  listeners.on(dom.backendSelect, 'change', async () => {
    const next = util.getBackendDef(dom.backendSelect.value).id;
    if (state.backend === next) {
      sim.refreshStatus();
      return;
    }

    store.setBackendState(next);
    try {
      await runner.ensureBackendInstance(state.backend);
      dom.simStatus.textContent = `WASM ready (${state.backend})`;
      if (String(dom.irJson?.value || '').trim()) {
        const preset = runner.currentPreset();
        if (preset.usesManualIr) {
          await sim.initializeSimulator({ preset });
        } else {
          const bundle = await runner.loadBundle(preset, { logLoad: false });
          await sim.initializeSimulator({
            preset,
            simJson: bundle.simJson,
            explorerSource: bundle.explorerJson,
            explorerMeta: bundle.explorerMeta,
            componentSourceBundle: bundle.sourceBundle || null,
            componentSchematicBundle: bundle.schematicBundle || null
          });
        }
      } else {
        sim.refreshStatus();
      }
      log(`Switched backend to ${state.backend}`);
    } catch (err) {
      dom.simStatus.textContent = `Backend ${state.backend} unavailable: ${err.message || err}`;
      log(`Backend load failed (${state.backend}): ${err.message || err}`);
      if (dom.backendStatus) {
        dom.backendStatus.textContent = `Backend: ${state.backend} (unavailable)`;
      }
    }
  });

  listeners.on(dom.runnerSelect, 'change', () => {
    store.setRunnerPresetState(runner.getPreset(dom.runnerSelect.value).id);
    runner.updateIrSourceVisibility();
    sim.refreshStatus();
  });

  listeners.on(dom.loadSampleBtn, 'click', () => {
    if (!runner.currentPreset().usesManualIr) {
      return;
    }
    runner.loadSample();
  });

  listeners.on(dom.sampleSelect, 'change', () => {
    if (!runner.currentPreset().usesManualIr) {
      return;
    }
    runner.loadSample();
  });

  const tabButtons = Array.isArray(dom.tabButtons) ? dom.tabButtons : [];
  for (const btn of tabButtons) {
    listeners.on(btn, 'click', () => {
      const tabId = btn.dataset.tab;
      if (!tabId) {
        return;
      }
      shell.setActiveTab(tabId);
      if (tabId === 'memoryTab') {
        apple2.refreshMemoryView();
      } else if (tabId === 'componentTab' || tabId === 'componentGraphTab') {
        components.refreshExplorer();
      }
    });
  }

  return () => {
    stopTerminalResize();
    listeners.dispose();
  };
}
