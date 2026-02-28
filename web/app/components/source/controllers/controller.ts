import { createSourceRuntimeService } from '../services/runtime_service';

export function createComponentSourceController(options: any = {}) {
  return createSourceRuntimeService(options);
}
