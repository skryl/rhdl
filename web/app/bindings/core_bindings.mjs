import { createListenerGroup } from './listener_bindings.mjs';

export function bindCoreBindings({ dom, state, actions }) {
  const listeners = createListenerGroup();

  listeners.on(dom.loadRunnerBtn, 'click', () => {
    actions.loadRunnerPreset();
  });

  listeners.on(dom.sidebarToggleBtn, 'click', () => {
    actions.setSidebarCollapsed(!state.sidebarCollapsed);
  });

  listeners.on(dom.terminalToggleBtn, 'click', () => {
    actions.setTerminalOpen(!state.terminalOpen, { focus: true });
  });

  listeners.on(dom.terminalRunBtn, 'click', () => {
    actions.submitTerminalInput();
  });

  listeners.on(dom.terminalInput, 'keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await actions.submitTerminalInput();
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      actions.terminalHistoryNavigate(-1);
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      actions.terminalHistoryNavigate(1);
    }
  });

  listeners.on(dom.themeSelect, 'change', () => {
    actions.applyTheme(dom.themeSelect.value);
  });

  listeners.on(dom.backendSelect, 'change', async () => {
    const next = actions.getBackendDef(dom.backendSelect.value).id;
    if (state.backend === next) {
      actions.refreshStatus();
      return;
    }

    actions.setBackendState(next);
    try {
      await actions.ensureBackendInstance(state.backend);
      dom.simStatus.textContent = `WASM ready (${state.backend})`;
      if (String(dom.irJson?.value || '').trim()) {
        const preset = actions.currentRunnerPreset();
        if (preset.usesManualIr) {
          await actions.initializeSimulator({ preset });
        } else {
          const bundle = await actions.loadRunnerIrBundle(preset, { logLoad: false });
          await actions.initializeSimulator({
            preset,
            simJson: bundle.simJson,
            explorerSource: bundle.explorerJson,
            explorerMeta: bundle.explorerMeta,
            componentSourceBundle: bundle.sourceBundle || null,
            componentSchematicBundle: bundle.schematicBundle || null
          });
        }
      } else {
        actions.refreshStatus();
      }
      actions.log(`Switched backend to ${state.backend}`);
    } catch (err) {
      dom.simStatus.textContent = `Backend ${state.backend} unavailable: ${err.message || err}`;
      actions.log(`Backend load failed (${state.backend}): ${err.message || err}`);
      if (dom.backendStatus) {
        dom.backendStatus.textContent = `Backend: ${state.backend} (unavailable)`;
      }
    }
  });

  listeners.on(dom.runnerSelect, 'change', () => {
    actions.setRunnerPresetState(actions.getRunnerPreset(dom.runnerSelect.value).id);
    actions.updateIrSourceVisibility();
    actions.refreshStatus();
  });

  listeners.on(dom.loadSampleBtn, 'click', () => {
    if (!actions.currentRunnerPreset().usesManualIr) {
      return;
    }
    actions.loadSample();
  });

  listeners.on(dom.sampleSelect, 'change', () => {
    if (!actions.currentRunnerPreset().usesManualIr) {
      return;
    }
    actions.loadSample();
  });

  const tabButtons = Array.isArray(dom.tabButtons) ? dom.tabButtons : [];
  for (const btn of tabButtons) {
    listeners.on(btn, 'click', () => {
      const tabId = btn.dataset.tab;
      if (!tabId) {
        return;
      }
      actions.setActiveTab(tabId);
      if (tabId === 'memoryTab') {
        actions.refreshMemoryView();
      } else if (tabId === 'componentTab' || tabId === 'componentGraphTab') {
        actions.refreshComponentExplorer();
      }
    });
  }

  return () => {
    listeners.dispose();
  };
}
