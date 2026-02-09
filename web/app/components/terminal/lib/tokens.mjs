export function tokenizeCommandLine(line) {
  const out = [];
  let current = '';
  let quote = '';
  let escaping = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (escaping) {
      current += ch;
      escaping = false;
      continue;
    }
    if (ch === '\\') {
      escaping = true;
      continue;
    }
    if (quote) {
      if (ch === quote) {
        quote = '';
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (/\s/.test(ch)) {
      if (current) {
        out.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }

  if (escaping) {
    current += '\\';
  }
  if (quote) {
    throw new Error('Unclosed quote in command.');
  }
  if (current) {
    out.push(current);
  }
  return out;
}

export function parseBooleanToken(token) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (['1', 'true', 'on', 'yes', 'enable', 'enabled', 'show', 'open'].includes(raw)) {
    return true;
  }
  if (['0', 'false', 'off', 'no', 'disable', 'disabled', 'hide', 'close'].includes(raw)) {
    return false;
  }
  return null;
}
