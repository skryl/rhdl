import { createSimLoopRunnerService } from '../services/loop_runner_service';

export function createSimLoopController(options: any = {}) {
  return createSimLoopRunnerService(options);
}
