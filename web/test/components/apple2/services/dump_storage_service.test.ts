import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2DumpStorageService } from '../../../../app/components/apple2/services/dump_storage_service';

test('apple2 dump storage service save/load round-trips payload', () => {
  const storage = new Map();
  const service = createApple2DumpStorageService({
    storageKey: 'test.dump',
    windowRef: {
      localStorage: {
        setItem(key: any, value: any) {
          storage.set(key, value);
        },
        getItem(key: any) {
          return storage.has(key) ? storage.get(key) : null;
        }
      }
    },
    buildSnapshotPayload: (bytes: any, offset: any, label: any, savedAtIso: any, startPc: any) => ({
      bytes: Array.from(bytes),
      offset,
      label,
      savedAtIso,
      startPc
    }),
    parseSnapshotPayload: (payload: any) => ({
      ...payload,
      bytes: new Uint8Array(payload.bytes)
    }),
    log: () => {}
  });

  const saved = service.save(new Uint8Array([1, 2, 3]), 0x10, 'sample', 'now' as any, 0xB82A as any);
  assert.equal(saved, true);

  const loaded = service.load();
  assert.equal(loaded.offset, 0x10);
  assert.equal(loaded.label, 'sample');
  assert.equal(loaded.startPc, 0xB82A);
  assert.deepEqual(Array.from(loaded.bytes), [1, 2, 3]);
});
