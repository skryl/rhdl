export function resolveLiveSignalName(signalName, pathTokens, signalSet) {
  const raw = String(signalName || '').trim();
  if (!raw) {
    return null;
  }
  const normalized = raw.replace(/\./g, '__');
  const candidates = [raw, normalized];
  if (Array.isArray(pathTokens) && pathTokens.length > 0) {
    const joined = pathTokens.join('__');
    const tail = pathTokens[pathTokens.length - 1];
    candidates.push(`${joined}__${raw}`);
    candidates.push(`${joined}__${normalized}`);
    candidates.push(`${tail}__${raw}`);
    candidates.push(`${tail}__${normalized}`);
  }
  for (const candidate of candidates) {
    if (signalSet.has(candidate)) {
      return candidate;
    }
  }
  return null;
}

export function nodeDisplayPath(node) {
  if (!node) {
    return 'top';
  }
  return node.path || node.name || 'top';
}

function makeComponentNode(model, parentId, name, kind, pathTokens = [], rawRef = null) {
  const id = `node_${model.nextId++}`;
  const path = pathTokens.length > 0 ? pathTokens.join('.') : 'top';
  const node = {
    id,
    parentId,
    name: String(name || 'component'),
    kind: String(kind || 'component'),
    path,
    pathTokens: Array.isArray(pathTokens) ? pathTokens : [],
    children: [],
    signals: [],
    rawRef,
    _signalKeys: new Set()
  };
  model.nodes.set(id, node);
  return node;
}

function addSignalToNode(node, signal) {
  if (!node || !signal) {
    return;
  }
  const key = signal.liveName || signal.fullName || signal.name;
  if (!key || node._signalKeys.has(key)) {
    return;
  }
  node._signalKeys.add(key);
  node.signals.push(signal);
}

function readSignalEntriesFromObject(obj) {
  const out = [];
  if (!obj || typeof obj !== 'object') {
    return out;
  }
  for (const kind of ['ports', 'nets', 'regs', 'signals', 'wires']) {
    const entries = Array.isArray(obj[kind]) ? obj[kind] : [];
    for (const entry of entries) {
      if (!entry || typeof entry.name !== 'string') {
        continue;
      }
      out.push({ kind, entry });
    }
  }
  return out;
}

export function deriveComponentName(obj, fallback) {
  if (obj && typeof obj === 'object') {
    for (const key of ['instance_name', 'inst_name', 'instance', 'name', 'id', 'module', 'component', 'label']) {
      if (typeof obj[key] === 'string' && obj[key].trim()) {
        return obj[key].trim();
      }
    }
  }
  return fallback;
}

export function summarizeIrEntry(entry) {
  if (!entry || typeof entry !== 'object') {
    return entry;
  }
  const summary = {};
  for (const key of ['name', 'kind', 'type', 'direction', 'width', 'clock', 'reset', 'path', 'file', 'line']) {
    if (entry[key] !== undefined) {
      summary[key] = entry[key];
    }
  }
  if (Object.keys(summary).length > 0) {
    return summary;
  }
  const keys = Object.keys(entry);
  return { keys: keys.slice(0, 12), fieldCount: keys.length };
}

export function ellipsizeText(value, maxLen = 88) {
  const text = String(value ?? '');
  if (text.length <= maxLen) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLen - 3))}...`;
}

export function summarizeIrNode(rawRef) {
  if (!rawRef || typeof rawRef !== 'object') {
    return null;
  }
  const summary = {};
  for (const key of ['name', 'kind', 'type', 'instance', 'instance_name', 'module', 'component', 'path']) {
    if (rawRef[key] !== undefined) {
      summary[key] = rawRef[key];
    }
  }
  for (const key of ['ports', 'nets', 'regs', 'signals', 'processes', 'assigns', 'instances', 'children', 'modules', 'components']) {
    if (!Array.isArray(rawRef[key])) {
      continue;
    }
    const entries = rawRef[key];
    const limit = 40;
    summary[key] = entries.slice(0, limit).map(summarizeIrEntry);
    if (entries.length > limit) {
      summary[`${key}_truncated`] = entries.length - limit;
    }
  }
  return summary;
}

function signalGroupToken(name) {
  const raw = String(name || '').trim();
  if (!raw) {
    return null;
  }
  const match = raw.match(/^([a-z][a-z0-9]{1,24})[_./]/i);
  if (!match) {
    return null;
  }
  const token = match[1].toLowerCase();
  if (['next', 'prev', 'tmp', 'temp', 'process'].includes(token)) {
    return null;
  }
  return token;
}

function addSyntheticSignalGroupChildren(model, node, pathTokens) {
  if (!model || !node || !Array.isArray(node.signals) || node.signals.length < 16) {
    return 0;
  }

  const grouped = new Map();
  for (const signal of node.signals) {
    const token = signalGroupToken(signal.name || signal.fullName);
    if (!token) {
      continue;
    }
    if (!grouped.has(token)) {
      grouped.set(token, []);
    }
    grouped.get(token).push(signal);
  }

  const groups = Array.from(grouped.entries())
    .filter(([, signals]) => signals.length >= 2)
    .sort((a, b) => {
      const countDiff = b[1].length - a[1].length;
      if (countDiff !== 0) {
        return countDiff;
      }
      return a[0].localeCompare(b[0]);
    })
    .slice(0, 8);

  if (groups.length === 0) {
    return 0;
  }

  const siblingNames = new Set(
    node.children
      .map((childId) => model.nodes.get(childId)?.name?.toLowerCase())
      .filter(Boolean)
  );

  let added = 0;
  for (const [token, signals] of groups) {
    let childName = token;
    let suffix = 2;
    while (siblingNames.has(childName.toLowerCase())) {
      childName = `${token}_${suffix}`;
      suffix += 1;
    }
    siblingNames.add(childName.toLowerCase());

    const childPath = [...pathTokens, childName];
    const childNode = makeComponentNode(model, node.id, childName, 'signal-group', childPath, {
      name: childName,
      kind: 'signal-group',
      synthetic: true,
      signal_count: signals.length
    });
    for (const signal of signals) {
      addSignalToNode(childNode, signal);
    }
    node.children.push(childNode.id);
    added += 1;
  }
  return added;
}

function buildHierarchicalComponentModel(meta) {
  const ir = meta?.ir;
  if (!ir || typeof ir !== 'object') {
    return null;
  }

  const childKeys = ['children', 'instances', 'modules', 'components', 'submodules', 'blocks', 'units'];
  const hasExplicitHierarchy = childKeys.some((key) => Array.isArray(ir[key]) && ir[key].length > 0);
  if (!hasExplicitHierarchy) {
    return null;
  }

  const signalSet = new Set(meta?.liveSignalNames || meta?.names || []);
  const model = {
    nextId: 1,
    mode: 'hierarchical',
    nodes: new Map(),
    rootId: null
  };
  const rootName = typeof ir.name === 'string' && ir.name.trim() ? ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], ir);
  model.rootId = root.id;

  const seen = new WeakSet();

  function walk(node, source, pathTokens) {
    if (!source || typeof source !== 'object') {
      return;
    }
    if (seen.has(source)) {
      return;
    }
    seen.add(source);

    for (const { kind, entry } of readSignalEntriesFromObject(source)) {
      const width = Number.parseInt(entry.width, 10) || 1;
      const liveName = resolveLiveSignalName(entry.name, pathTokens, signalSet);
      addSignalToNode(node, {
        name: entry.name,
        fullName: liveName || entry.name,
        liveName,
        width,
        kind,
        direction: entry.direction || null,
        declaration: entry
      });
    }

    let explicitChildCount = 0;
    for (const key of childKeys) {
      const children = Array.isArray(source[key]) ? source[key] : [];
      const siblingNames = new Set();
      children.forEach((child, index) => {
        if (!child || typeof child !== 'object') {
          return;
        }
        const baseName = deriveComponentName(child, `${key}_${index}`);
        let childName = baseName;
        let dedupe = 1;
        while (siblingNames.has(childName)) {
          dedupe += 1;
          childName = `${baseName}_${dedupe}`;
        }
        siblingNames.add(childName);

        const childPath = [...pathTokens, childName];
        const childNode = makeComponentNode(model, node.id, childName, key.slice(0, -1) || 'component', childPath, child);
        node.children.push(childNode.id);
        explicitChildCount += 1;
        walk(childNode, child, childPath);
      });
    }

    // Some modules are authored as monolithic blocks with no explicit hierarchy.
    // Add grouped signal families as synthetic child nodes so graphs are explorable.
    if (explicitChildCount === 0) {
      addSyntheticSignalGroupChildren(model, node, pathTokens);
    }
  }

  walk(root, ir, []);
  return model;
}

function buildDerivedFlatComponentModel(meta) {
  const model = {
    nextId: 1,
    mode: 'flat-derived',
    nodes: new Map(),
    rootId: null,
    pathMap: new Map()
  };
  const rootName = typeof meta?.ir?.name === 'string' && meta.ir.name.trim() ? meta.ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], meta?.ir || null);
  model.rootId = root.id;
  model.pathMap.set('', root.id);

  function ensurePath(pathTokens) {
    const pathKey = pathTokens.join('__');
    if (model.pathMap.has(pathKey)) {
      return model.nodes.get(model.pathMap.get(pathKey));
    }
    const parentTokens = pathTokens.slice(0, -1);
    const parent = ensurePath(parentTokens);
    const name = pathTokens[pathTokens.length - 1];
    const node = makeComponentNode(model, parent.id, name, 'component', pathTokens, null);
    parent.children.push(node.id);
    model.pathMap.set(pathKey, node.id);
    return node;
  }

  for (const signalName of meta?.names || []) {
    const info = meta?.signalInfo?.get(signalName);
    const width = info?.width || (meta?.widths?.get(signalName) || 1);
    const parts = signalName.split('__').filter(Boolean);
    if (parts.length <= 1) {
      addSignalToNode(root, {
        name: signalName,
        fullName: signalName,
        liveName: signalName,
        width,
        kind: info?.kind || 'signal',
        direction: info?.direction || null,
        declaration: info?.entry || null
      });
      continue;
    }

    const pathTokens = parts.slice(0, -1);
    const leaf = parts[parts.length - 1];
    const node = ensurePath(pathTokens);
    addSignalToNode(node, {
      name: leaf,
      fullName: signalName,
      liveName: signalName,
      width,
      kind: info?.kind || 'signal',
      direction: info?.direction || null,
      declaration: info?.entry || null
    });
  }

  return model;
}

function finalizeComponentModel(model) {
  if (!model || !model.nodes) {
    return model;
  }
  for (const node of model.nodes.values()) {
    node.children.sort((a, b) => {
      const left = model.nodes.get(a);
      const right = model.nodes.get(b);
      return (left?.name || '').localeCompare(right?.name || '');
    });
    node.signals.sort((a, b) => (a.fullName || a.name || '').localeCompare(b.fullName || b.name || ''));
  }
  return model;
}

export function buildComponentModel(meta) {
  const hierarchical = buildHierarchicalComponentModel(meta);
  if (hierarchical) {
    return finalizeComponentModel(hierarchical);
  }
  return finalizeComponentModel(buildDerivedFlatComponentModel(meta));
}

export function nodeMatchesFilter(node, filter) {
  if (!filter) {
    return true;
  }
  const lower = filter.toLowerCase();
  if ((node.name || '').toLowerCase().includes(lower)) {
    return true;
  }
  if ((node.path || '').toLowerCase().includes(lower)) {
    return true;
  }
  for (const signal of node.signals) {
    const full = (signal.fullName || signal.name || '').toLowerCase();
    if (full.includes(lower)) {
      return true;
    }
  }
  return false;
}
