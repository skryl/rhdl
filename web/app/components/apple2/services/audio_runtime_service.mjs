function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2AudioRuntimeService requires function: ${name}`);
  }
}

export function createApple2AudioRuntimeService({
  state,
  setApple2SoundEnabledState,
  updateIoToggleUi,
  log = () => {},
  windowRef = globalThis.window
} = {}) {
  if (!state) {
    throw new Error('createApple2AudioRuntimeService requires state');
  }
  requireFn('setApple2SoundEnabledState', setApple2SoundEnabledState);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('log', log);

  function ensureApple2AudioGraph() {
    if (state.apple2.audioCtx && state.apple2.audioOsc && state.apple2.audioGain) {
      return true;
    }

    const AudioCtx = windowRef.AudioContext || windowRef.webkitAudioContext;
    if (!AudioCtx) {
      return false;
    }

    const ctx = new AudioCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'square';
    osc.frequency.value = 440;
    gain.gain.value = 0;

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();

    state.apple2.audioCtx = ctx;
    state.apple2.audioOsc = osc;
    state.apple2.audioGain = gain;
    return true;
  }

  async function setApple2SoundEnabled(enabled) {
    setApple2SoundEnabledState(!!enabled);
    updateIoToggleUi();

    if (!state.apple2.soundEnabled) {
      if (state.apple2.audioCtx && state.apple2.audioGain) {
        state.apple2.audioGain.gain.setTargetAtTime(0, state.apple2.audioCtx.currentTime, 0.01);
      }
      return;
    }

    if (!ensureApple2AudioGraph()) {
      setApple2SoundEnabledState(false);
      updateIoToggleUi();
      log('WebAudio unavailable: SOUND toggle disabled');
      return;
    }

    try {
      await state.apple2.audioCtx.resume();
    } catch (err) {
      setApple2SoundEnabledState(false);
      updateIoToggleUi();
      log(`Failed to enable audio: ${err.message || err}`);
    }
  }

  function updateApple2SpeakerAudio(toggles, cyclesRun) {
    if (!state.apple2.soundEnabled) {
      return;
    }
    if (!state.apple2.audioCtx || !state.apple2.audioOsc || !state.apple2.audioGain) {
      return;
    }

    const ctx = state.apple2.audioCtx;
    const gain = state.apple2.audioGain.gain;
    const freq = state.apple2.audioOsc.frequency;

    if (!toggles || !cyclesRun) {
      gain.setTargetAtTime(0, ctx.currentTime, 0.012);
      return;
    }

    const hz = (toggles * 1_000_000) / (2 * Math.max(1, cyclesRun));
    const clampedHz = Math.max(40, Math.min(6000, hz));
    freq.setTargetAtTime(clampedHz, ctx.currentTime, 0.006);
    gain.setTargetAtTime(0.03, ctx.currentTime, 0.005);
  }

  return {
    setApple2SoundEnabled,
    updateApple2SpeakerAudio
  };
}
