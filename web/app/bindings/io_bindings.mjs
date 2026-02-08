import { createListenerGroup } from './listener_bindings.mjs';

export function bindIoBindings({ dom, state, actions }) {
  const listeners = createListenerGroup();

  listeners.on(dom.toggleHires, 'change', () => {
    actions.setApple2DisplayHiresState(!!dom.toggleHires.checked);
    if (!state.apple2.displayHires) {
      actions.setApple2DisplayColorState(false);
    }
    actions.updateIoToggleUi();
    actions.refreshApple2Screen();
    actions.scheduleReduxUxSync('toggleHires');
  });

  listeners.on(dom.toggleColor, 'change', () => {
    actions.setApple2DisplayColorState(!!dom.toggleColor.checked);
    if (state.apple2.displayColor) {
      actions.setApple2DisplayHiresState(true);
    }
    actions.updateIoToggleUi();
    actions.refreshApple2Screen();
    actions.scheduleReduxUxSync('toggleColor');
  });

  listeners.on(dom.toggleSound, 'change', async () => {
    await actions.setApple2SoundEnabled(!!dom.toggleSound.checked);
    if (!state.apple2.soundEnabled) {
      actions.updateApple2SpeakerAudio(0, 0);
    }
    actions.refreshStatus();
  });

  listeners.on(dom.clockSignal, 'change', () => {
    actions.refreshStatus();
  });

  listeners.on(dom.apple2SendKeyBtn, 'click', () => {
    const raw = dom.apple2KeyInput?.value || '';
    if (!raw) {
      return;
    }
    actions.queueApple2Key(raw[0]);
    dom.apple2KeyInput.value = '';
  });

  listeners.on(dom.apple2KeyInput, 'keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      const raw = dom.apple2KeyInput?.value || '';
      actions.queueApple2Key(raw ? raw[0] : '\r');
      dom.apple2KeyInput.value = '';
    }
  });

  listeners.on(dom.apple2ClearKeysBtn, 'click', () => {
    state.apple2.keyQueue = [];
    actions.refreshStatus();
  });

  listeners.on(dom.apple2TextScreen, 'keydown', (event) => {
    if (!actions.isApple2UiEnabled()) {
      return;
    }
    if (event.key.length === 1) {
      actions.queueApple2Key(event.key);
      event.preventDefault();
      return;
    }
    if (event.key === 'Enter') {
      actions.queueApple2Key('\r');
      event.preventDefault();
    } else if (event.key === 'Backspace') {
      actions.queueApple2Key(String.fromCharCode(0x08));
      event.preventDefault();
    }
  });

  return () => {
    listeners.dispose();
  };
}
