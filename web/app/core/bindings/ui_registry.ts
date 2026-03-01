import type { RuntimeContext } from '../../types/runtime';
import type { UiBindingRegistry } from '../../types/services';

export function createUiBindingRegistry(runtime: RuntimeContext): UiBindingRegistry {
  function registerUiBinding(teardown: (() => void) | null | undefined) {
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
      if (typeof teardown !== 'function') {
        continue;
      }
      try {
        teardown();
      } catch (_err: unknown) {
        // Ignore teardown errors; this is best-effort cleanup.
      }
    }
  }

  return {
    registerUiBinding,
    disposeUiBindings
  };
}
