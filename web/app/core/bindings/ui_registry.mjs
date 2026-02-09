export function createUiBindingRegistry(runtime) {
  function registerUiBinding(teardown) {
    if (typeof teardown !== 'function') {
      return;
    }
    if (!Array.isArray(runtime.uiTeardowns)) {
      runtime.uiTeardowns = [];
    }
    runtime.uiTeardowns.push(teardown);
  }

  function disposeUiBindings() {
    if (!Array.isArray(runtime.uiTeardowns)) {
      runtime.uiTeardowns = [];
      return;
    }
    while (runtime.uiTeardowns.length > 0) {
      const teardown = runtime.uiTeardowns.pop();
      try {
        teardown();
      } catch (_err) {
        // Ignore teardown errors; this is best-effort cleanup.
      }
    }
  }

  return {
    registerUiBinding,
    disposeUiBindings
  };
}
