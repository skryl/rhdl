import { createSimLoopRunnerService } from '../services/loop_runner_service.mjs';

export function createSimLoopController(options = {}) {
  return createSimLoopRunnerService(options);
}
