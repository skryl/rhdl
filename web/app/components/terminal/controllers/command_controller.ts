import {
  normalizeUiId,
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText
} from './helpers/parse';
import { createTerminalRuntimeService } from '../services/runtime_service';

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
