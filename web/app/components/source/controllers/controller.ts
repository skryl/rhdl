import { createSourceRuntimeService } from '../services/runtime_service';

export function createComponentSourceController(options: unknown = {}) {
  return createSourceRuntimeService(options);
}
