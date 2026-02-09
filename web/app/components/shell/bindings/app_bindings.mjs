import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

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

  listeners.on(dom.loadRunnerBtn, 'click', () => {
    runner.loadPreset();
  });

  listeners.on(dom.sidebarToggleBtn, 'click', () => {
    shell.setSidebarCollapsed(!state.sidebarCollapsed);
  });

  listeners.on(dom.terminalToggleBtn, 'click', () => {
    shell.setTerminalOpen(!state.terminalOpen, { focus: true });
  });

  listeners.on(dom.terminalRunBtn, 'click', () => {
    shell.submitTerminalInput();
  });

  listeners.on(dom.terminalInput, 'keydown', async (event) => {
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
    }
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
    listeners.dispose();
  };
}
