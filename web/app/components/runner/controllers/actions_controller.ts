import { fetchTextAsset } from '../../../core/lib/fetch_asset';
import { DEFAULT_SAMPLE_PATH } from '../config/presets';

function requireFn(name: Unsafe, fn: Unsafe) {
  if (typeof fn !== 'function') {
    throw new Error(`createRunnerActionsController requires function: ${name}`);
  }
}

export function createRunnerActionsController({
  dom,
  getRunnerPreset,
  setBackendState,
  ensureBackendInstance,
  setRunnerPresetState,
  updateIrSourceVisibility,
  loadRunnerIrBundle,
  initializeSimulator,
  applyRunnerDefaults,
  clearComponentSourceOverride,
  resetComponentExplorerState,
  log,
  isComponentTabActive,
  refreshComponentExplorer,
  clearComponentSourceBundle,
  clearComponentSchematicBundle,
  setComponentSourceBundle,
  setComponentSchematicBundle,
  setActiveTab,
  refreshStatus,
  fetchImpl = globalThis.fetch,
  requestFrame = globalThis.requestAnimationFrame,
  setTimeoutImpl = globalThis.setTimeout
}: Unsafe = {}) {
  if (!dom) {
    throw new Error('createRunnerActionsController requires dom');
  }
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('setBackendState', setBackendState);
  requireFn('ensureBackendInstance', ensureBackendInstance);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('updateIrSourceVisibility', updateIrSourceVisibility);
  requireFn('loadRunnerIrBundle', loadRunnerIrBundle);
  requireFn('initializeSimulator', initializeSimulator);
  requireFn('applyRunnerDefaults', applyRunnerDefaults);
  requireFn('clearComponentSourceOverride', clearComponentSourceOverride);
  requireFn('resetComponentExplorerState', resetComponentExplorerState);
  requireFn('log', log);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('clearComponentSourceBundle', clearComponentSourceBundle);
  requireFn('clearComponentSchematicBundle', clearComponentSchematicBundle);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('setActiveTab', setActiveTab);
  requireFn('refreshStatus', refreshStatus);
  requireFn('fetchImpl', fetchImpl);
  let runnerLoadInFlight = false;
  let explorerWarmupScheduled = false;

  async function applyPreferredBackend(preset: Unsafe) {
    const preferredBackend = String(preset?.preferredBackend || '').trim();
    if (!preferredBackend) {
      return;
    }

    if (dom.backendSelect && dom.backendSelect.value !== preferredBackend) {
      dom.backendSelect.value = preferredBackend;
    }

    setBackendState(preferredBackend);
    await ensureBackendInstance(preferredBackend);
  }

  async function waitForUiPaint() {
    await new Promise<void>((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) {
          return;
        }
        settled = true;
        resolve();
      };
      const fallbackTimer = (typeof globalThis.setTimeout === 'function')
        ? globalThis.setTimeout(finish, 120)
        : null;
      const finishWithFallbackClear = () => {
        if (fallbackTimer != null && typeof globalThis.clearTimeout === 'function') {
          globalThis.clearTimeout(fallbackTimer);
        }
        finish();
      };
      if (typeof requestFrame === 'function') {
        requestFrame(() => {
          if (typeof setTimeoutImpl === 'function') {
            setTimeoutImpl(finishWithFallbackClear, 0);
          } else {
            finishWithFallbackClear();
          }
        });
        return;
      }
      if (typeof setTimeoutImpl === 'function') {
        setTimeoutImpl(finishWithFallbackClear, 0);
        return;
      }
      finishWithFallbackClear();
    });
  }

  function scheduleComponentExplorerWarmup() {
    if (explorerWarmupScheduled) {
      return;
    }
    explorerWarmupScheduled = true;
    const run = () => {
      explorerWarmupScheduled = false;
      try {
        refreshComponentExplorer();
      } catch (_err: Unsafe) {
        // Ignore warmup failures; explicit tab refresh paths will still rebuild explorer state.
      }
    };
    if (typeof requestFrame === 'function') {
      requestFrame(() => {
        if (typeof setTimeoutImpl === 'function') {
          setTimeoutImpl(run, 0);
          return;
        }
        run();
      });
      return;
    }
    if (typeof setTimeoutImpl === 'function') {
      setTimeoutImpl(run, 0);
      return;
    }
    run();
  }

  async function loadSample(samplePathOverride = null) {
    const samplePath = samplePathOverride || dom.sampleSelect?.value || DEFAULT_SAMPLE_PATH;
    const sampleLabel = dom.sampleSelect?.selectedOptions?.[0]?.textContent?.trim() || samplePath;
    try {
      dom.irJson.value = await fetchTextAsset(samplePath, `sample ${samplePath}`, fetchImpl);
      clearComponentSourceOverride();
      resetComponentExplorerState();
      log(`Loaded sample IR: ${sampleLabel}`);
      if (isComponentTabActive()) {
        refreshComponentExplorer();
      }
    } catch (err: Unsafe) {
      log(`Failed to load sample (${samplePath}): ${err.message || err}`);
    }
  }

  async function loadRunnerPreset(options: Unsafe = {}) {
    const {
      presetOverride = null,
      logLoad = true,
      setPreferredTab = true,
      showLoadingUi = false
    } = options;
    const preset = presetOverride || getRunnerPreset(dom.runnerSelect?.value);
    const loadingText = 'Loading...';
    const loadingRunnerStatus = `Loading ${preset.label}...`;
    const previousDisplayText = String(dom.apple2TextScreen?.textContent || '');
    const previousRunnerStatus = String(dom.runnerStatus?.textContent || '');
    const previousCanvasHidden = dom.apple2HiresCanvas ? !!dom.apple2HiresCanvas.hidden : null;

    if (showLoadingUi) {
      if (runnerLoadInFlight) {
        return;
      }
      runnerLoadInFlight = true;
      if (dom.loadRunnerBtn) {
        dom.loadRunnerBtn.disabled = true;
      }
      if (dom.apple2TextScreen) {
        dom.apple2TextScreen.textContent = loadingText;
      }
      if (dom.apple2HiresCanvas) {
        dom.apple2HiresCanvas.hidden = true;
      }
      if (dom.runnerStatus) {
        dom.runnerStatus.textContent = loadingRunnerStatus;
      }
      await waitForUiPaint();
    }

    if (dom.runnerSelect) {
      dom.runnerSelect.value = preset.id;
    }
    setRunnerPresetState(preset.id);
    updateIrSourceVisibility();
    try {
      await applyPreferredBackend(preset);

      let bundle = null;
      if (preset.usesManualIr) {
        if (!String(dom.irJson?.value || '').trim()) {
          await loadSample(preset.samplePath || null);
        }
        clearComponentSourceOverride();
        bundle = {
          simJson: String(dom.irJson?.value || '').trim(),
          explorerJson: String(dom.irJson?.value || '').trim(),
          explorerMeta: null,
          sourceBundle: null,
          schematicBundle: null
        };
      } else {
        bundle = await loadRunnerIrBundle(preset, { logLoad: !!logLoad });
      }

      await initializeSimulator({
        preset,
        simJson: bundle.simJson,
        explorerSource: bundle.explorerJson,
        explorerMeta: bundle.explorerMeta,
        componentSourceBundle: bundle.sourceBundle || null,
        componentSchematicBundle: bundle.schematicBundle || null,
        yieldToUi: showLoadingUi,
        deferComponentExplorerRebuild: showLoadingUi
      });
      if (setPreferredTab) {
        setActiveTab(preset.preferredTab || 'vcdTab');
      }
      await applyRunnerDefaults(preset);
    } catch (err: Unsafe) {
      log(`Failed to load runner ${preset.label}: ${err.message || err}`);
      return;
    } finally {
      if (showLoadingUi) {
        runnerLoadInFlight = false;
        if (dom.loadRunnerBtn) {
          dom.loadRunnerBtn.disabled = false;
        }
        if (dom.apple2TextScreen && String(dom.apple2TextScreen.textContent || '').trim() === loadingText) {
          dom.apple2TextScreen.textContent =
            previousDisplayText || 'Load a runner with memory + I/O support to use this tab.';
        }
        if (dom.runnerStatus && String(dom.runnerStatus.textContent || '').trim() === loadingRunnerStatus) {
          dom.runnerStatus.textContent = previousRunnerStatus;
        }
        if (dom.apple2HiresCanvas && previousCanvasHidden != null) {
          dom.apple2HiresCanvas.hidden = previousCanvasHidden;
        }
      }
    }
    refreshStatus();
    scheduleComponentExplorerWarmup();
  }

  async function preloadStartPreset(startPreset: Unsafe) {
    if (!startPreset || startPreset.usesManualIr) {
      clearComponentSourceBundle();
      clearComponentSchematicBundle();
      await loadSample(startPreset?.samplePath || null);
      return;
    }
    const preloadBundle = await loadRunnerIrBundle(startPreset, { logLoad: false });
    setComponentSourceBundle(preloadBundle.sourceBundle || null);
    setComponentSchematicBundle(preloadBundle.schematicBundle || null);
  }

  return {
    loadSample,
    loadRunnerPreset,
    preloadStartPreset
  };
}
