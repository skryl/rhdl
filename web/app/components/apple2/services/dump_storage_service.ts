function requireFn(name: string, fn: unknown) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2DumpStorageService requires function: ${name}`);
  }
}

function formatError(err: unknown) {
  if (err instanceof Error) {
    return err.message;
  }
  return String(err);
}

interface Apple2SnapshotRecord {
  bytes: Uint8Array;
  offset: number;
  label: string;
  savedAtIso: string | null;
  startPc: number | null;
}

interface Apple2DumpStorageServiceDeps {
  storageKey: string;
  windowRef?: Unsafe;
  buildSnapshotPayload: (
    bytes: Uint8Array,
    offset: number,
    label: string,
    savedAtIso: string | null,
    startPc: number | null
  ) => Unsafe;
  parseSnapshotPayload: (payload: Unsafe) => Apple2SnapshotRecord | null;
  log?: (message: string) => void;
}

export function createApple2DumpStorageService({
  storageKey,
  windowRef = globalThis.window,
  buildSnapshotPayload,
  parseSnapshotPayload,
  log = () => {}
}: Apple2DumpStorageServiceDeps) {
  if (!storageKey) {
    throw new Error('createApple2DumpStorageService requires storageKey');
  }
  requireFn('buildSnapshotPayload', buildSnapshotPayload);
  requireFn('parseSnapshotPayload', parseSnapshotPayload);
  requireFn('log', log);

  function save(
    bytes: Uint8Array,
    offset = 0,
    label = 'saved dump',
    savedAtIso: string | null = null,
    startPc: number | null = null
  ) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    try {
      const payload = buildSnapshotPayload(bytes, offset, label, savedAtIso, startPc);
      if (!payload) {
        return false;
      }
      windowRef.localStorage.setItem(storageKey, JSON.stringify(payload));
      return true;
    } catch (err: unknown) {
      log(`Could not persist last memory dump: ${formatError(err)}`);
      return false;
    }
  }

  function load() {
    try {
      const raw = windowRef.localStorage.getItem(storageKey);
      if (!raw) {
        return null;
      }
      return parseSnapshotPayload(JSON.parse(raw));
    } catch (err: unknown) {
      log(`Could not read last memory dump: ${formatError(err)}`);
      return null;
    }
  }

  return {
    save,
    load
  };
}
