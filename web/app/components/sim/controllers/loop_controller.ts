import { createSimLoopRunnerService } from '../services/loop_runner_service';

export function createSimLoopController(options: Unsafe = {}) {
  return createSimLoopRunnerService(options);
}
