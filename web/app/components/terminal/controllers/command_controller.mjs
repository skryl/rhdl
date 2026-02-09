import {
  normalizeUiId,
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText
} from './helpers/parse.mjs';
import { createTerminalRuntimeService } from '../services/runtime_service.mjs';

export {
  normalizeUiId,
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText
};

export function createTerminalCommandController(options = {}) {
  return createTerminalRuntimeService(options);
}
