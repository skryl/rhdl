import { toBigInt, formatValue } from '../lib/numeric_utils.mjs';
import {
  resolveLiveSignalName,
  nodeDisplayPath,
  deriveComponentName,
  summarizeIrEntry,
  summarizeIrNode
} from '../lib/model_utils.mjs';

export function createExplorerInspectorController({
  dom,
  state,
  runtime,
  componentSignalPreviewLimit = 180,
  renderComponentInspectorView,
  renderComponentLiveSignalsView,
  renderComponentConnectionsView,
  clearComponentConnectionsView
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createExplorerInspectorController requires dom/state/runtime');
  }
  if (typeof renderComponentInspectorView !== 'function') {
    throw new Error('createExplorerInspectorController requires function: renderComponentInspectorView');
  }
  if (typeof renderComponentLiveSignalsView !== 'function') {
    throw new Error('createExplorerInspectorController requires function: renderComponentLiveSignalsView');
  }
  if (typeof renderComponentConnectionsView !== 'function') {
    throw new Error('createExplorerInspectorController requires function: renderComponentConnectionsView');
  }
  if (typeof clearComponentConnectionsView !== 'function') {
    throw new Error('createExplorerInspectorController requires function: clearComponentConnectionsView');
  }

  function signalLiveValue(signal) {
    if (!runtime.sim || !signal?.liveName) {
      return null;
    }
    if (!runtime.irMeta?.widths?.has(signal.liveName)) {
      return null;
    }
    try {
      return runtime.sim.peek(signal.liveName);
    } catch (_err) {
      return null;
    }
  }

  function findComponentSourceEntry(node) {
    if (!node) {
      return null;
    }
    const byClass = state.components.sourceBundleByClass;
    const byModule = state.components.sourceBundleByModule;
    if (!(byClass instanceof Map) || !(byModule instanceof Map)) {
      return null;
    }

    const raw = node.rawRef && typeof node.rawRef === 'object' ? node.rawRef : null;
    const className = raw && typeof raw.component_class === 'string' ? raw.component_class.trim() : '';
    if (className && byClass.has(className)) {
      return byClass.get(className);
    }

    const moduleCandidates = [];
    if (raw) {
      for (const key of ['module_name', 'name', 'module', 'instance_name']) {
        const value = raw[key];
        if (typeof value === 'string' && value.trim()) {
          moduleCandidates.push(value.trim());
        }
      }
    }
    if (typeof node.name === 'string' && node.name.trim()) {
      moduleCandidates.push(node.name.trim());
    }
    for (const moduleName of moduleCandidates) {
      if (byModule.has(moduleName)) {
        return byModule.get(moduleName);
      }
      const lower = moduleName.toLowerCase();
      if (byModule.has(lower)) {
        return byModule.get(lower);
      }
    }

    const bundle = state.components.sourceBundle;
    if (bundle && bundle.top) {
      const model = state.components.model;
      if (!node.parentId || (model && node.id === model.rootId)) {
        return bundle.top;
      }
    }
    if (bundle && Array.isArray(bundle.components) && bundle.components.length === 1) {
      return bundle.components[0];
    }
    return null;
  }

  function normalizeComponentCodeView(view) {
    return view === 'verilog' ? 'verilog' : 'rhdl';
  }

  function formatSourceBackedComponentCode(node, view = 'rhdl') {
    const entry = findComponentSourceEntry(node);
    if (!entry) {
      return null;
    }

    const normalizedView = normalizeComponentCodeView(view);
    const componentClass = String(entry.component_class || '').trim();
    const moduleName = String(entry.module_name || '').trim();
    const sourcePath = String(entry.source_path || '').trim();
    const rhdlSource = typeof entry.rhdl_source === 'string' ? entry.rhdl_source.trim() : '';
    const verilogSource = typeof entry.verilog_source === 'string' ? entry.verilog_source.trim() : '';

    if (normalizedView === 'rhdl') {
      if (!rhdlSource) {
        if (!verilogSource) {
          return null;
        }
        const fallbackHeader = ['// RHDL Ruby source not available; showing Verilog'];
        if (moduleName) {
          fallbackHeader.push(`module=${moduleName}`);
        }
        return `${fallbackHeader.join(' | ')}\n${verilogSource}`;
      }
      const headerBits = ['// RHDL Ruby source'];
      if (componentClass) {
        headerBits.push(`class=${componentClass}`);
      }
      if (sourcePath) {
        headerBits.push(`path=${sourcePath}`);
      }
      return `${headerBits.join(' | ')}\n${rhdlSource}`;
    }

    if (verilogSource) {
      const headerBits = ['// Verilog source'];
      if (moduleName) {
        headerBits.push(`module=${moduleName}`);
      }
      return `${headerBits.join(' | ')}\n${verilogSource}`;
    }

    if (rhdlSource) {
      const fallbackHeader = ['// Verilog source not available; showing RHDL Ruby'];
      if (componentClass) {
        fallbackHeader.push(`class=${componentClass}`);
      }
      if (sourcePath) {
        fallbackHeader.push(`path=${sourcePath}`);
      }
      return `${fallbackHeader.join(' | ')}\n${rhdlSource}`;
    }

    if (!rhdlSource && !verilogSource) {
      return null;
    }
    return null;
  }

  function formatComponentCode(node) {
    if (!node) {
      return 'Select a component to view details.';
    }

    const sections = [];
    if (node.rawRef) {
      const summary = summarizeIrNode(node.rawRef);
      if (summary) {
        sections.push('// IR node summary');
        sections.push(JSON.stringify(summary, null, 2));
      }
    }

    if (node.signals.length > 0) {
      const maxRows = 240;
      sections.push('// Signals');
      const rows = node.signals.slice(0, maxRows).map((signal) => {
        const direction = signal.direction ? ` (${signal.direction})` : '';
        return `${signal.kind.padEnd(6)} ${signal.fullName.padEnd(48)} width=${String(signal.width).padStart(2)}${direction}`;
      });
      if (node.signals.length > maxRows) {
        rows.push(`... ${node.signals.length - maxRows} more signals`);
      }
      sections.push(rows.join('\n'));
    }

    if (sections.length === 0) {
      return 'No IR/code details available for this component.';
    }
    return sections.join('\n\n');
  }

  function signalLiveValueByName(liveName) {
    if (!runtime.sim || !liveName) {
      return null;
    }
    try {
      return runtime.sim.peek(liveName);
    } catch (_err) {
      return null;
    }
  }

  function componentSignalLookup(node) {
    const lookup = new Map();
    if (!node) {
      return lookup;
    }
    for (const signal of node.signals || []) {
      if (signal?.name) {
        lookup.set(String(signal.name), signal);
      }
      if (signal?.fullName) {
        lookup.set(String(signal.fullName), signal);
      }
      if (signal?.liveName) {
        lookup.set(String(signal.liveName), signal);
      }
    }
    return lookup;
  }

  function resolveNodeSignalRef(node, lookup, signalName, width = 1, signalSet = null) {
    const localName = String(signalName || '').trim();
    if (!localName) {
      return null;
    }

    const signal = lookup?.get(localName) || null;
    if (signal) {
      const liveName = signal.liveName || signal.fullName || null;
      return {
        name: localName,
        liveName,
        width: signal.width || width || 1,
        valueKey: liveName || `${node?.path || 'top'}::${localName}`
      };
    }

    const fallbackSignalSet = signalSet || new Set(
      state.components.overrideMeta?.liveSignalNames
      || state.components.overrideMeta?.names
      || runtime.irMeta?.names
      || []
    );
    const liveName = resolveLiveSignalName(localName, node?.pathTokens || [], fallbackSignalSet);
    return {
      name: localName,
      liveName: liveName || null,
      width: width || 1,
      valueKey: liveName || `${node?.path || 'top'}::${localName}`
    };
  }

  function collectExprSignalNames(expr, out = new Set(), maxSignals = 20) {
    if (out.size >= maxSignals || expr == null) {
      return out;
    }
    if (Array.isArray(expr)) {
      for (const entry of expr) {
        collectExprSignalNames(entry, out, maxSignals);
        if (out.size >= maxSignals) {
          break;
        }
      }
      return out;
    }
    if (typeof expr !== 'object') {
      return out;
    }

    if (expr.type === 'signal' && typeof expr.name === 'string' && expr.name.trim()) {
      out.add(expr.name.trim());
      if (out.size >= maxSignals) {
        return out;
      }
    }

    for (const value of Object.values(expr)) {
      collectExprSignalNames(value, out, maxSignals);
      if (out.size >= maxSignals) {
        break;
      }
    }
    return out;
  }

  function findComponentSchematicEntry(node) {
    if (!node) {
      return null;
    }
    const byPath = state.components.schematicBundleByPath;
    if (!(byPath instanceof Map) || byPath.size === 0) {
      return null;
    }
    const path = String(node.path || 'top');
    return byPath.get(path) || null;
  }

  function summarizeExpr(expr) {
    if (expr == null) {
      return '-';
    }
    if (typeof expr === 'string' || typeof expr === 'number' || typeof expr === 'bigint' || typeof expr === 'boolean') {
      return String(expr);
    }
    if (Array.isArray(expr)) {
      const preview = expr.slice(0, 3).map((entry) => summarizeExpr(entry)).join(', ');
      return `[${preview}${expr.length > 3 ? ', ...' : ''}]`;
    }
    if (typeof expr !== 'object') {
      return String(expr);
    }

    if (typeof expr.name === 'string') {
      return expr.name;
    }
    if (expr.op && expr.left !== undefined && expr.right !== undefined) {
      return `${summarizeExpr(expr.left)} ${expr.op} ${summarizeExpr(expr.right)}`;
    }
    if (expr.op && expr.operand !== undefined) {
      return `${expr.op} ${summarizeExpr(expr.operand)}`;
    }
    if (expr.value !== undefined && expr.width !== undefined) {
      return `lit(${expr.value}:${expr.width})`;
    }
    if (expr.selector !== undefined && expr.cases !== undefined) {
      return `mux(${summarizeExpr(expr.selector)})`;
    }
    if (expr.kind) {
      return String(expr.kind);
    }
    return JSON.stringify(summarizeIrEntry(expr));
  }

  function collectConnectionRows(node) {
    const rows = [];

    const schematicEntry = findComponentSchematicEntry(node);
    const schematic = schematicEntry?.schematic;
    if (schematic && typeof schematic === 'object') {
      const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
      const pins = Array.isArray(schematic.pins) ? schematic.pins : [];
      const nets = Array.isArray(schematic.nets) ? schematic.nets : [];
      const wires = Array.isArray(schematic.wires) ? schematic.wires : [];
      if (wires.length > 0) {
        const symbolById = new Map(symbols.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));
        const pinById = new Map(pins.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));
        const netById = new Map(nets.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));

        const pinLabel = (pinId) => {
          const pin = pinById.get(String(pinId || ''));
          if (!pin) {
            return String(pinId || '?');
          }
          const symbol = symbolById.get(String(pin.symbol_id || ''));
          const symbolName = String(symbol?.label || symbol?.id || pin.symbol_id || '?');
          const pinName = String(pin.name || pin.signal || pin.id || '?');
          return `${symbolName}.${pinName}`;
        };

        for (const wire of wires) {
          if (!wire || typeof wire !== 'object') {
            continue;
          }
          const fromPinId = String(wire.from_pin_id || '').trim();
          const toPinId = String(wire.to_pin_id || '').trim();
          if (!fromPinId || !toPinId) {
            continue;
          }
          const net = netById.get(String(wire.net_id || '').trim());
          const netName = String(net?.name || wire.signal || '?');
          const width = Number.parseInt(wire.width || net?.width, 10) || 1;
          const direction = String(wire.direction || '?').toLowerCase();
          rows.push({
            type: String(wire.kind || 'wire'),
            source: pinLabel(fromPinId),
            target: pinLabel(toPinId),
            details: `net=${netName} dir=${direction} w=${width}`
          });
        }
        return rows;
      }
    }

    const raw = node?.rawRef;
    if (!raw || typeof raw !== 'object') {
      return rows;
    }

    const instances = Array.isArray(raw.instances) ? raw.instances : [];
    for (const inst of instances) {
      const instanceName = deriveComponentName(inst, 'instance');
      const connections = Array.isArray(inst.connections) ? inst.connections : [];
      for (const conn of connections) {
        rows.push({
          type: 'port',
          source: `${instanceName}.${conn.port_name || conn.port || '?'}`,
          target: String(conn.signal || '?'),
          details: String(conn.direction || '?')
        });
      }
    }

    const children = Array.isArray(raw.children) ? raw.children : [];
    for (const child of children) {
      const instanceName = deriveComponentName(child, 'child');
      const ports = Array.isArray(child?.ports) ? child.ports : [];
      for (const port of ports) {
        if (!port || typeof port.name !== 'string') {
          continue;
        }
        const direction = String(port.direction || '?').toLowerCase();
        if (direction === 'out') {
          rows.push({
            type: 'child-port',
            source: `${instanceName}.${port.name}`,
            target: port.name,
            details: direction
          });
        } else {
          rows.push({
            type: 'child-port',
            source: port.name,
            target: `${instanceName}.${port.name}`,
            details: direction
          });
        }
      }
    }

    const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
    for (const assign of assigns) {
      rows.push({
        type: 'wire',
        source: summarizeExpr(assign?.expr),
        target: String(assign?.target || '?'),
        details: 'assign'
      });
    }

    const writePorts = Array.isArray(raw.write_ports) ? raw.write_ports : [];
    for (const port of writePorts) {
      rows.push({
        type: 'mem-wr',
        source: summarizeExpr(port?.data),
        target: `${port?.memory || '?'}[${summarizeExpr(port?.addr)}]`,
        details: `clk=${port?.clock || '?'} en=${summarizeExpr(port?.enable)}`
      });
    }

    const syncReadPorts = Array.isArray(raw.sync_read_ports) ? raw.sync_read_ports : [];
    for (const port of syncReadPorts) {
      rows.push({
        type: 'mem-rd',
        source: `${port?.memory || '?'}[${summarizeExpr(port?.addr)}]`,
        target: String(port?.data || '?'),
        details: `clk=${port?.clock || '?'} en=${summarizeExpr(port?.enable)}`
      });
    }

    return rows;
  }

  function renderComponentConnections(node) {
    if (!node) {
      clearComponentConnectionsView(dom, state.components.parseError || 'Select a component to inspect connections.');
      return;
    }

    const rows = collectConnectionRows(node);
    const maxRows = 420;
    renderComponentConnectionsView(
      dom,
      `${rows.length} connections in ${nodeDisplayPath(node)}`,
      rows.slice(0, maxRows),
      Math.max(0, rows.length - maxRows)
    );
  }

  function renderComponentInspector(node) {
    const signalRows = node ? node.signals.slice(0, componentSignalPreviewLimit).map((signal) => ({
      ...signal,
      value: signalLiveValue(signal)
    })) : [];
    const hiddenSignalCount = node ? Math.max(0, node.signals.length - signalRows.length) : 0;
    const codeTextRhdl = node ? (formatSourceBackedComponentCode(node, 'rhdl') || formatComponentCode(node)) : '';
    const codeTextVerilog = node ? (formatSourceBackedComponentCode(node, 'verilog') || formatComponentCode(node)) : '';
    renderComponentInspectorView({
      dom,
      node,
      parseError: state.components.parseError,
      signalRows,
      hiddenSignalCount,
      codeTextRhdl,
      codeTextVerilog,
      title: node ? nodeDisplayPath(node) : 'Component Details',
      metaText: node ? `kind=${node.kind} | children=${node.children.length} | signals=${node.signals.length}` : '',
      signalMetaText: node ? `showing ${signalRows.length}/${node.signals.length} signals` : '',
      formatValue
    });
  }

  function renderComponentLiveSignals(node) {
    const highlight = state.components.graphHighlightedSignal;
    const limitedSignals = Array.isArray(node?.signals) ? node.signals.slice(0, 120) : [];
    const rows = [];
    let highlightedRows = 0;

    for (const signal of limitedSignals) {
      const matchesHighlight = !!highlight && (
        (!!highlight.liveName && (signal.liveName === highlight.liveName || signal.fullName === highlight.liveName))
        || (!!highlight.signalName && (signal.name === highlight.signalName || signal.fullName === highlight.signalName))
      );
      if (matchesHighlight) {
        highlightedRows += 1;
      }

      rows.push({
        ...signal,
        matchesHighlight,
        value: signalLiveValue(signal)
      });
    }

    renderComponentLiveSignalsView(dom, {
      signals: rows,
      highlight,
      highlightedRows,
      highlightLabel: node ? `Highlighted wire not in ${node.name}` : '',
      extraSignals: Math.max(0, (node?.signals?.length || 0) - limitedSignals.length)
    }, formatValue);
  }

  return {
    signalLiveValue,
    signalLiveValueByName,
    componentSignalLookup,
    resolveNodeSignalRef,
    collectExprSignalNames,
    findComponentSchematicEntry,
    summarizeExpr,
    renderComponentInspector,
    renderComponentLiveSignals,
    renderComponentConnections
  };
}
