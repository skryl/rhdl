export const DEFAULT_APPLE2_SNAPSHOT_KIND = 'rhdl.apple2.ram_snapshot';
export const DEFAULT_APPLE2_SNAPSHOT_VERSION = 1;
export const DEFAULT_MEMORY_SNAPSHOT_KIND = 'rhdl.memory.snapshot';

interface SnapshotBuildOptions {
  kind?: unknown;
  version?: unknown;
}

interface SnapshotParseOptions {
  kind?: unknown;
  kinds?: unknown;
  version?: unknown;
}

interface Apple2SnapshotPayload {
  kind: string;
  version: number;
  label: string;
  offset: number;
  length: number;
  savedAtMs: number;
  savedAtIso: string;
  dataB64: string;
  startPc?: number;
  [key: string]: unknown;
}

export interface ParsedApple2Snapshot {
  bytes: Uint8Array;
  offset: number;
  label: string;
  savedAtIso: string | null;
  startPc: number | null;
}

type SnapshotPayloadRecord = Record<string, unknown>;

function encodeBase64Binary(binaryText: string) {
  if (typeof btoa === 'function') {
    return btoa(binaryText);
  }
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(binaryText, 'binary').toString('base64');
  }
  throw new Error('No base64 encoder available.');
}

function decodeBase64Binary(base64: string) {
  if (typeof atob === 'function') {
    return atob(base64);
  }
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(base64, 'base64').toString('binary');
  }
  throw new Error('No base64 decoder available.');
}

export function bytesToBase64(bytes: unknown) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return '';
  }
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return encodeBase64Binary(binary);
}

export function base64ToBytes(base64: unknown) {
  const binary = decodeBase64Binary(String(base64 || ''));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}

export function parsePcLiteral(value: unknown) {
  if (value == null) {
    return null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value) & 0xffff;
  }
  const raw = String(value).trim();
  if (!raw) {
    return null;
  }

  let m = raw.match(/^\$([0-9A-Fa-f]{1,4})$/);
  if (m) {
    return Number.parseInt(m[1], 16) & 0xffff;
  }
  m = raw.match(/^0x([0-9A-Fa-f]{1,4})$/i);
  if (m) {
    return Number.parseInt(m[1], 16) & 0xffff;
  }
  m = raw.match(/^[0-9A-Fa-f]{1,4}$/);
  if (m && /[A-Fa-f]/.test(raw)) {
    return Number.parseInt(raw, 16) & 0xffff;
  }
  m = raw.match(/^[0-9]{1,5}$/);
  if (m) {
    return Number.parseInt(m[0], 10) & 0xffff;
  }
  return null;
}

export function extractPcFromText(text: unknown) {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }
  const patterns = [
    /PC at dump:\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i,
    /start[_\s-]*pc\s*[:=]\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i,
    /\(PC\s*=\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})\)/i,
    /\bPC\s*[:=]\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) {
      continue;
    }
    const parsed = parsePcLiteral(match[1]);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

export function isSnapshotFileName(fileName: unknown) {
  const lower = String(fileName || '').trim().toLowerCase();
  return (
    lower.endsWith('.rhdlsnap')
    || lower.endsWith('.rhdlsnap.json')
    || lower.endsWith('.snapshot')
    || lower.endsWith('.snapshot.json')
  );
}

export function buildApple2SnapshotPayload(
  bytes: Uint8Array,
  offset = 0,
  label = 'saved dump',
  savedAtIso: string | null = null,
  startPc: unknown = null,
  options: SnapshotBuildOptions = {}
): Apple2SnapshotPayload | null {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return null;
  }

  const dataB64 = bytesToBase64(bytes);
  if (!dataB64) {
    return null;
  }

  const kind = String(options.kind || DEFAULT_APPLE2_SNAPSHOT_KIND);
  const version = Number.parseInt(String(options.version ?? ''), 10) || DEFAULT_APPLE2_SNAPSHOT_VERSION;
  const iso = typeof savedAtIso === 'string' && savedAtIso ? savedAtIso : new Date().toISOString();

  const payload: Apple2SnapshotPayload = {
    kind,
    version,
    label: String(label || 'saved dump'),
    offset: Math.max(0, Number.parseInt(String(offset), 10) || 0),
    length: bytes.length,
    savedAtMs: Date.now(),
    savedAtIso: iso,
    dataB64
  };

  const parsedPc = parsePcLiteral(startPc);
  if (parsedPc != null) {
    payload.startPc = parsedPc;
  }

  return payload;
}

export function parseApple2SnapshotPayload(
  payload: unknown,
  options: SnapshotParseOptions = {}
): ParsedApple2Snapshot | null {
  if (!payload || typeof payload !== 'object') {
    return null;
  }
  const payloadRecord = payload as SnapshotPayloadRecord;

  const explicitKinds = Array.isArray(options.kinds)
    ? options.kinds.map((kind: unknown) => String(kind || '').trim()).filter(Boolean)
    : [];
  if (explicitKinds.length === 0 && options.kind) {
    explicitKinds.push(String(options.kind));
  }
  if (explicitKinds.length === 0) {
    explicitKinds.push(DEFAULT_APPLE2_SNAPSHOT_KIND, DEFAULT_MEMORY_SNAPSHOT_KIND);
  }
  const expectedVersion = Number.parseInt(String(options.version ?? ''), 10) || DEFAULT_APPLE2_SNAPSHOT_VERSION;

  if (payloadRecord.kind != null && !explicitKinds.includes(String(payloadRecord.kind))) {
    return null;
  }
  if (payloadRecord.version != null) {
    const version = Number.parseInt(String(payloadRecord.version), 10);
    if (!Number.isFinite(version) || version > expectedVersion) {
      return null;
    }
  }
  if (typeof payloadRecord.dataB64 !== 'string') {
    return null;
  }

  let bytes;
  try {
    bytes = base64ToBytes(payloadRecord.dataB64);
  } catch (_err: unknown) {
    return null;
  }
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return null;
  }

  let startPc = null;
  const pcCandidates = [
    payloadRecord.startPc,
    payloadRecord.start_pc,
    payloadRecord.pc,
    payloadRecord.resetPc,
    payloadRecord.reset_pc,
    payloadRecord.entryPc,
    payloadRecord.entry_pc
  ];
  for (const candidate of pcCandidates) {
    const parsed = parsePcLiteral(candidate);
    if (parsed != null) {
      startPc = parsed;
      break;
    }
  }
  if (startPc == null) {
    startPc = extractPcFromText(payloadRecord.label) ?? extractPcFromText(payloadRecord.notes);
  }

  return {
    bytes,
    offset: Math.max(0, Number.parseInt(String(payloadRecord.offset ?? ''), 10) || 0),
    label: typeof payloadRecord.label === 'string' && payloadRecord.label ? payloadRecord.label : 'saved dump',
    savedAtIso: typeof payloadRecord.savedAtIso === 'string' ? payloadRecord.savedAtIso : null,
    startPc
  };
}

export function parseApple2SnapshotText(
  text: unknown,
  options: SnapshotParseOptions = {}
): ParsedApple2Snapshot | null {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }
  try {
    const payload = JSON.parse(text);
    return parseApple2SnapshotPayload(payload, options);
  } catch (_err: unknown) {
    return null;
  }
}
