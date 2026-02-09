import { createSourceRuntimeService } from '../services/runtime_service.mjs';

export function createComponentSourceController(options = {}) {
  return createSourceRuntimeService(options);
}
