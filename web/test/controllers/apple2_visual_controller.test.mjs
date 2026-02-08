import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2VisualController } from '../../app/controllers/apple2_visual_controller.mjs';

function createHarness() {
  const debugCalls = [];
  const ioCalls = [];
  const dom = {
    apple2TextScreen: { textContent: '' },
    apple2HiresCanvas: null
  };
  const state = {
    apple2: {
      displayHires: false,
      displayColor: false,
      lastCpuResult: { speaker_toggles: 7 }
    }
  };
  const runtime = {
    sim: null
  };
  const controller = createApple2VisualController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => false,
    updateIoToggleUi: () => ioCalls.push('io'),
    renderApple2DebugRows: (...args) => debugCalls.push(args),
    apple2HiresLineAddress: (row) => row
  });
  return { controller, dom, debugCalls, ioCalls };
}

test('refreshApple2Screen renders disabled message when runner is unavailable', () => {
  const { controller, dom, ioCalls } = createHarness();
  controller.refreshApple2Screen();
  assert.match(dom.apple2TextScreen.textContent, /Load the Apple II runner/);
  assert.equal(ioCalls.length, 1);
});

test('refreshApple2Debug renders disabled placeholder when runner is unavailable', () => {
  const { controller, debugCalls } = createHarness();
  controller.refreshApple2Debug();
  assert.equal(debugCalls.length, 1);
  assert.equal(Array.isArray(debugCalls[0][1]), true);
  assert.equal(debugCalls[0][1].length, 0);
  assert.match(debugCalls[0][2], /Speaker toggles/);
  assert.equal(debugCalls[0][3], false);
});
