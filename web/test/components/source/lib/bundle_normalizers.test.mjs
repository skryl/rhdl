import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../../../app/components/source/lib/bundle_normalizers.mjs';

test('normalizeComponentSourceBundle builds class/module indexes', () => {
  const raw = {
    top_component_class: 'Top',
    components: [
      { component_class: 'Top', module_name: 'TopMod' },
      { component_class: 'Child', module_name: 'ChildMod' }
    ]
  };
  const normalized = normalizeComponentSourceBundle(raw);
  assert.equal(normalized.top.component_class, 'Top');
  assert.equal(normalized.byClass.get('Child').module_name, 'ChildMod');
  assert.equal(normalized.byModule.get('topmod').component_class, 'Top');
});

test('normalizeComponentSchematicBundle indexes entries by path', () => {
  const raw = {
    components: [
      { path: 'top' },
      { path: 'top.cpu' }
    ]
  };
  const normalized = normalizeComponentSchematicBundle(raw);
  assert.equal(normalized.byPath.get('top.cpu').path, 'top.cpu');
});
