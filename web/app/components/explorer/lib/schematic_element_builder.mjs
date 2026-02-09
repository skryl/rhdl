function componentCyIdForNode(nodeId) {
  return `cmp:${String(nodeId || '')}`;
}

export function createSchematicElementBuilder({
  state,
  runtime,
  componentSignalLookup,
  resolveNodeSignalRef,
  collectExprSignalNames,
  findComponentSchematicEntry,
  summarizeExpr,
  ellipsizeText
} = {}) {
  if (!state || !runtime) {
    throw new Error('createSchematicElementBuilder requires state/runtime');
  }

  function createComponentSchematicElementsFromExport(model, focusNode, showChildren, schematicEntry) {
    const elements = [];
    if (!model || !focusNode || !schematicEntry || typeof schematicEntry !== 'object') {
      return elements;
    }
    const schematic = schematicEntry.schematic;
    if (!schematic || typeof schematic !== 'object') {
      return elements;
    }

    const lookup = componentSignalLookup(focusNode);
    const seenNodes = new Set();
    const seenEdges = new Set();
    let edgeSeq = 0;

    const pathToNodeId = new Map();
    for (const node of model.nodes.values()) {
      pathToNodeId.set(String(node.path || ''), node.id);
    }

    const normalizeSignal = (name, width = 1, liveName = null) => {
      const signalName = String(name || '').trim();
      if (!signalName) {
        return null;
      }
      const ref = resolveNodeSignalRef(focusNode, lookup, signalName, width);
      const explicitLive = String(liveName || '').trim();
      if (explicitLive) {
        ref.liveName = explicitLive;
        ref.valueKey = explicitLive;
      }
      return ref;
    };

    const pushNode = (id, data, classes = '') => {
      if (!id || seenNodes.has(id)) {
        return;
      }
      seenNodes.add(id);
      elements.push({
        data: {
          id,
          ...data
        },
        classes
      });
    };

    const pushEdge = (source, target, data = {}, classes = '') => {
      if (!source || !target || !seenNodes.has(source) || !seenNodes.has(target)) {
        return;
      }
      edgeSeq += 1;
      const base = data.id || `wire:${source}:${target}:${edgeSeq}`;
      let id = base;
      while (seenEdges.has(id)) {
        edgeSeq += 1;
        id = `${base}:${edgeSeq}`;
      }
      seenEdges.add(id);
      elements.push({
        data: {
          id,
          source,
          target,
          ...data
        },
        classes
      });
    };

    const pins = Array.isArray(schematic.pins) ? schematic.pins : [];
    const pinCountBySymbol = new Map();
    for (const pin of pins) {
      const symbolId = String(pin?.symbol_id || '').trim();
      const side = String(pin?.side || 'left').trim().toLowerCase();
      if (!symbolId) {
        continue;
      }
      if (!pinCountBySymbol.has(symbolId)) {
        pinCountBySymbol.set(symbolId, { left: 0, right: 0, top: 0, bottom: 0 });
      }
      const counts = pinCountBySymbol.get(symbolId);
      if (Object.prototype.hasOwnProperty.call(counts, side)) {
        counts[side] += 1;
      } else {
        counts.left += 1;
      }
    }

    const symbolIdSet = new Set();
    const netIdSet = new Set();
    const pinIdSet = new Set();
    const netSignalById = new Map();
    const hideTopFocusSymbol = String(focusNode.path || 'top') === 'top';

    const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
    for (const symbol of symbols) {
      if (!symbol || typeof symbol !== 'object') {
        continue;
      }
      const symbolId = String(symbol.id || '').trim();
      if (!symbolId) {
        continue;
      }
      const symbolType = String(symbol.type || 'component').trim().toLowerCase();
      const componentPath = String(symbol.component_path || '').trim();
      if (hideTopFocusSymbol && symbolType === 'focus') {
        continue;
      }
      const isChildComponent = symbolType === 'component' && componentPath && componentPath !== String(focusNode.path || 'top');
      if (!showChildren && isChildComponent) {
        continue;
      }

      const componentId = (() => {
        if (symbolType === 'focus') {
          return focusNode.id;
        }
        if (!componentPath) {
          return '';
        }
        return String(pathToNodeId.get(componentPath) || '');
      })();

      const direction = String(symbol.direction || '').trim().toLowerCase();
      const counts = pinCountBySymbol.get(symbolId) || { left: 0, right: 0, top: 0, bottom: 0 };
      const verticalPins = Math.max(counts.left, counts.right);
      const horizontalPins = Math.max(counts.top, counts.bottom);
      const baseWidth = symbolType === 'focus'
        ? 228
        : symbolType === 'component'
          ? 178
          : symbolType === 'memory'
            ? 118
            : symbolType === 'op'
              ? 102
              : symbolType === 'io'
                ? 34
                : 112;
      const baseHeight = symbolType === 'focus'
        ? 94
        : symbolType === 'component'
          ? 72
          : symbolType === 'memory'
            ? 54
            : symbolType === 'op'
              ? 42
              : symbolType === 'io'
                ? 16
                : 46;
      const scalable = symbolType === 'focus' || symbolType === 'component' || symbolType === 'memory';
      const symbolWidth = scalable
        ? Math.min(420, Math.max(baseWidth, baseWidth + Math.max(0, horizontalPins - 4) * 10))
        : baseWidth;
      const symbolHeight = scalable
        ? Math.min(420, Math.max(baseHeight, baseHeight + Math.max(0, verticalPins - 4) * 12))
        : baseHeight;

      const classes = [
        'schem-symbol',
        symbolType === 'focus' || symbolType === 'component' ? 'schem-component' : '',
        symbolType === 'focus' ? 'schem-focus' : '',
        symbolType === 'io' ? `schem-io ${direction === 'in' ? 'schem-io-in' : direction === 'out' ? 'schem-io-out' : ''}` : '',
        symbolType === 'memory' ? 'schem-memory' : '',
        symbolType === 'op' ? 'schem-op' : ''
      ].filter(Boolean).join(' ');

      pushNode(symbolId, {
        label: String(symbol.label || symbol.name || symbolId),
        nodeRole: 'symbol',
        symbolType,
        componentId,
        path: componentPath || '',
        direction,
        symbolWidth,
        symbolHeight
      }, classes);
      symbolIdSet.add(symbolId);
    }

    const nets = Array.isArray(schematic.nets) ? schematic.nets : [];
    for (const net of nets) {
      if (!net || typeof net !== 'object') {
        continue;
      }
      const netId = String(net.id || '').trim();
      const signalName = String(net.name || net.signal || '').trim();
      if (!netId || !signalName) {
        continue;
      }
      const width = Number.parseInt(net.width, 10) || 1;
      const signalRef = normalizeSignal(signalName, width, net.live_name);
      const classes = ['schem-net'];
      if ((signalRef?.width || width || 1) > 1 || net.bus) {
        classes.push('schem-bus');
      }
      pushNode(netId, {
        label: ellipsizeText(signalName, 18),
        nodeRole: 'net',
        signalName: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
        width: signalRef?.width || width || 1,
        group: String(net.group || '')
      }, classes.join(' '));
      netIdSet.add(netId);
      netSignalById.set(netId, {
        signalName: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
        width: signalRef?.width || width || 1
      });
    }

    for (const pin of pins) {
      if (!pin || typeof pin !== 'object') {
        continue;
      }
      const pinId = String(pin.id || '').trim();
      const symbolId = String(pin.symbol_id || '').trim();
      if (!pinId || !symbolId || !symbolIdSet.has(symbolId)) {
        continue;
      }

      const signalName = String(pin.signal || pin.name || '').trim();
      const width = Number.parseInt(pin.width, 10) || 1;
      const signalRef = signalName ? normalizeSignal(signalName, width, pin.live_name) : null;
      const side = ['left', 'right', 'top', 'bottom'].includes(String(pin.side || '').toLowerCase())
        ? String(pin.side || '').toLowerCase()
        : 'left';
      const direction = String(pin.direction || 'inout').toLowerCase();
      const classes = ['schem-pin', `schem-pin-${side}`];
      if ((signalRef?.width || width || 1) > 1 || pin.bus) {
        classes.push('schem-bus');
      }

      pushNode(pinId, {
        label: String(pin.name || signalRef?.name || pinId),
        nodeRole: 'pin',
        symbolId,
        side,
        order: Number.parseInt(pin.order, 10) || 0,
        direction,
        signalName: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || (signalName ? `${focusNode.path}::${signalName}` : ''),
        width: signalRef?.width || width || 1
      }, classes.join(' '));
      pinIdSet.add(pinId);
    }

    const wires = Array.isArray(schematic.wires) ? schematic.wires : [];
    for (const wire of wires) {
      if (!wire || typeof wire !== 'object') {
        continue;
      }
      const fromPinId = String(wire.from_pin_id || '').trim();
      const toPinId = String(wire.to_pin_id || '').trim();
      let netId = String(wire.net_id || '').trim();
      if (!fromPinId || !toPinId) {
        continue;
      }
      const hasFrom = pinIdSet.has(fromPinId);
      const hasTo = pinIdSet.has(toPinId);
      if (!hasFrom && !hasTo) {
        continue;
      }

      if (!netId || !netIdSet.has(netId)) {
        const signalName = String(wire.signal || '').trim();
        if (!signalName) {
          continue;
        }
        const width = Number.parseInt(wire.width, 10) || 1;
        const signalRef = normalizeSignal(signalName, width, wire.live_name);
        netId = `net:${focusNode.id}:${signalRef?.name || signalName}`;
        if (!netIdSet.has(netId)) {
          pushNode(netId, {
            label: ellipsizeText(signalRef?.name || signalName, 18),
            nodeRole: 'net',
            signalName: signalRef?.name || signalName,
            liveName: signalRef?.liveName || '',
            valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
            width: signalRef?.width || width || 1
          }, (signalRef?.width || width || 1) > 1 ? 'schem-net schem-bus' : 'schem-net');
          netIdSet.add(netId);
        }
        netSignalById.set(netId, {
          signalName: signalRef?.name || signalName,
          liveName: signalRef?.liveName || '',
          valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
          width: signalRef?.width || width || 1
        });
      }

      const netSignal = netSignalById.get(netId) || {};
      const direction = String(wire.direction || 'inout').toLowerCase();
      const width = Number.parseInt(wire.width, 10) || netSignal.width || 1;
      const signalName = String(wire.signal || netSignal.signalName || '').trim();
      const liveName = String(wire.live_name || netSignal.liveName || '').trim();
      const valueKey = String(netSignal.valueKey || (signalName ? `${focusNode.path}::${signalName}` : '')).trim();
      const wireKind = String(wire.kind || 'wire').trim();

      const classes = ['schem-wire', `schem-kind-${wireKind.replace(/[^a-zA-Z0-9_-]+/g, '_')}`];
      if (width > 1) {
        classes.push('schem-bus');
      }
      if (direction === 'inout') {
        classes.push('schem-bidir');
      }

      const edgeData = {
        signalName,
        liveName,
        valueKey,
        width,
        direction,
        kind: wireKind,
        wireId: String(wire.id || ''),
        netId
      };

      if (hasFrom) {
        pushEdge(fromPinId, netId, { ...edgeData, segment: 'from', id: `${wire.id || `${fromPinId}:${netId}`}:from` }, classes.join(' '));
      }
      if (hasTo) {
        pushEdge(netId, toPinId, { ...edgeData, segment: 'to', id: `${wire.id || `${netId}:${toPinId}`}:to` }, classes.join(' '));
      }
    }

    return elements;
  }

  function createComponentSchematicElements(model, focusNode, showChildren) {
    const elements = [];
    if (!model || !focusNode) {
      return elements;
    }

    const schematicEntry = findComponentSchematicEntry(focusNode);
    if (schematicEntry) {
      return createComponentSchematicElementsFromExport(model, focusNode, showChildren, schematicEntry);
    }

    const lookup = componentSignalLookup(focusNode);
    const liveSignalSet = new Set(
      state.components.overrideMeta?.liveSignalNames
      || state.components.overrideMeta?.names
      || runtime.irMeta?.names
      || []
    );
    const raw = focusNode.rawRef && typeof focusNode.rawRef === 'object' ? focusNode.rawRef : {};
    const seenNodes = new Set();
    const seenEdges = new Set();
    const netNodes = new Map();
    let edgeSeq = 0;

    const pushNode = (id, data, classes = '') => {
      if (!id || seenNodes.has(id)) {
        return;
      }
      seenNodes.add(id);
      elements.push({
        data: {
          id,
          ...data
        },
        classes
      });
    };

    const pushEdge = (source, target, data = {}, classes = '') => {
      if (!source || !target) {
        return;
      }
      edgeSeq += 1;
      const base = data.id || `wire:${source}:${target}:${edgeSeq}`;
      let id = base;
      while (seenEdges.has(id)) {
        edgeSeq += 1;
        id = `${base}:${edgeSeq}`;
      }
      seenEdges.add(id);
      elements.push({
        data: {
          id,
          source,
          target,
          ...data
        },
        classes
      });
    };

    const ensureNet = (name, width = 1) => {
      const signalName = String(name || '').trim();
      if (!signalName) {
        return null;
      }
      if (netNodes.has(signalName)) {
        return netNodes.get(signalName);
      }
      const ref = resolveNodeSignalRef(focusNode, lookup, signalName, width, liveSignalSet);
      const id = `net:${focusNode.id}:${signalName}`;
      pushNode(id, {
        label: signalName,
        nodeRole: 'net',
        signalName: ref?.name || signalName,
        liveName: ref?.liveName || '',
        valueKey: ref?.valueKey || `${focusNode.path}::${signalName}`,
        width: ref?.width || width || 1
      }, 'schem-net');
      netNodes.set(signalName, id);
      return id;
    };

    const addPortEdge = (fromId, toId, signalRef, direction, kind = 'port') => {
      if (!fromId || !toId || !signalRef) {
        return;
      }
      const edgeData = {
        signalName: signalRef.name,
        liveName: signalRef.liveName || '',
        valueKey: signalRef.valueKey,
        width: signalRef.width || 1,
        direction: direction || '?',
        kind
      };
      if (direction === 'in') {
        pushEdge(fromId, toId, edgeData, 'schem-wire schem-port-wire');
      } else if (direction === 'out') {
        pushEdge(toId, fromId, edgeData, 'schem-wire schem-port-wire');
      } else {
        pushEdge(fromId, toId, edgeData, 'schem-wire schem-port-wire schem-bidir');
      }
    };

    const focusCyId = componentCyIdForNode(focusNode.id);
    pushNode(focusCyId, {
      label: focusNode.name,
      nodeRole: 'component',
      componentId: focusNode.id,
      isFocus: 1,
      path: focusNode.path,
      signals: focusNode.signals.length,
      children: focusNode.children.length
    }, 'schem-component schem-focus schem-component-fallback');

    const rawPorts = Array.isArray(raw.ports) ? raw.ports : [];
    const maxIoPorts = 120;
    for (const port of rawPorts.slice(0, maxIoPorts)) {
      if (!port || typeof port.name !== 'string') {
        continue;
      }
      const signalRef = resolveNodeSignalRef(focusNode, lookup, port.name, Number.parseInt(port.width, 10) || 1, liveSignalSet);
      const netId = ensureNet(port.name, signalRef?.width || 1);
      if (!netId || !signalRef) {
        continue;
      }
      const direction = String(port.direction || '?').toLowerCase();
      const ioId = `io:${focusNode.id}:${signalRef.name}`;
      const ioClass = direction === 'in'
        ? 'schem-io schem-io-in'
        : direction === 'out'
          ? 'schem-io schem-io-out'
          : 'schem-io';
      pushNode(ioId, {
        label: signalRef.name,
        nodeRole: 'io',
        signalName: signalRef.name,
        liveName: signalRef.liveName || '',
        valueKey: signalRef.valueKey,
        direction
      }, ioClass);
      addPortEdge(ioId, netId, signalRef, direction, 'io-port');
    }

    const shouldShowChildren = !!showChildren;
    if (shouldShowChildren) {
      for (const childId of focusNode.children || []) {
        const childNode = model.nodes.get(childId);
        if (!childNode) {
          continue;
        }
        const childCyId = componentCyIdForNode(childNode.id);
        const childLabel = childNode.kind === 'signal-group'
          ? `${childNode.name} [signals]`
          : childNode.name;
        pushNode(childCyId, {
          label: childLabel,
          nodeRole: 'component',
          componentId: childNode.id,
          isFocus: 0,
          path: childNode.path,
          signals: childNode.signals.length,
          children: childNode.children.length
        }, 'schem-component schem-component-fallback');

        const childRaw = childNode.rawRef && typeof childNode.rawRef === 'object' ? childNode.rawRef : {};
        const childPorts = Array.isArray(childRaw.ports) ? childRaw.ports : [];
        for (const port of childPorts) {
          if (!port || typeof port.name !== 'string') {
            continue;
          }
          const signalRef = resolveNodeSignalRef(focusNode, lookup, port.name, Number.parseInt(port.width, 10) || 1, liveSignalSet);
          const netId = ensureNet(port.name, signalRef?.width || 1);
          if (!netId || !signalRef) {
            continue;
          }
          const direction = String(port.direction || '?').toLowerCase();
          addPortEdge(netId, childCyId, signalRef, direction, 'child-port');
        }
      }
    }

    const memoryNodes = new Set();
    const ensureMemoryNode = (name) => {
      const memoryName = String(name || '').trim();
      if (!memoryName) {
        return null;
      }
      const id = `mem:${focusNode.id}:${memoryName}`;
      if (!memoryNodes.has(id)) {
        memoryNodes.add(id);
        pushNode(id, {
          label: memoryName,
          nodeRole: 'memory'
        }, 'schem-memory');
      }
      return id;
    };

    const addAssignEdges = () => {
      const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
      const maxAssigns = shouldShowChildren && focusNode.children.length > 0 ? 48 : 220;
      for (let idx = 0; idx < Math.min(assigns.length, maxAssigns); idx += 1) {
        const assign = assigns[idx];
        const targetName = String(assign?.target || '').trim();
        if (!targetName) {
          continue;
        }
        const opId = `op:${focusNode.id}:assign:${idx}`;
        pushNode(opId, {
          label: `= ${targetName}`,
          nodeRole: 'op'
        }, 'schem-op');

        const targetRef = resolveNodeSignalRef(focusNode, lookup, targetName, 1, liveSignalSet);
        const targetNetId = ensureNet(targetRef?.name || targetName, targetRef?.width || 1);
        if (targetRef && targetNetId) {
          pushEdge(opId, targetNetId, {
            signalName: targetRef.name,
            liveName: targetRef.liveName || '',
            valueKey: targetRef.valueKey,
            kind: 'assign-target'
          }, 'schem-wire');
        }

        const sourceSignals = Array.from(collectExprSignalNames(assign?.expr, new Set(), 14));
        for (const sourceName of sourceSignals) {
          const sourceRef = resolveNodeSignalRef(focusNode, lookup, sourceName, 1, liveSignalSet);
          const sourceNetId = ensureNet(sourceRef?.name || sourceName, sourceRef?.width || 1);
          if (!sourceRef || !sourceNetId) {
            continue;
          }
          pushEdge(sourceNetId, opId, {
            signalName: sourceRef.name,
            liveName: sourceRef.liveName || '',
            valueKey: sourceRef.valueKey,
            kind: 'assign-source'
          }, 'schem-wire');
        }
      }
    };

    const writePorts = Array.isArray(raw.write_ports) ? raw.write_ports : [];
    for (const [idx, port] of writePorts.entries()) {
      const memId = ensureMemoryNode(port?.memory || `mem_wr_${idx}`);
      if (!memId) {
        continue;
      }
      for (const signalName of [summarizeExpr(port?.addr), summarizeExpr(port?.data), summarizeExpr(port?.enable), port?.clock]) {
        const ref = resolveNodeSignalRef(focusNode, lookup, signalName, 1, liveSignalSet);
        const netId = ensureNet(ref?.name || signalName, 1);
        if (!ref || !netId) {
          continue;
        }
        pushEdge(netId, memId, {
          signalName: ref.name,
          liveName: ref.liveName || '',
          valueKey: ref.valueKey,
          kind: 'mem-write'
        }, 'schem-wire');
      }
    }

    const syncReadPorts = Array.isArray(raw.sync_read_ports) ? raw.sync_read_ports : [];
    for (const [idx, port] of syncReadPorts.entries()) {
      const memId = ensureMemoryNode(port?.memory || `mem_rd_${idx}`);
      if (!memId) {
        continue;
      }
      for (const signalName of [summarizeExpr(port?.addr), summarizeExpr(port?.enable), port?.clock]) {
        const ref = resolveNodeSignalRef(focusNode, lookup, signalName, 1, liveSignalSet);
        const netId = ensureNet(ref?.name || signalName, 1);
        if (!ref || !netId) {
          continue;
        }
        pushEdge(netId, memId, {
          signalName: ref.name,
          liveName: ref.liveName || '',
          valueKey: ref.valueKey,
          kind: 'mem-read-ctrl'
        }, 'schem-wire');
      }
      const dataRef = resolveNodeSignalRef(focusNode, lookup, port?.data, 1, liveSignalSet);
      const dataNetId = ensureNet(dataRef?.name || port?.data, 1);
      if (dataRef && dataNetId) {
        pushEdge(memId, dataNetId, {
          signalName: dataRef.name,
          liveName: dataRef.liveName || '',
          valueKey: dataRef.valueKey,
          kind: 'mem-read-data'
        }, 'schem-wire');
      }
    }

    addAssignEdges();

    return elements;
  }

  return {
    createComponentSchematicElements
  };
}
