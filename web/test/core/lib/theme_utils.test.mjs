import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeTheme,
  waveformFontFamily,
  waveformPalette
} from '../../../app/core/lib/theme_utils.mjs';

test('normalizeTheme constrains to supported values', () => {
  assert.equal(normalizeTheme('original'), 'original');
  assert.equal(normalizeTheme('shenzhen'), 'shenzhen');
  assert.equal(normalizeTheme('other'), 'shenzhen');
});

test('waveformFontFamily follows selected theme', () => {
  assert.equal(waveformFontFamily('original'), 'IBM Plex Mono');
  assert.equal(waveformFontFamily('shenzhen'), 'Share Tech Mono');
});

test('waveformPalette returns expected palette keys for both themes', () => {
  const original = waveformPalette('original');
  const shenzhen = waveformPalette('shenzhen');

  for (const palette of [original, shenzhen]) {
    for (const key of ['bg', 'axis', 'grid', 'label', 'trace', 'value', 'time', 'hint']) {
      assert.ok(Array.isArray(palette[key]));
      assert.equal(palette[key].length, 3);
    }
  }

  assert.notDeepEqual(original.bg, shenzhen.bg);
});
