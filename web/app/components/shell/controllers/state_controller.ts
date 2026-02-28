import { createShellStateRuntimeService } from '../services/state_runtime_service';

export function createShellStateController(options = {}) {
  return createShellStateRuntimeService(options);
}
