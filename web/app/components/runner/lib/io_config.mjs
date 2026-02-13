const U16_MAX = 0xFFFF;
const U32_MAX = 0xFFFFFFFF;
const U32_ADDRESS_SPACE = 0x100000000;

function asBoolean(value, fallback = false) {
  if (value == null) {
    return fallback;
  }
  return !!value;
}

function asUint(value, fallback = 0, max = U32_MAX) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(0, Math.min(max, Math.trunc(parsed)));
}

function asOptionalUint(value, fallback = null, max = U32_MAX) {
  if (value == null || value === '') {
    return fallback;
  }
  return asUint(value, fallback == null ? 0 : fallback, max);
}

function asString(value, fallback = '') {
  if (typeof value !== 'string') {
    return fallback;
  }
  return value;
}

function asStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) => String(entry || '').trim())
    .filter(Boolean);
}

function baseRunnerIoConfig() {
  return {
    enabled: false,
    api: 'memory',
    memory: {
      dumpStart: 0,
      dumpLength: 0x10000,
      addressSpace: 0x10000,
      viewMapped: true,
      dumpReadMapped: true,
      directWriteMapped: true
    },
    display: {
      enabled: false,
      mode: 'text',
      text: {
        start: 0x0400,
        width: 40,
        height: 24,
        rowStride: 40,
        rowLayout: 'linear',
        charMask: 0x7F,
        asciiMin: 0x20,
        asciiMax: 0x7E
      }
    },
    keyboard: {
      enabled: false,
      mode: 'memory_mapped',
      dataAddr: null,
      strobeAddr: null,
      strobeValue: 1,
      strobeClearValue: null,
      upperCase: true,
      setHighBit: false,
      enterCode: 0x0D,
      backspaceCode: 0x08
    },
    sound: {
      enabled: false,
      mode: 'memory_mapped',
      addr: null,
      mask: 1
    },
    rom: {
      path: null,
      offset: 0,
      isRom: false
    },
    pcSignalCandidates: [],
    watchSignals: []
  };
}

function legacyApple2IoConfig(preset = {}) {
  return {
    enabled: true,
    api: 'apple2',
    memory: {
      dumpStart: 0,
      dumpLength: 48 * 1024,
      addressSpace: 0x10000,
      viewMapped: true,
      dumpReadMapped: false,
      directWriteMapped: false
    },
    display: {
      enabled: true,
      mode: 'apple2',
      text: {
        start: 0x0400,
        width: 40,
        height: 24,
        rowStride: 0x80,
        rowLayout: 'apple2',
        charMask: 0x7F,
        asciiMin: 0x20,
        asciiMax: 0x7E
      }
    },
    keyboard: {
      enabled: true,
      mode: 'apple2_special',
      dataAddr: null,
      strobeAddr: null,
      strobeValue: 1,
      strobeClearValue: null,
      upperCase: true,
      setHighBit: false,
      enterCode: 0x0D,
      backspaceCode: 0x08
    },
    sound: {
      enabled: true,
      mode: 'apple2_special',
      addr: null,
      mask: 1
    },
    rom: {
      path: asString(preset.romPath, null),
      offset: 0xD000,
      isRom: true
    },
    pcSignalCandidates: ['pc_debug', 'cpu__debug_pc', 'reg_pc'],
    watchSignals: ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker']
  };
}

function normalizeMemory(memory = {}, fallback) {
  return {
    dumpStart: asUint(memory.dumpStart, fallback.dumpStart, U32_MAX),
    dumpLength: asUint(memory.dumpLength, fallback.dumpLength, U32_MAX),
    addressSpace: Math.max(1, asUint(memory.addressSpace, fallback.addressSpace, U32_ADDRESS_SPACE)),
    viewMapped: asBoolean(memory.viewMapped, fallback.viewMapped),
    dumpReadMapped: asBoolean(memory.dumpReadMapped, fallback.dumpReadMapped),
    directWriteMapped: asBoolean(memory.directWriteMapped, fallback.directWriteMapped)
  };
}

function normalizeDisplay(display = {}, fallback) {
  const textRaw = display.text && typeof display.text === 'object' ? display.text : {};
  return {
    enabled: asBoolean(display.enabled, fallback.enabled),
    mode: asString(display.mode, fallback.mode),
    text: {
      start: asUint(textRaw.start, fallback.text.start, U16_MAX),
      width: Math.max(1, asUint(textRaw.width, fallback.text.width, 0x4000)),
      height: Math.max(1, asUint(textRaw.height, fallback.text.height, 0x4000)),
      rowStride: Math.max(1, asUint(textRaw.rowStride, fallback.text.rowStride, 0x4000)),
      rowLayout: asString(textRaw.rowLayout, fallback.text.rowLayout),
      charMask: asUint(textRaw.charMask, fallback.text.charMask, 0xFF),
      asciiMin: asUint(textRaw.asciiMin, fallback.text.asciiMin, 0xFF),
      asciiMax: asUint(textRaw.asciiMax, fallback.text.asciiMax, 0xFF)
    }
  };
}

function normalizeKeyboard(keyboard = {}, fallback) {
  return {
    enabled: asBoolean(keyboard.enabled, fallback.enabled),
    mode: asString(keyboard.mode, fallback.mode),
    dataAddr: asOptionalUint(keyboard.dataAddr, fallback.dataAddr, U16_MAX),
    strobeAddr: asOptionalUint(keyboard.strobeAddr, fallback.strobeAddr, U16_MAX),
    strobeValue: asUint(keyboard.strobeValue, fallback.strobeValue, 0xFF),
    strobeClearValue: asOptionalUint(keyboard.strobeClearValue, fallback.strobeClearValue, 0xFF),
    upperCase: asBoolean(keyboard.upperCase, fallback.upperCase),
    setHighBit: asBoolean(keyboard.setHighBit, fallback.setHighBit),
    enterCode: asUint(keyboard.enterCode, fallback.enterCode, 0xFF),
    backspaceCode: asUint(keyboard.backspaceCode, fallback.backspaceCode, 0xFF)
  };
}

function normalizeSound(sound = {}, fallback) {
  return {
    enabled: asBoolean(sound.enabled, fallback.enabled),
    mode: asString(sound.mode, fallback.mode),
    addr: asOptionalUint(sound.addr, fallback.addr, U16_MAX),
    mask: asUint(sound.mask, fallback.mask, 0xFF)
  };
}

function normalizeRom(rom = {}, fallback) {
  return {
    path: asString(rom.path, fallback.path),
    offset: asUint(rom.offset, fallback.offset, U16_MAX),
    isRom: asBoolean(rom.isRom, fallback.isRom)
  };
}

export function resolveRunnerIoConfig(preset = {}) {
  const raw = preset && typeof preset.io === 'object' ? preset.io : null;
  if (!raw) {
    if (preset?.enableApple2Ui) {
      return legacyApple2IoConfig(preset);
    }
    return baseRunnerIoConfig();
  }

  const fallback = raw.api === 'apple2' || preset?.enableApple2Ui
    ? legacyApple2IoConfig(preset)
    : baseRunnerIoConfig();

  const normalized = {
    enabled: asBoolean(raw.enabled, fallback.enabled),
    api: asString(raw.api, fallback.api),
    memory: normalizeMemory(raw.memory || {}, fallback.memory),
    display: normalizeDisplay(raw.display || {}, fallback.display),
    keyboard: normalizeKeyboard(raw.keyboard || {}, fallback.keyboard),
    sound: normalizeSound(raw.sound || {}, fallback.sound),
    rom: normalizeRom(raw.rom || {}, fallback.rom),
    pcSignalCandidates: asStringArray(raw.pcSignalCandidates),
    watchSignals: asStringArray(raw.watchSignals)
  };

  if (normalized.pcSignalCandidates.length === 0) {
    normalized.pcSignalCandidates = fallback.pcSignalCandidates.slice();
  }

  if (normalized.watchSignals.length === 0) {
    normalized.watchSignals = fallback.watchSignals.slice();
  }

  if (!normalized.rom.path && preset?.romPath) {
    normalized.rom.path = String(preset.romPath);
  }

  return normalized;
}
