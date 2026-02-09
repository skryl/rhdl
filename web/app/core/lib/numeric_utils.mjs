export function toBigInt(value) {
  if (typeof value === 'bigint') {
    return value;
  }
  if (Number.isFinite(value)) {
    return BigInt(Math.trunc(value));
  }
  return 0n;
}

export function parseNumeric(text) {
  const raw = String(text || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }

  try {
    if (raw.startsWith('0x')) {
      return BigInt(raw);
    }
    if (raw.startsWith('0b')) {
      return BigInt(raw);
    }
    return BigInt(raw);
  } catch (_err) {
    return null;
  }
}

export function formatValue(value, width) {
  if (value == null) {
    return '-';
  }

  const v = toBigInt(value);
  if (width <= 1) {
    return String(Number(v & 1n));
  }

  return `0x${v.toString(16)}`;
}

export function parseHexOrDec(text, defaultValue = 0) {
  const raw = String(text || '').trim().toLowerCase();
  if (!raw) {
    return defaultValue;
  }
  if (raw.startsWith('0x')) {
    const value = Number.parseInt(raw.slice(2), 16);
    return Number.isFinite(value) ? value : defaultValue;
  }
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : defaultValue;
}

export function hexWord(value) {
  return (Number(value) & 0xffff).toString(16).toUpperCase().padStart(4, '0');
}

export function hexByte(value) {
  return Number(value).toString(16).toUpperCase().padStart(2, '0');
}
