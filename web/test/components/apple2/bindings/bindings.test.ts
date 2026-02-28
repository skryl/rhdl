import test from 'node:test';
import assert from 'node:assert/strict';

import { bindIoBindings } from '../../../../app/components/apple2/bindings/bindings';

function makeTarget(extra: any = {}) {
  return Object.assign(new EventTarget(), extra);
}

test('bindIoBindings wires hires toggle and cleanup', () => {
  const calls: any[] = [];
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

  const apple2 = {
    setSoundEnabled: async () => {},
    updateSpeakerAudio: () => {},
    updateIoToggleUi: () => calls.push(['updateIoToggleUi']),
    refreshScreen: () => calls.push(['refreshApple2Screen']),
    queueKey: () => {},
    isUiEnabled: () => true
  };

  const teardown = bindIoBindings({
    dom,
    state,
    apple2,
    sim: {
      refreshStatus: () => {}
    },
    store: {
      setApple2DisplayHiresState: (value: any) => calls.push(['setHires', value]),
      setApple2DisplayColorState: (value: any) => calls.push(['setColor', value])
    },
    scheduleReduxUxSync: (reason: any) => calls.push(['sync', reason])
  });

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
