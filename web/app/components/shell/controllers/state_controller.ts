import { createShellStateRuntimeService } from '../services/state_runtime_service';

export function createShellStateController(options: any = {}) {
  return createShellStateRuntimeService(options);
}
