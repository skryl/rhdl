import { createShellStateRuntimeService } from '../services/state_runtime_service.mjs';

export function createShellStateController(options = {}) {
  return createShellStateRuntimeService(options);
}
