import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

export function bindIoBindings({
  dom,
  state,
  apple2,
  sim,
  store,
  scheduleReduxUxSync
}) {
  const listeners = createListenerGroup();

  listeners.on(dom.toggleHires, 'change', () => {
    store.setApple2DisplayHiresState(!!dom.toggleHires.checked);
    if (!state.apple2.displayHires) {
      store.setApple2DisplayColorState(false);
    }
    apple2.updateIoToggleUi();
    apple2.refreshScreen();
    scheduleReduxUxSync('toggleHires');
  });

  listeners.on(dom.toggleColor, 'change', () => {
    store.setApple2DisplayColorState(!!dom.toggleColor.checked);
    if (state.apple2.displayColor) {
      store.setApple2DisplayHiresState(true);
    }
    apple2.updateIoToggleUi();
    apple2.refreshScreen();
    scheduleReduxUxSync('toggleColor');
  });

  listeners.on(dom.toggleSound, 'change', async () => {
    await apple2.setSoundEnabled(!!dom.toggleSound.checked);
    if (!state.apple2.soundEnabled) {
      apple2.updateSpeakerAudio(0, 0);
    }
    sim.refreshStatus();
  });

  listeners.on(dom.clockSignal, 'change', () => {
    sim.refreshStatus();
  });

  listeners.on(dom.apple2SendKeyBtn, 'click', () => {
    const raw = dom.apple2KeyInput?.value || '';
    if (!raw) {
      return;
    }
    apple2.queueKey(raw[0]);
    dom.apple2KeyInput.value = '';
  });

  listeners.on(dom.apple2KeyInput, 'keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      const raw = dom.apple2KeyInput?.value || '';
      apple2.queueKey(raw ? raw[0] : '\r');
      dom.apple2KeyInput.value = '';
    }
  });

  listeners.on(dom.apple2ClearKeysBtn, 'click', () => {
    state.apple2.keyQueue = [];
    sim.refreshStatus();
  });

  listeners.on(dom.apple2TextScreen, 'keydown', (event) => {
    if (!apple2.isUiEnabled()) {
      return;
    }
    if (event.key.length === 1) {
      apple2.queueKey(event.key);
      event.preventDefault();
      return;
    }
    if (event.key === 'Enter') {
      apple2.queueKey('\r');
      event.preventDefault();
    } else if (event.key === 'Backspace') {
      apple2.queueKey(String.fromCharCode(0x08));
      event.preventDefault();
    }
  });

  return () => {
    listeners.dispose();
  };
}
