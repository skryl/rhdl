import { tokenizeCommandLine } from '../lib/tokens.mjs';

export function createTerminalCommandDispatcher({ handlers = [] } = {}) {
  if (!Array.isArray(handlers) || handlers.some((entry) => typeof entry !== 'function')) {
    throw new Error('createTerminalCommandDispatcher requires handler functions');
  }

  async function execute(rawLine, context) {
    const tokens = tokenizeCommandLine(rawLine);
    if (tokens.length === 0) {
      return null;
    }

    const cmd = tokens.shift().toLowerCase();
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
