import { createSimStatusRuntimeService } from '../services/status_runtime_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimStatusController requires function: ${name}`);
  }
}

export function createSimStatusController({
  dom,
  state,
  runtime,
  getBackendDef,
  currentRunnerPreset,
  isApple2UiEnabled,
  updateIoToggleUi,
  scheduleReduxUxSync,
  litRender,
  html
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createSimStatusController requires dom/state/runtime');
  }
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('litRender', litRender);
  requireFn('html', html);

  const runtimeService = createSimStatusRuntimeService({
    state,
    runtime,
    getBackendDef,
    currentRunnerPreset,
    isApple2UiEnabled
  });

  function selectedClock() {
    return runtimeService.selectedClock(dom.clockSignal.value);
  }

  function refreshStatus() {
    const snapshot = runtimeService.describeStatus(dom.clockSignal.value);
    dom.simStatus.textContent = snapshot.simStatus;
    dom.traceStatus.textContent = snapshot.traceStatus;
    if (dom.backendStatus) {
      dom.backendStatus.textContent = snapshot.backendStatus;
    }
    if (dom.runnerStatus) {
      dom.runnerStatus.textContent = snapshot.runnerStatus;
    }
    if (dom.apple2KeyStatus && snapshot.apple2KeyStatus != null) {
      dom.apple2KeyStatus.textContent = snapshot.apple2KeyStatus;
    }
    if (snapshot.updateIoToggles) {
      updateIoToggleUi();
    }
    scheduleReduxUxSync(snapshot.syncReason);
  }

  function populateClockSelect() {
    const { options, selected } = runtimeService.listClockOptions(dom.clockSignal.value);
    litRender(
      html`${options.map((entry) => html`
        <option value=${entry.value}>${entry.label}</option>
      `)}`,
      dom.clockSignal
    );
    dom.clockSignal.value = selected;
  }

  return {
    selectedClock,
    maskForWidth: runtimeService.maskForWidth,
    refreshStatus,
    populateClockSelect
  };
}
