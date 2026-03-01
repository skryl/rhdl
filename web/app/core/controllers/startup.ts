import { createStartupInitializationService } from '../services/startup_initialization_service';
import { createStartupBindingRegistrationService } from '../services/startup_binding_registration_service';
import type {
  StartupAppControllers,
  StartupContext,
  StartupInitializationServiceDeps,
  StartupBindingRegistrationServiceDeps
} from '../../types/services';

function messageFromError(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

export async function startApp(ctx: Partial<StartupContext> = {}) {
  const {
    dom,
    state,
    runtime,
    log = () => {},
    env = {},
    store = {},
    util = {},
    keys = {},
    bindings = {},
    app = {}
  } = ctx;

  const storeBindings = store as Partial<StartupContext['store']>;
  const { syncReduxUxState } = storeBindings;
  const appControllers = app as StartupAppControllers;
  const {
    shell = {} as StartupAppControllers['shell'],
    runner = {} as StartupAppControllers['runner'],
    components = {} as StartupAppControllers['components'],
    apple2 = {} as StartupAppControllers['apple2'],
    sim = {} as StartupAppControllers['sim'],
    watch = {} as StartupAppControllers['watch']
  } = appControllers;
  const { terminal = {} as NonNullable<typeof shell>['terminal'] } = shell || {};

  const startupInitService = createStartupInitializationService({
    dom,
    state,
    store: storeBindings,
    util,
    keys,
    env,
    shell,
    runner,
    sim,
    apple2,
    terminal
  } as StartupInitializationServiceDeps);

  const startupBindingService = createStartupBindingRegistrationService({
    dom,
    state,
    runtime,
    bindings,
    app: {
      shell,
      runner,
      components,
      apple2,
      sim,
      watch
    },
    store: storeBindings,
    util,
    env,
    log
  } as StartupBindingRegistrationServiceDeps);

  try {
    await startupInitService.initialize();
  } catch (err: unknown) {
    const message = messageFromError(err);
    if (dom?.simStatus) {
      dom.simStatus.textContent = `WASM init failed: ${message}`;
    }
    log(`WASM init failed: ${message}`);
    return;
  }

  startupBindingService.resetBindingLifecycle();
  startupBindingService.registerBindings();
  if (typeof syncReduxUxState === 'function') {
    syncReduxUxState('start');
  }
  return true;
}
