import { createStartupInitializationService } from '../services/startup_initialization_service';
import { createStartupBindingRegistrationService } from '../services/startup_binding_registration_service';

export async function startApp(ctx: any = {}) {
  const {
    dom,
    state,
    runtime,
    log,
    env = {} as any,
    store = {} as any,
    util = {} as any,
    keys = {} as any,
    bindings = {} as any,
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
  } catch (err: any) {
    dom.simStatus.textContent = `WASM init failed: ${err.message || err}`;
    log(`WASM init failed: ${err.message || err}`);
    return;
  }

  startupBindingService.resetBindingLifecycle();
  startupBindingService.registerBindings();
  syncReduxUxState('start');
  return true;
}
