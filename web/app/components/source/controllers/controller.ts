import { createSourceRuntimeService } from '../services/runtime_service';

export function createComponentSourceController(options = {}) {
  return createSourceRuntimeService(options);
}
