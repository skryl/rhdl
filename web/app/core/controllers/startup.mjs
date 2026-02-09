import { createStartupInitializationService } from '../services/startup_initialization_service.mjs';
import { createStartupBindingRegistrationService } from '../services/startup_binding_registration_service.mjs';

export async function startApp(ctx = {}) {
  const {
    dom,
    state,
    runtime,
    log,
    env = {},
    store = {},
    util = {},
    keys = {},
    bindings = {},
    app = {}
  } = ctx;

  const { syncReduxUxState } = store;
  const { shell = {}, runner = {}, components = {}, apple2 = {}, sim = {}, watch = {} } = app;
  const { terminal = {} } = shell;

  const startupInitService = createStartupInitializationService({
    dom,
    state,
    store,
    util,
    keys,
    env,
    shell,
    runner,
    sim,
    apple2,
    terminal
  });

  const startupBindingService = createStartupBindingRegistrationService({
    dom,
    state,
    runtime,
    bindings,
    app: { shell, runner, components, apple2, sim, watch },
    store,
    util,
    env,
    log
  });

  try {
    await startupInitService.initialize();
  } catch (err) {
    dom.simStatus.textContent = `WASM init failed: ${err.message || err}`;
    log(`WASM init failed: ${err.message || err}`);
    return;
  }

  startupBindingService.resetBindingLifecycle();
  startupBindingService.registerBindings();
  syncReduxUxState('start');
  return true;
}
