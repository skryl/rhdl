import {
  GENERATED_RUNNER_PRESETS,
  GENERATED_RUNNER_ORDER,
  GENERATED_DEFAULT_RUNNER_ID
} from './generated_presets.mjs';

function asString(value, fallback = '') {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }
  return fallback;
}

function uniqueTokens(values = []) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const token = asString(value, '');
    if (!token || seen.has(token)) {
      continue;
    }
    seen.add(token);
    out.push(token);
  }
  return out;
}

function samplePathForPreset(preset = null) {
  if (!preset || typeof preset !== 'object') {
    return '';
  }
  if (preset.usesManualIr) {
    return asString(preset.samplePath, '');
  }
  return asString(preset.simIrPath, '');
}

const GENERIC_PRESET = Object.freeze({
  id: 'generic',
  label: 'Generic IR Runner',
  sampleLabel: 'CPU (examples/8bit/hdl/cpu)',
  samplePath: './assets/fixtures/cpu/ir/cpu_lib_hdl.json',
  preferredTab: 'vcdTab',
  enableApple2Ui: false,
  usesManualIr: true
});

const mergedPresets = {
  generic: GENERIC_PRESET,
  ...(GENERATED_RUNNER_PRESETS && typeof GENERATED_RUNNER_PRESETS === 'object' ? GENERATED_RUNNER_PRESETS : {})
};

const generatedOrder = Array.isArray(GENERATED_RUNNER_ORDER)
  ? GENERATED_RUNNER_ORDER
  : Object.keys(mergedPresets);

export const RUNNER_ORDER = Object.freeze(
  uniqueTokens(['generic', ...generatedOrder]).filter((id) => mergedPresets[id])
);

const normalizedPresets = {};
for (const id of RUNNER_ORDER) {
  const preset = mergedPresets[id] || {};
  normalizedPresets[id] = {
    ...preset,
    id
  };
}

export const RUNNER_PRESETS = Object.freeze(normalizedPresets);

export const DEFAULT_RUNNER_PRESET_ID = RUNNER_ORDER.includes(GENERATED_DEFAULT_RUNNER_ID)
  ? GENERATED_DEFAULT_RUNNER_ID
  : (RUNNER_ORDER.includes('apple2') ? 'apple2' : (RUNNER_ORDER[0] || 'generic'));

export const RUNNER_SELECT_OPTIONS = Object.freeze(
  RUNNER_ORDER.map((id) => ({
    value: id,
    label: asString(RUNNER_PRESETS[id]?.label, id)
  }))
);

export const SAMPLE_SELECT_OPTIONS = (() => {
  const options = [];
  const seenPaths = new Set();

  for (const id of RUNNER_ORDER) {
    const preset = RUNNER_PRESETS[id];
    const path = samplePathForPreset(preset);
    if (!path || seenPaths.has(path)) {
      continue;
    }
    seenPaths.add(path);
    options.push({
      value: path,
      label: asString(preset?.sampleLabel, asString(preset?.label, path))
    });
  }

  return Object.freeze(options);
})();

export const DEFAULT_SAMPLE_PATH = asString(
  SAMPLE_SELECT_OPTIONS[0]?.value,
  GENERIC_PRESET.samplePath
);
