import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2DumpStorageService } from '../../../../app/components/apple2/services/dump_storage_service';

test('apple2 dump storage service save/load round-trips payload', () => {
  const storage = new Map<string, string>();
  const service = createApple2DumpStorageService({
    storageKey: 'test.dump',
    windowRef: {
      localStorage: {
        setItem(key: string, value: string) {
          storage.set(key, value);
        },
        getItem(key: string) {
          return storage.has(key) ? storage.get(key) : null;
        }
      }
    },
    buildSnapshotPayload: (
      bytes: Uint8Array,
      offset: number,
      label: string,
      savedAtIso: string | null,
      startPc: number | null
    ) => ({
      bytes: Array.from(bytes),
      offset,
      label,
      savedAtIso,
      startPc
    }),
    parseSnapshotPayload: (payload: {
      bytes: number[];
      offset: number;
      label: string;
      savedAtIso: string | null;
      startPc: number | null;
    }) => ({
      ...payload,
      bytes: new Uint8Array(payload.bytes)
    }),
    log: () => {}
  });

  const saved = service.save(new Uint8Array([1, 2, 3]), 0x10, 'sample', 'now', 0xB82A);
  assert.equal(saved, true);

  const loaded = service.load();
  assert.ok(loaded);
  assert.equal(loaded.offset, 0x10);
  assert.equal(loaded.label, 'sample');
  assert.equal(loaded.startPc, 0xB82A);
  assert.deepEqual(Array.from(loaded.bytes), [1, 2, 3]);
});
