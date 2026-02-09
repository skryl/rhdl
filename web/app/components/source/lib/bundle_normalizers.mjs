export function normalizeComponentSourceBundle(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }

  const components = Array.isArray(raw.components) ? raw.components : [];
  const byClass = new Map();
  const byModule = new Map();
  for (const entry of components) {
    if (!entry || typeof entry !== 'object') {
      continue;
    }
    const className = String(entry.component_class || '').trim();
    const moduleName = String(entry.module_name || '').trim();
    if (className) {
      byClass.set(className, entry);
    }
    if (moduleName) {
      byModule.set(moduleName, entry);
      byModule.set(moduleName.toLowerCase(), entry);
    }
  }

  let topEntry = null;
  const topClass = String(raw.top_component_class || '').trim();
  if (topClass && byClass.has(topClass)) {
    topEntry = byClass.get(topClass);
  } else if (raw.top && typeof raw.top === 'object') {
    topEntry = raw.top;
  } else if (components.length > 0) {
    topEntry = components[0];
  }

  return {
    ...raw,
    components,
    byClass,
    byModule,
    top: topEntry
  };
}

export function normalizeComponentSchematicBundle(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  const components = Array.isArray(raw.components) ? raw.components : [];
  const byPath = new Map();
  for (const entry of components) {
    if (!entry || typeof entry !== 'object') {
      continue;
    }
    const path = String(entry.path || '').trim();
    if (!path) {
      continue;
    }
    byPath.set(path, entry);
  }
  return {
    ...raw,
    components,
    byPath
  };
}
