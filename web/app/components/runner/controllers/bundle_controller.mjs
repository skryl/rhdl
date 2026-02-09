import {
  fetchTextAsset,
  fetchJsonAsset
} from '../../../core/lib/fetch_asset.mjs';
import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../../source/lib/bundle_normalizers.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createRunnerBundleLoader requires function: ${name}`);
  }
}

export function createRunnerBundleLoader({
  dom,
  parseIrMeta,
  resetComponentExplorerState,
  log,
  fetchImpl = globalThis.fetch
} = {}) {
  if (!dom) {
    throw new Error('createRunnerBundleLoader requires dom');
  }
  requireFn('parseIrMeta', parseIrMeta);
  requireFn('resetComponentExplorerState', resetComponentExplorerState);
  requireFn('log', log);
  requireFn('fetchImpl', fetchImpl);

  async function loadRunnerIrBundle(preset, options = {}) {
    const { logLoad = false } = options;
    if (!preset || preset.usesManualIr) {
      return {
        simJson: String(dom.irJson?.value || '').trim(),
        explorerJson: String(dom.irJson?.value || '').trim(),
        explorerMeta: null,
        sourceBundle: null,
        schematicBundle: null
      };
    }

    const simJson = (await fetchTextAsset(preset.simIrPath, `${preset.label} IR`, fetchImpl)).trim();
    let explorerJson = simJson;
    if (preset.explorerIrPath && preset.explorerIrPath !== preset.simIrPath) {
      explorerJson = (await fetchTextAsset(preset.explorerIrPath, `${preset.label} hierarchical IR`, fetchImpl)).trim();
    }

    if (dom.irJson) {
      dom.irJson.value = simJson;
    }
    resetComponentExplorerState();

    let explorerMeta = null;
    if (explorerJson) {
      explorerMeta = parseIrMeta(explorerJson);
    }

    let sourceBundle = null;
    if (preset.sourceBundlePath) {
      try {
        const rawBundle = await fetchJsonAsset(preset.sourceBundlePath, `${preset.label} source bundle`, fetchImpl);
        sourceBundle = normalizeComponentSourceBundle(rawBundle);
      } catch (err) {
        log(`Source bundle load failed for ${preset.label}: ${err.message || err}`);
      }
    }

    let schematicBundle = null;
    if (preset.schematicPath) {
      try {
        const rawSchematic = await fetchJsonAsset(preset.schematicPath, `${preset.label} schematic`, fetchImpl);
        schematicBundle = normalizeComponentSchematicBundle(rawSchematic);
      } catch (err) {
        log(`Schematic load failed for ${preset.label}: ${err.message || err}`);
      }
    }

    if (logLoad) {
      log(`Loaded ${preset.label} IR bundle`);
    }
    return {
      simJson,
      explorerJson,
      explorerMeta,
      sourceBundle,
      schematicBundle
    };
  }

  return {
    loadRunnerIrBundle
  };
}
