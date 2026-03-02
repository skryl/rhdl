import {
  asRecord,
  asStringArray,
  type ComponentModel,
  type ComponentNode,
  type ComponentSignal,
  type ExplorerRuntimeLike,
  type ExplorerStateLike,
  type SchematicBundleEntry,
  type SchematicElement,
  type UnknownRecord
} from './types';

interface SignalRef {
  name: string;
  liveName: string | null;
  width: number;
  valueKey: string;
}

interface SchematicElementBuilderOptions {
  state: ExplorerStateLike;
  runtime: ExplorerRuntimeLike;
  componentSignalLookup: (node: ComponentNode) => Map<string, ComponentSignal>;
  resolveNodeSignalRef: (
    node: ComponentNode,
    lookup: Map<string, ComponentSignal>,
    signalName: unknown,
    width?: number,
    signalSet?: Set<string> | null
  ) => SignalRef | null;
  collectExprSignalNames: (expr: unknown, out?: Set<string>, maxSignals?: number) => Set<string>;
  findComponentSchematicEntry: (node: ComponentNode) => SchematicBundleEntry | null;
  summarizeExpr: (expr: unknown) => string;
  ellipsizeText: (value: unknown, maxLen?: number) => string;
}

function componentCyIdForNode(nodeId: string): string {
  return `cmp:${nodeId}`;
}

function readWidth(value: unknown, fallback = 1): number {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function normalizeSide(side: unknown): string {
  const raw = String(side || '').toLowerCase();
  return ['left', 'right', 'top', 'bottom'].includes(raw) ? raw : 'left';
}

function normalizeDirection(direction: unknown): string {
  return String(direction || 'inout').toLowerCase();
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
}: SchematicElementBuilderOptions) {
  if (!state || !runtime) {
    throw new Error('createSchematicElementBuilder requires state/runtime');
  }

  function createComponentSchematicElementsFromExport(
    model: ComponentModel,
    focusNode: ComponentNode,
    showChildren: boolean,
    schematicEntry: SchematicBundleEntry
  ): SchematicElement[] {
    const elements: SchematicElement[] = [];
    const schematic = asRecord(schematicEntry.schematic);
    if (!schematic) {
      return elements;
    }

    const lookup = componentSignalLookup(focusNode);
    const seenNodes = new Set<string>();
    const seenEdges = new Set<string>();
    let edgeSeq = 0;

    const pathToNodeId = new Map<string, string>();
    for (const node of model.nodes.values()) {
      pathToNodeId.set(String(node.path || ''), node.id);
    }

    const normalizeSignal = (
      name: unknown,
      width = 1,
      liveName: unknown = null
    ): SignalRef | null => {
      const signalName = String(name || '').trim();
      if (!signalName) {
        return null;
      }
      const ref = resolveNodeSignalRef(focusNode, lookup, signalName, width);
      if (!ref) {
        return null;
      }
      const explicitLive = String(liveName || '').trim();
      if (explicitLive) {
        ref.liveName = explicitLive;
        ref.valueKey = explicitLive;
      }
      return ref;
    };

    const pushNode = (id: string, data: UnknownRecord, classes = ''): void => {
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

    const pushEdge = (
      source: string,
      target: string,
      data: UnknownRecord = {},
      classes = ''
    ): void => {
      if (!source || !target || !seenNodes.has(source) || !seenNodes.has(target)) {
        return;
      }
      edgeSeq += 1;
      const base = String(data.id || `wire:${source}:${target}:${edgeSeq}`);
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
    const pinCountBySymbol = new Map<string, Record<string, number>>();
    for (const pin of pins) {
      const pinRecord = asRecord(pin);
      const symbolId = pinRecord ? String(pinRecord.symbol_id || '').trim() : '';
      const side = normalizeSide(pinRecord?.side || 'left');
      if (!symbolId) {
        continue;
      }
      if (!pinCountBySymbol.has(symbolId)) {
        pinCountBySymbol.set(symbolId, { left: 0, right: 0, top: 0, bottom: 0 });
      }
      const counts = pinCountBySymbol.get(symbolId);
      if (!counts) {
        continue;
      }
      if (Object.prototype.hasOwnProperty.call(counts, side)) {
        counts[side] += 1;
      } else {
        counts.left += 1;
      }
    }

    const symbolIdSet = new Set<string>();
    const netIdSet = new Set<string>();
    const pinIdSet = new Set<string>();
    const netSignalById = new Map<string, SignalRef>();
    const hideTopFocusSymbol = String(focusNode.path || 'top') === 'top';

    const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
    for (const symbol of symbols) {
      const symbolRecord = asRecord(symbol);
      if (!symbolRecord) {
        continue;
      }
      const symbolId = String(symbolRecord.id || '').trim();
      if (!symbolId) {
        continue;
      }
      const symbolType = String(symbolRecord.type || 'component').trim().toLowerCase();
      const componentPath = String(symbolRecord.component_path || '').trim();
      if (hideTopFocusSymbol && symbolType === 'focus') {
        continue;
      }
      const isChildComponent = (
        symbolType === 'component'
        && componentPath
        && componentPath !== String(focusNode.path || 'top')
      );
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

      const direction = normalizeDirection(symbolRecord.direction || '');
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
                ? 52
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
                ? 18
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
        symbolType === 'io'
          ? `schem-io ${direction === 'in' ? 'schem-io-in' : direction === 'out' ? 'schem-io-out' : ''}`
          : '',
        symbolType === 'memory' ? 'schem-memory' : '',
        symbolType === 'op' ? 'schem-op' : ''
      ].filter(Boolean).join(' ');

      pushNode(symbolId, {
        label: String(symbolRecord.label || symbolRecord.name || symbolId),
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
      const netRecord = asRecord(net);
      if (!netRecord) {
        continue;
      }
      const netId = String(netRecord.id || '').trim();
      const signalName = String(netRecord.name || netRecord.signal || '').trim();
      if (!netId || !signalName) {
        continue;
      }
      const width = readWidth(netRecord.width, 1);
      const signalRef = normalizeSignal(signalName, width, netRecord.live_name);
      const classes = ['schem-net'];
      if ((signalRef?.width || width || 1) > 1 || Boolean(netRecord.bus)) {
        classes.push('schem-bus');
      }
      pushNode(netId, {
        label: ellipsizeText(signalName, 18),
        nodeRole: 'net',
        signalName: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
        width: signalRef?.width || width || 1,
        group: String(netRecord.group || '')
      }, classes.join(' '));
      netIdSet.add(netId);
      netSignalById.set(netId, {
        name: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
        width: signalRef?.width || width || 1
      });
    }

    for (const pin of pins) {
      const pinRecord = asRecord(pin);
      if (!pinRecord) {
        continue;
      }
      const pinId = String(pinRecord.id || '').trim();
      const symbolId = String(pinRecord.symbol_id || '').trim();
      if (!pinId || !symbolId || !symbolIdSet.has(symbolId)) {
        continue;
      }

      const signalName = String(pinRecord.signal || pinRecord.name || '').trim();
      const width = readWidth(pinRecord.width, 1);
      const signalRef = signalName ? normalizeSignal(signalName, width, pinRecord.live_name) : null;
      const side = normalizeSide(pinRecord.side);
      const direction = normalizeDirection(pinRecord.direction || 'inout');
      const classes = ['schem-pin', `schem-pin-${side}`];
      if ((signalRef?.width || width || 1) > 1 || Boolean(pinRecord.bus)) {
        classes.push('schem-bus');
      }

      pushNode(pinId, {
        label: String(pinRecord.name || signalRef?.name || pinId),
        nodeRole: 'pin',
        symbolId,
        side,
        order: readWidth(pinRecord.order, 0),
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
      const wireRecord = asRecord(wire);
      if (!wireRecord) {
        continue;
      }
      const fromPinId = String(wireRecord.from_pin_id || '').trim();
      const toPinId = String(wireRecord.to_pin_id || '').trim();
      let netId = String(wireRecord.net_id || '').trim();
      if (!fromPinId || !toPinId) {
        continue;
      }
      const hasFrom = pinIdSet.has(fromPinId);
      const hasTo = pinIdSet.has(toPinId);
      if (!hasFrom && !hasTo) {
        continue;
      }

      if (!netId || !netIdSet.has(netId)) {
        const signalName = String(wireRecord.signal || '').trim();
        if (!signalName) {
          continue;
        }
        const width = readWidth(wireRecord.width, 1);
        const signalRef = normalizeSignal(signalName, width, wireRecord.live_name);
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
          name: signalRef?.name || signalName,
          liveName: signalRef?.liveName || '',
          valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
          width: signalRef?.width || width || 1
        });
      }

      const netSignal = netSignalById.get(netId);
      const direction = normalizeDirection(wireRecord.direction || 'inout');
      const width = readWidth(wireRecord.width, netSignal?.width || 1);
      const signalName = String(wireRecord.signal || netSignal?.name || '').trim();
      const liveName = String(wireRecord.live_name || netSignal?.liveName || '').trim();
      const valueKey = String(netSignal?.valueKey || (signalName ? `${focusNode.path}::${signalName}` : '')).trim();
      const wireKind = String(wireRecord.kind || 'wire').trim();

      const classes = ['schem-wire', `schem-kind-${wireKind.replace(/[^a-zA-Z0-9_-]+/g, '_')}`];
      if (width > 1) {
        classes.push('schem-bus');
      }
      if (direction === 'inout') {
        classes.push('schem-bidir');
      }

      const edgeData: UnknownRecord = {
        signalName,
        liveName,
        valueKey,
        width,
        direction,
        kind: wireKind,
        wireId: String(wireRecord.id || ''),
        netId
      };

      if (hasFrom) {
        pushEdge(fromPinId, netId, {
          ...edgeData,
          segment: 'from',
          id: `${String(wireRecord.id || `${fromPinId}:${netId}`)}:from`
        }, classes.join(' '));
      }
      if (hasTo) {
        pushEdge(netId, toPinId, {
          ...edgeData,
          segment: 'to',
          id: `${String(wireRecord.id || `${netId}:${toPinId}`)}:to`
        }, classes.join(' '));
      }
    }

    return elements;
  }

  function createComponentSchematicElements(
    model: ComponentModel,
    focusNode: ComponentNode,
    showChildren: boolean
  ): SchematicElement[] {
    const elements: SchematicElement[] = [];
    if (!model || !focusNode) {
      return elements;
    }

    const schematicEntry = findComponentSchematicEntry(focusNode);
    if (schematicEntry) {
      return createComponentSchematicElementsFromExport(model, focusNode, showChildren, schematicEntry);
    }

    const lookup = componentSignalLookup(focusNode);
    const liveSignalSet = new Set(
      asStringArray(
        state.components.overrideMeta?.liveSignalNames
        || state.components.overrideMeta?.names
        || runtime.irMeta?.names
      )
    );
    const raw = focusNode.rawRef || {};
    const seenNodes = new Set<string>();
    const seenEdges = new Set<string>();
    const netNodes = new Map<string, string>();
    let edgeSeq = 0;

    const pushNode = (id: string, data: UnknownRecord, classes = ''): void => {
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

    const pushEdge = (
      source: string,
      target: string,
      data: UnknownRecord = {},
      classes = ''
    ): void => {
      if (!source || !target) {
        return;
      }
      edgeSeq += 1;
      const base = String(data.id || `wire:${source}:${target}:${edgeSeq}`);
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

    const ensureNet = (name: unknown, width = 1): string | null => {
      const signalName = String(name || '').trim();
      if (!signalName) {
        return null;
      }
      if (netNodes.has(signalName)) {
        return netNodes.get(signalName) || null;
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

    const addPortEdge = (
      fromId: string,
      toId: string,
      signalRef: SignalRef | null,
      direction: string,
      kind = 'port'
    ): void => {
      if (!fromId || !toId || !signalRef) {
        return;
      }
      const edgeData: UnknownRecord = {
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
      const portRecord = asRecord(port);
      if (!portRecord || typeof portRecord.name !== 'string') {
        continue;
      }
      const signalRef = resolveNodeSignalRef(
        focusNode,
        lookup,
        portRecord.name,
        readWidth(portRecord.width, 1),
        liveSignalSet
      );
      const netId = ensureNet(portRecord.name, signalRef?.width || 1);
      if (!netId || !signalRef) {
        continue;
      }
      const direction = normalizeDirection(portRecord.direction || '?');
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

    if (showChildren) {
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

        const childRaw = childNode.rawRef || {};
        const childPorts = Array.isArray(childRaw.ports) ? childRaw.ports : [];
        for (const port of childPorts) {
          const portRecord = asRecord(port);
          if (!portRecord || typeof portRecord.name !== 'string') {
            continue;
          }
          const signalRef = resolveNodeSignalRef(
            focusNode,
            lookup,
            portRecord.name,
            readWidth(portRecord.width, 1),
            liveSignalSet
          );
          const netId = ensureNet(portRecord.name, signalRef?.width || 1);
          if (!netId || !signalRef) {
            continue;
          }
          const direction = normalizeDirection(portRecord.direction || '?');
          addPortEdge(netId, childCyId, signalRef, direction, 'child-port');
        }
      }
    }

    const memoryNodes = new Set<string>();
    const ensureMemoryNode = (name: unknown): string | null => {
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

    const addAssignEdges = (): void => {
      const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
      const maxAssigns = showChildren && focusNode.children.length > 0 ? 48 : 220;
      for (let idx = 0; idx < Math.min(assigns.length, maxAssigns); idx += 1) {
        const assign = asRecord(assigns[idx]);
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

        const sourceSignals = Array.from(collectExprSignalNames(assign?.expr, new Set<string>(), 14));
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
      const portRecord = asRecord(port);
      const memId = ensureMemoryNode(portRecord?.memory || `mem_wr_${idx}`);
      if (!memId) {
        continue;
      }
      for (const signalName of [
        summarizeExpr(portRecord?.addr),
        summarizeExpr(portRecord?.data),
        summarizeExpr(portRecord?.enable),
        portRecord?.clock
      ]) {
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
      const portRecord = asRecord(port);
      const memId = ensureMemoryNode(portRecord?.memory || `mem_rd_${idx}`);
      if (!memId) {
        continue;
      }
      for (const signalName of [
        summarizeExpr(portRecord?.addr),
        summarizeExpr(portRecord?.enable),
        portRecord?.clock
      ]) {
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
      const dataRef = resolveNodeSignalRef(focusNode, lookup, portRecord?.data, 1, liveSignalSet);
      const dataNetId = ensureNet(dataRef?.name || portRecord?.data, 1);
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
