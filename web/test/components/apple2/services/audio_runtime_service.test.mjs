import test from 'node:test';
import assert from 'node:assert/strict';
import { createApple2AudioRuntimeService } from '../../../../app/components/apple2/services/audio_runtime_service.mjs';

test('apple2 audio runtime service updates oscillator when speaker toggles are present', () => {
  const freqCalls = [];
  const gainCalls = [];
  const state = {
    apple2: {
      soundEnabled: true,
      audioCtx: { currentTime: 1.25 },
      audioOsc: { frequency: { setTargetAtTime: (...args) => freqCalls.push(args) } },
      audioGain: { gain: { setTargetAtTime: (...args) => gainCalls.push(args) } }
    }
  };
  const service = createApple2AudioRuntimeService({
    state,
    setApple2SoundEnabledState: () => {},
    updateIoToggleUi: () => {},
    log: () => {}
  });

  service.updateApple2SpeakerAudio(50, 1000);
  assert.equal(freqCalls.length, 1);
  assert.equal(gainCalls.length, 1);
});

test('apple2 audio runtime service disables sound when web audio is unavailable', async () => {
  const toggles = [];
  const state = {
    apple2: {
      soundEnabled: false,
      audioCtx: null,
      audioOsc: null,
      audioGain: null
    }
  };
  const service = createApple2AudioRuntimeService({
    state,
    setApple2SoundEnabledState: (enabled) => {
      state.apple2.soundEnabled = !!enabled;
      toggles.push(!!enabled);
    },
    updateIoToggleUi: () => {},
    log: () => {},
    windowRef: {}
  });

  await service.setApple2SoundEnabled(true);
  assert.deepEqual(toggles, [true, false]);
  assert.equal(state.apple2.soundEnabled, false);
});
