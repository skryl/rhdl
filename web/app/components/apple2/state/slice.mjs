export const apple2ActionTypes = {
  SET_APPLE2_DISPLAY_HIRES: 'apple2/setDisplayHires',
  SET_APPLE2_DISPLAY_COLOR: 'apple2/setDisplayColor',
  SET_APPLE2_SOUND_ENABLED: 'apple2/setSoundEnabled'
};

export const apple2Actions = {
  setApple2DisplayHires: (value) => ({ type: apple2ActionTypes.SET_APPLE2_DISPLAY_HIRES, payload: !!value }),
  setApple2DisplayColor: (value) => ({ type: apple2ActionTypes.SET_APPLE2_DISPLAY_COLOR, payload: !!value }),
  setApple2SoundEnabled: (value) => ({ type: apple2ActionTypes.SET_APPLE2_SOUND_ENABLED, payload: !!value })
};

export function createApple2StateSlice() {
  return {
    apple2: {
      enabled: false,
      keyQueue: [],
      lastSpeakerToggles: 0,
      lastCpuResult: null,
      baseRomBytes: null,
      displayHires: false,
      displayColor: false,
      soundEnabled: false,
      audioCtx: null,
      audioOsc: null,
      audioGain: null
    }
  };
}

export function reduceApple2State(state, action = {}) {
  switch (action.type) {
    case apple2ActionTypes.SET_APPLE2_DISPLAY_HIRES:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.displayHires = !!action.payload;
      return true;
    case apple2ActionTypes.SET_APPLE2_DISPLAY_COLOR:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.displayColor = !!action.payload;
      return true;
    case apple2ActionTypes.SET_APPLE2_SOUND_ENABLED:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.soundEnabled = !!action.payload;
      return true;
    default:
      return false;
  }
}
