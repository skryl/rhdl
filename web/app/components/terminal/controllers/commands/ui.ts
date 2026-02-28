export function handleUiCommand({ cmd, tokens, context }) {
  const { helpers } = context;

  if (cmd === 'set') {
    const id = tokens.shift();
    if (!id || tokens.length === 0) {
      throw new Error('Usage: set <elementId> <value>');
    }
    return helpers.setUiInputValueById(id, tokens.join(' '));
  }

  if (cmd === 'click') {
    const id = tokens[0];
    if (!id) {
      throw new Error('Usage: click <elementId>');
    }
    return helpers.clickUiElementById(id);
  }

  return undefined;
}
