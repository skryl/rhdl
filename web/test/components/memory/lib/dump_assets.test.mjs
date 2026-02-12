import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createDumpAssetTree,
  isDumpAssetPath,
  normalizeDumpAssetPath
} from '../../../../app/components/memory/lib/dump_assets.mjs';

test('normalizeDumpAssetPath normalizes slash direction and assets prefix', () => {
  assert.equal(normalizeDumpAssetPath('assets\\fixtures\\cpu\\software\\demo.bin'), './assets/fixtures/cpu/software/demo.bin');
  assert.equal(normalizeDumpAssetPath('./assets//fixtures///cpu/demo.bin'), './assets/fixtures/cpu/demo.bin');
});

test('isDumpAssetPath only accepts dump/snapshot file extensions under ./assets', () => {
  assert.equal(isDumpAssetPath('./assets/fixtures/cpu/software/demo.bin'), true);
  assert.equal(isDumpAssetPath('./assets/fixtures/apple2/memory/demo.rhdlsnap'), true);
  assert.equal(isDumpAssetPath('./assets/fixtures/apple2/memory/appleiigo.rom'), false);
  assert.equal(isDumpAssetPath('/tmp/demo.bin'), false);
});

test('createDumpAssetTree builds nested sorted directories with file leaves', () => {
  const tree = createDumpAssetTree([
    './assets/fixtures/mos6502/memory/karateka_mem.bin',
    './assets/fixtures/cpu/software/conway_glider_80x24.bin',
    './assets/fixtures/apple2/memory/karateka_mem.rhdlsnap'
  ]);

  assert.deepEqual(tree.dirs.map((dir) => dir.name), ['assets']);
  const assetsNode = tree.dirs[0];
  assert.equal(assetsNode.path, './assets');
  assert.deepEqual(assetsNode.dirs.map((dir) => dir.name), ['fixtures']);

  const fixturesNode = assetsNode.dirs[0];
  assert.deepEqual(fixturesNode.dirs.map((dir) => dir.name), ['apple2', 'cpu', 'mos6502']);
});
