import {
  asRecord,
  asStringArray,
  type ComponentModel,
  type ComponentNode,
  type ComponentSignal,
  type IrMetaLike,
  type SignalInfo,
  type UnknownRecord
} from './types';

export function resolveLiveSignalName(
  signalName: unknown,
  pathTokens: unknown,
  signalSet: unknown
): string | null {
  const raw = String(signalName || '').trim();
  if (!raw) {
    return null;
  }
  const normalized = raw.replace(/\./g, '__');
  const candidates = [raw, normalized];
  const tokenList = asStringArray(pathTokens);
  const resolvedSignalSet = signalSet instanceof Set ? signalSet : new Set(asStringArray(signalSet));
  if (tokenList.length > 0) {
    const joined = tokenList.join('__');
    const tail = tokenList[tokenList.length - 1];
    candidates.push(`${joined}__${raw}`);
    candidates.push(`${joined}__${normalized}`);
    candidates.push(`${tail}__${raw}`);
    candidates.push(`${tail}__${normalized}`);
  }
  for (const candidate of candidates) {
    if (resolvedSignalSet.has(candidate)) {
      return candidate;
    }
  }
  return null;
}

export function nodeDisplayPath(node: unknown): string {
  const nodeRecord = asRecord(node);
  if (!nodeRecord) {
    return 'top';
  }
  return String(nodeRecord.path || nodeRecord.name || 'top');
}

function makeComponentNode(
  model: ComponentModel,
  parentId: string | null,
  name: unknown,
  kind: unknown,
  pathTokens: string[] = [],
  rawRef: UnknownRecord | null = null
): ComponentNode {
  const id = `node_${model.nextId++}`;
  const path = pathTokens.length > 0 ? pathTokens.join('.') : 'top';
  const node: ComponentNode = {
    id,
    parentId,
    name: String(name || 'component'),
    kind: String(kind || 'component'),
    path,
    pathTokens: pathTokens.slice(),
    children: [],
    signals: [],
    rawRef,
    _signalKeys: new Set<string>()
  };
  model.nodes.set(id, node);
  return node;
}

function normalizeSignal(signal: unknown): ComponentSignal | null {
  const signalRecord = asRecord(signal);
  if (!signalRecord) {
    return null;
  }

  const name = String(signalRecord.name || '').trim();
  const fullName = String(signalRecord.fullName || name).trim();
  if (!name && !fullName) {
    return null;
  }

  const widthRaw = Number(signalRecord.width);
  const width = Number.isFinite(widthRaw) && widthRaw > 0 ? widthRaw : 1;

  return {
    name: name || fullName,
    fullName: fullName || name,
    liveName:
      signalRecord.liveName === null || signalRecord.liveName === undefined
        ? null
        : String(signalRecord.liveName),
    width,
    kind: String(signalRecord.kind || 'signal'),
    direction:
      signalRecord.direction === null || signalRecord.direction === undefined
        ? null
        : String(signalRecord.direction),
    declaration: signalRecord.declaration ?? null,
    value: signalRecord.value,
    matchesHighlight:
      typeof signalRecord.matchesHighlight === 'boolean'
        ? signalRecord.matchesHighlight
        : undefined
  };
}

function addSignalToNode(node: ComponentNode | null, signal: unknown): void {
  if (!node) {
    return;
  }
  const normalizedSignal = normalizeSignal(signal);
  if (!normalizedSignal) {
    return;
  }

  const key = normalizedSignal.liveName || normalizedSignal.fullName || normalizedSignal.name;
  if (!key || node._signalKeys.has(key)) {
    return;
  }

  node._signalKeys.add(key);
  node.signals.push(normalizedSignal);
}

function readSignalEntriesFromObject(obj: unknown): Array<{ kind: string; entry: UnknownRecord }> {
  const out: Array<{ kind: string; entry: UnknownRecord }> = [];
  const record = asRecord(obj);
  if (!record) {
    return out;
  }

  for (const kind of ['ports', 'nets', 'regs', 'signals', 'wires']) {
    const entries = Array.isArray(record[kind]) ? record[kind] : [];
    for (const entry of entries) {
      const entryRecord = asRecord(entry);
      if (!entryRecord || typeof entryRecord.name !== 'string') {
        continue;
      }
      out.push({ kind, entry: entryRecord });
    }
  }

  return out;
}

export function deriveComponentName(obj: unknown, fallback: unknown): string {
  const record = asRecord(obj);
  if (record) {
    for (const key of [
      'instance_name',
      'inst_name',
      'instance',
      'name',
      'id',
      'module',
      'component',
      'label'
    ]) {
      const value = record[key];
      if (typeof value === 'string' && value.trim()) {
        return value.trim();
      }
    }
  }
  return String(fallback || 'component');
}

export function summarizeIrEntry(entry: unknown): unknown {
  const entryRecord = asRecord(entry);
  if (!entryRecord) {
    return entry;
  }

  const summary: Record<string, unknown> = {};
  for (const key of [
    'name',
    'kind',
    'type',
    'direction',
    'width',
    'clock',
    'reset',
    'path',
    'file',
    'line'
  ]) {
    if (entryRecord[key] !== undefined) {
      summary[key] = entryRecord[key];
    }
  }
  if (Object.keys(summary).length > 0) {
    return summary;
  }

  const keys = Object.keys(entryRecord);
  return { keys: keys.slice(0, 12), fieldCount: keys.length };
}

export function ellipsizeText(value: unknown, maxLen = 88): string {
  const text = String(value ?? '');
  if (text.length <= maxLen) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLen - 3))}...`;
}

export function summarizeIrNode(rawRef: unknown): Record<string, unknown> | null {
  const rawRecord = asRecord(rawRef);
  if (!rawRecord) {
    return null;
  }

  const summary: Record<string, unknown> = {};
  for (const key of [
    'name',
    'kind',
    'type',
    'instance',
    'instance_name',
    'module',
    'component',
    'path'
  ]) {
    if (rawRecord[key] !== undefined) {
      summary[key] = rawRecord[key];
    }
  }

  for (const key of [
    'ports',
    'nets',
    'regs',
    'signals',
    'processes',
    'assigns',
    'instances',
    'children',
    'modules',
    'components'
  ]) {
    if (!Array.isArray(rawRecord[key])) {
      continue;
    }
    const entries = rawRecord[key];
    const limit = 40;
    summary[key] = entries.slice(0, limit).map(summarizeIrEntry);
    if (entries.length > limit) {
      summary[`${key}_truncated`] = entries.length - limit;
    }
  }

  return summary;
}

function signalGroupToken(name: unknown): string | null {
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

function addSyntheticSignalGroupChildren(
  model: ComponentModel,
  node: ComponentNode,
  pathTokens: string[]
): number {
  if (!Array.isArray(node.signals) || node.signals.length < 16) {
    return 0;
  }

  const grouped = new Map<string, ComponentSignal[]>();
  for (const signal of node.signals) {
    const token = signalGroupToken(signal.name || signal.fullName);
    if (!token) {
      continue;
    }
    const list = grouped.get(token) || [];
    list.push(signal);
    grouped.set(token, list);
  }

  const groups = Array.from(grouped.entries())
    .filter(([, signals]) => signals.length >= 2)
    .sort((left, right) => {
      const countDiff = right[1].length - left[1].length;
      if (countDiff !== 0) {
        return countDiff;
      }
      return left[0].localeCompare(right[0]);
    })
    .slice(0, 8);

  if (groups.length === 0) {
    return 0;
  }

  const siblingNames = new Set<string>(
    node.children
      .map((childId) => model.nodes.get(childId)?.name?.toLowerCase())
      .filter((name): name is string => typeof name === 'string' && name.length > 0)
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

function buildHierarchicalComponentModel(meta: unknown): ComponentModel | null {
  const metaRecord = (asRecord(meta) || {}) as IrMetaLike & UnknownRecord;
  const ir = asRecord(metaRecord.ir);
  if (!ir) {
    return null;
  }

  const childKeys = ['children', 'instances', 'modules', 'components', 'submodules', 'blocks', 'units'];
  const hasExplicitHierarchy = childKeys.some((key) => {
    const childEntries = ir[key];
    return Array.isArray(childEntries) && childEntries.length > 0;
  });
  if (!hasExplicitHierarchy) {
    return null;
  }

  const signalSet = new Set(
    asStringArray(metaRecord.liveSignalNames || metaRecord.names)
  );
  const model: ComponentModel = {
    nextId: 1,
    mode: 'hierarchical',
    nodes: new Map<string, ComponentNode>(),
    rootId: null
  };

  const rootName = typeof ir.name === 'string' && ir.name.trim() ? ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], ir);
  model.rootId = root.id;

  const seen = new WeakSet<object>();

  function walk(node: ComponentNode, source: UnknownRecord, pathTokens: string[]): void {
    if (seen.has(source)) {
      return;
    }
    seen.add(source);

    for (const { kind, entry } of readSignalEntriesFromObject(source)) {
      const width = Number.parseInt(String(entry.width || ''), 10) || 1;
      const signalName = String(entry.name || '').trim();
      if (!signalName) {
        continue;
      }
      const liveName = resolveLiveSignalName(signalName, pathTokens, signalSet);
      addSignalToNode(node, {
        name: signalName,
        fullName: liveName || signalName,
        liveName,
        width,
        kind,
        direction: entry.direction ? String(entry.direction) : null,
        declaration: entry
      });
    }

    let explicitChildCount = 0;
    for (const key of childKeys) {
      const children = Array.isArray(source[key]) ? source[key] : [];
      const siblingNames = new Set<string>();
      children.forEach((child, index) => {
        const childRecord = asRecord(child);
        if (!childRecord) {
          return;
        }

        const baseName = deriveComponentName(childRecord, `${key}_${index}`);
        let childName = baseName;
        let dedupe = 1;
        while (siblingNames.has(childName)) {
          dedupe += 1;
          childName = `${baseName}_${dedupe}`;
        }
        siblingNames.add(childName);

        const childPath = [...pathTokens, childName];
        const childKind = key.endsWith('s') ? key.slice(0, -1) : key;
        const childNode = makeComponentNode(
          model,
          node.id,
          childName,
          childKind || 'component',
          childPath,
          childRecord
        );
        node.children.push(childNode.id);
        explicitChildCount += 1;
        walk(childNode, childRecord, childPath);
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

function buildDerivedFlatComponentModel(meta: unknown): ComponentModel {
  const metaRecord = (asRecord(meta) || {}) as IrMetaLike & UnknownRecord;
  const model: ComponentModel = {
    nextId: 1,
    mode: 'flat-derived',
    nodes: new Map<string, ComponentNode>(),
    rootId: null,
    pathMap: new Map<string, string>()
  };

  const ir = asRecord(metaRecord.ir);
  const rootName = typeof ir?.name === 'string' && ir.name.trim() ? ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], ir || null);
  model.rootId = root.id;
  model.pathMap?.set('', root.id);

  function ensurePath(pathTokens: string[]): ComponentNode {
    if (pathTokens.length === 0) {
      return root;
    }

    const pathKey = pathTokens.join('__');
    const existingId = model.pathMap?.get(pathKey);
    if (existingId) {
      const existingNode = model.nodes.get(existingId);
      if (existingNode) {
        return existingNode;
      }
    }

    const parentTokens = pathTokens.slice(0, -1);
    const parent = ensurePath(parentTokens);
    const name = pathTokens[pathTokens.length - 1];
    const node = makeComponentNode(model, parent.id, name, 'component', pathTokens, null);
    parent.children.push(node.id);
    model.pathMap?.set(pathKey, node.id);
    return node;
  }

  const signalInfo = metaRecord.signalInfo instanceof Map
    ? (metaRecord.signalInfo as Map<string, SignalInfo>)
    : new Map<string, SignalInfo>();
  const widths = metaRecord.widths instanceof Map
    ? (metaRecord.widths as Map<string, number>)
    : new Map<string, number>();

  for (const signalName of asStringArray(metaRecord.names)) {
    const info = signalInfo.get(signalName);
    const width = info?.width || widths.get(signalName) || 1;
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

function finalizeComponentModel(model: ComponentModel): ComponentModel {
  for (const node of model.nodes.values()) {
    node.children.sort((leftId, rightId) => {
      const left = model.nodes.get(leftId);
      const right = model.nodes.get(rightId);
      return (left?.name || '').localeCompare(right?.name || '');
    });
    node.signals.sort((left, right) =>
      (left.fullName || left.name || '').localeCompare(right.fullName || right.name || '')
    );
  }
  return model;
}

export function buildComponentModel(meta: unknown): ComponentModel {
  const hierarchical = buildHierarchicalComponentModel(meta);
  if (hierarchical) {
    return finalizeComponentModel(hierarchical);
  }
  return finalizeComponentModel(buildDerivedFlatComponentModel(meta));
}

export function nodeMatchesFilter(node: ComponentNode, filter: unknown): boolean {
  const rawFilter = String(filter || '').trim().toLowerCase();
  if (!rawFilter) {
    return true;
  }

  const nodeName = String(node?.name || '').toLowerCase();
  if (nodeName.includes(rawFilter)) {
    return true;
  }
  const nodePath = String(node?.path || '').toLowerCase();
  if (nodePath.includes(rawFilter)) {
    return true;
  }
  for (const signal of node.signals) {
    const full = (signal.fullName || signal.name || '').toLowerCase();
    if (full.includes(rawFilter)) {
      return true;
    }
  }
  return false;
}
