import test from 'node:test';
import assert from 'node:assert/strict';

import { bindIoBindings } from '../../app/bindings/io_bindings.mjs';

function makeTarget(extra = {}) {
  return Object.assign(new EventTarget(), extra);
}

test('bindIoBindings wires hires toggle and cleanup', () => {
  const calls = [];
  const dom = {
    toggleHires: makeTarget({ checked: false }),
    toggleColor: makeTarget({ checked: false }),
    toggleSound: makeTarget({ checked: false }),
    clockSignal: makeTarget(),
    apple2SendKeyBtn: makeTarget(),
    apple2KeyInput: makeTarget({ value: '' }),
    apple2ClearKeysBtn: makeTarget(),
    apple2TextScreen: makeTarget()
  };

  const state = {
    apple2: {
      displayHires: false,
      displayColor: false,
      soundEnabled: false,
      keyQueue: []
    }
  };

  const actions = {
    setApple2DisplayHiresState: (value) => calls.push(['setHires', value]),
    setApple2DisplayColorState: (value) => calls.push(['setColor', value]),
    setApple2SoundEnabled: async () => {},
    updateApple2SpeakerAudio: () => {},
    refreshStatus: () => {},
    updateIoToggleUi: () => calls.push(['updateIoToggleUi']),
    refreshApple2Screen: () => calls.push(['refreshApple2Screen']),
    scheduleReduxUxSync: (reason) => calls.push(['sync', reason]),
    queueApple2Key: () => {},
    isApple2UiEnabled: () => true
  };

  const teardown = bindIoBindings({ dom, state, actions });

  dom.toggleHires.dispatchEvent(new Event('change'));
  assert.deepEqual(calls, [
    ['setHires', false],
    ['setColor', false],
    ['updateIoToggleUi'],
    ['refreshApple2Screen'],
    ['sync', 'toggleHires']
  ]);

  teardown();
  dom.toggleHires.dispatchEvent(new Event('change'));
  assert.equal(calls.length, 5);
});
