function requireFn(name: any, fn: any) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2DumpStorageService requires function: ${name}`);
  }
}

export function createApple2DumpStorageService({
  storageKey,
  windowRef = globalThis.window,
  buildSnapshotPayload,
  parseSnapshotPayload,
  log = () => {}
}: any = {}) {
  if (!storageKey) {
    throw new Error('createApple2DumpStorageService requires storageKey');
  }
  requireFn('buildSnapshotPayload', buildSnapshotPayload);
  requireFn('parseSnapshotPayload', parseSnapshotPayload);
  requireFn('log', log);

  function save(bytes: any, offset = 0, label = 'saved dump', savedAtIso = null, startPc = null) {
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
    } catch (err: any) {
      log(`Could not persist last memory dump: ${err.message || err}`);
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
    } catch (err: any) {
      log(`Could not read last memory dump: ${err.message || err}`);
      return null;
    }
  }

  return {
    save,
    load
  };
}
