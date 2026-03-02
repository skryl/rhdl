import { createShellStateRuntimeService } from '../services/state_runtime_service';

export function createShellStateController(options: unknown = {}) {
  return createShellStateRuntimeService(options);
}
