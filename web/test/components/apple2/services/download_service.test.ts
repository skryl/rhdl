import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2DownloadService } from '../../../../app/components/apple2/services/download_service';

test('apple2 download service creates and revokes blob urls', () => {
  const calls: Array<[name: string, ...args: unknown[]]> = [];
  const service = createApple2DownloadService({
    windowRef: {
      URL: {
        createObjectURL(blob: Blob) {
          calls.push(['create', blob instanceof Blob]);
          return 'blob:test';
        },
        revokeObjectURL(url: string) {
          calls.push(['revoke', url]);
        }
      }
    },
    documentRef: {
      createElement() {
        return {
          href: '',
          download: '',
          click() {
            calls.push(['click']);
          }
        };
      }
    }
  });

  service.downloadMemoryDump(new Uint8Array([1, 2]), 'dump.bin');
  service.downloadSnapshot({ a: 1 }, 'snap.rhdlsnap');

  assert.equal(calls.some(([kind]) => kind === 'create'), true);
  assert.equal(calls.some(([kind]) => kind === 'click'), true);
  assert.equal(calls.some(([kind]) => kind === 'revoke'), true);
});
