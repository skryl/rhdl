export const DUMP_ASSET_EXTENSIONS = Object.freeze(['.bin', '.mem', '.dat', '.rhdlsnap', '.snapshot']);

function extensionAllowed(pathValue) {
  const lower = String(pathValue || '').toLowerCase();
  return DUMP_ASSET_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

function normalizeAssetPathPrefix(pathValue) {
  if (pathValue.startsWith('./')) {
    return pathValue;
  }
  if (pathValue.startsWith('assets/')) {
    return `./${pathValue}`;
  }
  return pathValue;
}

export function normalizeDumpAssetPath(rawPath) {
  const normalized = normalizeAssetPathPrefix(String(rawPath || '').trim().replace(/\\/g, '/'));
  return normalized.replace(/\/{2,}/g, '/');
}

export function isDumpAssetPath(pathValue) {
  const normalized = normalizeDumpAssetPath(pathValue);
  if (!normalized || !normalized.startsWith('./assets/')) {
    return false;
  }
  return extensionAllowed(normalized);
}

function createTreeNode(name = '', path = '') {
  return {
    name,
    path,
    dirs: new Map(),
    files: []
  };
}

function sortByName(a, b) {
  return String(a.name || '').localeCompare(String(b.name || ''), undefined, { sensitivity: 'base' });
}

function materializeTree(node) {
  return {
    name: node.name,
    path: node.path,
    dirs: Array.from(node.dirs.values()).sort(sortByName).map(materializeTree),
    files: node.files.sort(sortByName)
  };
}

export function createDumpAssetTree(paths = []) {
  const root = createTreeNode();
  for (const rawPath of paths) {
    const normalizedPath = normalizeDumpAssetPath(rawPath);
    if (!isDumpAssetPath(normalizedPath)) {
      continue;
    }

    const cleanPath = normalizedPath.replace(/^\.\//, '');
    const segments = cleanPath.split('/').filter(Boolean);
    if (segments.length === 0) {
      continue;
    }

    const fileName = segments[segments.length - 1];
    const dirs = segments.slice(0, -1);
    let node = root;
    let runningPath = '';
    for (const dirName of dirs) {
      runningPath = runningPath ? `${runningPath}/${dirName}` : dirName;
      if (!node.dirs.has(dirName)) {
        node.dirs.set(dirName, createTreeNode(dirName, `./${runningPath}`));
      }
      node = node.dirs.get(dirName);
    }
    node.files.push({
      name: fileName,
      path: normalizedPath
    });
  }

  return materializeTree(root);
}
