// @ts-nocheck
import { tokenizeCommandLine } from '../lib/tokens';

export function createTerminalCommandDispatcher({ handlers = [] }: unknown = {}) {
  if (!Array.isArray(handlers) || handlers.some((entry) => typeof entry !== 'function')) {
    throw new Error('createTerminalCommandDispatcher requires handler functions');
  }

  async function execute(rawLine: unknown, context: unknown) {
    const tokens = tokenizeCommandLine(rawLine);
    if (tokens.length === 0) {
      return null;
    }

    const cmd = tokens.shift()!.toLowerCase();
    for (const handler of handlers) {
      const result = await handler({ cmd, tokens: [...tokens], context });
      if (result !== undefined) {
        return result;
      }
    }

    throw new Error(`Unknown command: ${cmd}. Use "help".`);
  }

  return {
    execute
  };
}
