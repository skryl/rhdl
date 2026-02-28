import test from 'node:test';
import assert from 'node:assert/strict';
import { getThemePalette, resolveElementColors } from '../../../../app/components/explorer/renderers/themes';

test('getThemePalette shenzhen returns expected colors', () => {
  const p = getThemePalette('shenzhen');
  assert.equal(p.componentBg, '#1b3d32');
  assert.equal(p.componentBorder, '#76d4a4');
  assert.equal(p.componentText, '#d8eee0');
  assert.equal(p.wire, '#4f7d6d');
  assert.equal(p.wireActive, '#7be9ad');
  assert.equal(p.wireToggle, '#f4bf66');
  assert.equal(p.selected, '#9cffe3');
  assert.equal(p.netBg, '#243a35');
  assert.equal(p.pinBg, '#2d5d4f');
  assert.equal(p.ioBg, '#28463d');
  assert.equal(p.memoryBg, '#4f3e2f');
  assert.equal(p.opBg, '#3f4c3a');
});

test('getThemePalette original returns expected colors', () => {
  const p = getThemePalette('original');
  assert.equal(p.componentBg, '#214c71');
  assert.equal(p.componentBorder, '#2f6b97');
  assert.equal(p.wire, '#3a5f82');
  assert.equal(p.wireActive, '#3dd7c2');
  assert.equal(p.wireToggle, '#ffbc5a');
  assert.equal(p.selected, '#7fdfff');
});

test('resolveElementColors for component returns component colors', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'component', active: false, toggled: false, selected: false }, p);
  assert.equal(colors.fill, p.componentBg);
  assert.equal(colors.stroke, p.componentBorder);
  assert.equal(colors.text, p.componentText);
});

test('resolveElementColors for memory returns memory colors', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'memory' }, p);
  assert.equal(colors.fill, p.memoryBg);
});

test('resolveElementColors for io returns io colors', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'io' }, p);
  assert.equal(colors.fill, p.ioBg);
  assert.equal(colors.stroke, p.ioBorder);
});

test('resolveElementColors for wire active state', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'wire', active: true, toggled: false, selected: false, bus: false }, p);
  assert.equal(colors.stroke, p.wireActive);
  assert.equal(colors.strokeWidth, 2.0);
});

test('resolveElementColors wire toggled overrides active', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'wire', active: true, toggled: true, selected: false, bus: false }, p);
  assert.equal(colors.stroke, p.wireToggle);
  assert.equal(colors.strokeWidth, 2.7);
});

test('resolveElementColors wire selected overrides toggled', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'wire', active: true, toggled: true, selected: true, bus: false }, p);
  assert.equal(colors.stroke, '#ffffff');
  assert.equal(colors.strokeWidth, 3.2);
});

test('resolveElementColors wire default bus width', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'wire', active: false, toggled: false, selected: false, bus: true }, p);
  assert.equal(colors.strokeWidth, 2.4);
});

test('resolveElementColors wire default non-bus width', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'wire', active: false, toggled: false, selected: false, bus: false }, p);
  assert.equal(colors.strokeWidth, 1.4);
});

test('resolveElementColors for net selected', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'net', active: false, toggled: false, selected: true, bus: false }, p);
  assert.equal(colors.stroke, p.selected);
  assert.equal(colors.strokeWidth, 2.8);
});

test('resolveElementColors for net active', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'net', active: true, toggled: false, selected: false, bus: false }, p);
  assert.equal(colors.fill, p.wireActive);
  assert.equal(colors.stroke, p.wireActive);
});

test('resolveElementColors for pin active', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'pin', active: true, toggled: false, selected: false }, p);
  assert.equal(colors.fill, p.wireActive);
});

test('resolveElementColors for pin selected', () => {
  const p = getThemePalette('shenzhen');
  const colors = resolveElementColors({ type: 'pin', active: false, toggled: false, selected: true }, p);
  assert.equal(colors.stroke, p.selected);
});
