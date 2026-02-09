import test from 'node:test';
import assert from 'node:assert/strict';

import { isComponentPanel } from '../../../../app/components/shell/bindings/collapsible_bindings.mjs';

function fakePanel(classes) {
  const set = new Set(classes || []);
  return {
    classList: {
      contains(name) {
        return set.has(name);
      }
    }
  };
}

test('isComponentPanel identifies known component panel classes', () => {
  assert.equal(isComponentPanel(fakePanel(['component-tree-panel'])), true);
  assert.equal(isComponentPanel(fakePanel(['component-live-panel'])), true);
  assert.equal(isComponentPanel(fakePanel(['unrelated'])), false);
  assert.equal(isComponentPanel(null), false);
});
