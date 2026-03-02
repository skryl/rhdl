import {
  resolveLiveSignalName,
  deriveComponentName,
  summarizeIrEntry,
  summarizeIrNode
} from './model_utils';
import {
  asRecord,
  asStringArray,
  type ComponentModel,
  type ComponentNode,
  type ComponentSignal,
  type ExplorerRuntimeLike,
  type ExplorerStateLike,
  type SchematicBundleEntry,
  type SourceBundleEntry,
  type UnknownRecord
} from './types';

interface SignalRef {
  name: string;
  liveName: string | null;
  width: number;
  valueKey: string;
}

interface ConnectionRow {
  type: string;
  source: string;
  target: string;
  details: string;
}

interface ResolveSignalRefOptions {
  state: ExplorerStateLike;
  runtime: ExplorerRuntimeLike;
  node: ComponentNode | null;
  lookup: Map<string, ComponentSignal>;
  signalName: unknown;
  width?: number;
  signalSet?: Set<string> | null;
}

export function findComponentSourceEntry(
  state: ExplorerStateLike,
  node: ComponentNode | null,
  model: ComponentModel | null = null
): SourceBundleEntry | null {
  if (!node) {
    return null;
  }

  const byClass = state.components.sourceBundleByClass;
  const byModule = state.components.sourceBundleByModule;
  if (!(byClass instanceof Map) || !(byModule instanceof Map)) {
    return null;
  }

  const raw = node.rawRef;
  const className = raw && typeof raw.component_class === 'string' ? raw.component_class.trim() : '';
  if (className && byClass.has(className)) {
    return byClass.get(className) || null;
  }

  const moduleCandidates: string[] = [];
  if (raw) {
    for (const key of ['module_name', 'name', 'module', 'instance_name']) {
      const value = raw[key];
      if (typeof value === 'string' && value.trim()) {
        moduleCandidates.push(value.trim());
      }
    }
  }
  if (node.name.trim()) {
    moduleCandidates.push(node.name.trim());
  }

  for (const moduleName of moduleCandidates) {
    if (byModule.has(moduleName)) {
      return byModule.get(moduleName) || null;
    }
    const lower = moduleName.toLowerCase();
    if (byModule.has(lower)) {
      return byModule.get(lower) || null;
    }
  }

  const bundle = state.components.sourceBundle;
  if (bundle?.top) {
    if (!node.parentId || (model && node.id === model.rootId)) {
      return bundle.top;
    }
  }

  if (bundle && Array.isArray(bundle.components) && bundle.components.length === 1) {
    return bundle.components[0] || null;
  }

  return null;
}

export function normalizeComponentCodeView(view: unknown): 'rhdl' | 'verilog' {
  return view === 'verilog' ? 'verilog' : 'rhdl';
}

export function formatSourceBackedComponentCode(
  state: ExplorerStateLike,
  node: ComponentNode,
  view: 'rhdl' | 'verilog' | string = 'rhdl',
  model: ComponentModel | null = null
): string | null {
  const entry = findComponentSourceEntry(state, node, model);
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

  return null;
}

export function formatComponentCode(node: ComponentNode | null): string {
  if (!node) {
    return 'Select a component to view details.';
  }

  const sections: string[] = [];
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

export function componentSignalLookup(node: ComponentNode | null): Map<string, ComponentSignal> {
  const lookup = new Map<string, ComponentSignal>();
  if (!node) {
    return lookup;
  }

  for (const signal of node.signals) {
    if (signal.name) {
      lookup.set(signal.name, signal);
    }
    if (signal.fullName) {
      lookup.set(signal.fullName, signal);
    }
    if (signal.liveName) {
      lookup.set(signal.liveName, signal);
    }
  }

  return lookup;
}

export function resolveNodeSignalRef({
  state,
  runtime,
  node,
  lookup,
  signalName,
  width = 1,
  signalSet = null
}: ResolveSignalRefOptions): SignalRef | null {
  const localName = String(signalName || '').trim();
  if (!localName) {
    return null;
  }

  const signal = lookup.get(localName) || null;
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
    asStringArray(
      state.components.overrideMeta?.liveSignalNames
      || state.components.overrideMeta?.names
      || runtime.irMeta?.names
    )
  );
  const liveName = resolveLiveSignalName(localName, node?.pathTokens || [], fallbackSignalSet);

  return {
    name: localName,
    liveName: liveName || null,
    width: width || 1,
    valueKey: liveName || `${node?.path || 'top'}::${localName}`
  };
}

export function collectExprSignalNames(
  expr: unknown,
  out: Set<string> = new Set<string>(),
  maxSignals = 20
): Set<string> {
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

  const exprRecord = asRecord(expr);
  if (!exprRecord) {
    return out;
  }

  if (exprRecord.type === 'signal' && typeof exprRecord.name === 'string' && exprRecord.name.trim()) {
    out.add(exprRecord.name.trim());
    if (out.size >= maxSignals) {
      return out;
    }
  }

  for (const value of Object.values(exprRecord)) {
    collectExprSignalNames(value, out, maxSignals);
    if (out.size >= maxSignals) {
      break;
    }
  }

  return out;
}

export function findComponentSchematicEntry(
  state: ExplorerStateLike,
  node: ComponentNode | null
): SchematicBundleEntry | null {
  if (!node) {
    return null;
  }

  const byPath = state.components.schematicBundleByPath;
  if (!(byPath instanceof Map) || byPath.size === 0) {
    return null;
  }

  const path = String(node.path || 'top');
  const entry = byPath.get(path);
  return entry || null;
}

export function summarizeExpr(expr: unknown): string {
  if (expr == null) {
    return '-';
  }
  if (
    typeof expr === 'string'
    || typeof expr === 'number'
    || typeof expr === 'bigint'
    || typeof expr === 'boolean'
  ) {
    return String(expr);
  }
  if (Array.isArray(expr)) {
    const preview = expr.slice(0, 3).map((entry) => summarizeExpr(entry)).join(', ');
    return `[${preview}${expr.length > 3 ? ', ...' : ''}]`;
  }

  const exprRecord = asRecord(expr);
  if (!exprRecord) {
    return String(expr);
  }

  if (typeof exprRecord.name === 'string') {
    return exprRecord.name;
  }
  if (
    typeof exprRecord.op === 'string'
    && exprRecord.left !== undefined
    && exprRecord.right !== undefined
  ) {
    return `${summarizeExpr(exprRecord.left)} ${exprRecord.op} ${summarizeExpr(exprRecord.right)}`;
  }
  if (typeof exprRecord.op === 'string' && exprRecord.operand !== undefined) {
    return `${exprRecord.op} ${summarizeExpr(exprRecord.operand)}`;
  }
  if (exprRecord.value !== undefined && exprRecord.width !== undefined) {
    return `lit(${exprRecord.value}:${exprRecord.width})`;
  }
  if (exprRecord.selector !== undefined && exprRecord.cases !== undefined) {
    return `mux(${summarizeExpr(exprRecord.selector)})`;
  }
  if (exprRecord.kind !== undefined) {
    return String(exprRecord.kind);
  }
  return JSON.stringify(summarizeIrEntry(exprRecord));
}

function mapById(entries: unknown[]): Map<string, UnknownRecord> {
  const mapped = new Map<string, UnknownRecord>();
  for (const entry of entries) {
    const record = asRecord(entry);
    const id = record ? String(record.id || '').trim() : '';
    if (!id || !record) {
      continue;
    }
    mapped.set(id, record);
  }
  return mapped;
}

export function collectConnectionRows(
  state: ExplorerStateLike,
  node: ComponentNode | null
): ConnectionRow[] {
  const rows: ConnectionRow[] = [];
  if (!node) {
    return rows;
  }

  const schematicEntry = findComponentSchematicEntry(state, node);
  const schematic = asRecord(schematicEntry?.schematic);
  if (schematic) {
    const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
    const pins = Array.isArray(schematic.pins) ? schematic.pins : [];
    const nets = Array.isArray(schematic.nets) ? schematic.nets : [];
    const wires = Array.isArray(schematic.wires) ? schematic.wires : [];

    if (wires.length > 0) {
      const symbolById = mapById(symbols);
      const pinById = mapById(pins);
      const netById = mapById(nets);

      const pinLabel = (pinId: unknown): string => {
        const pin = pinById.get(String(pinId || '').trim());
        if (!pin) {
          return String(pinId || '?');
        }
        const symbol = symbolById.get(String(pin.symbol_id || '').trim());
        const symbolName = String(symbol?.label || symbol?.id || pin.symbol_id || '?');
        const pinName = String(pin.name || pin.signal || pin.id || '?');
        return `${symbolName}.${pinName}`;
      };

      for (const wire of wires) {
        const wireRecord = asRecord(wire);
        if (!wireRecord) {
          continue;
        }
        const fromPinId = String(wireRecord.from_pin_id || '').trim();
        const toPinId = String(wireRecord.to_pin_id || '').trim();
        if (!fromPinId || !toPinId) {
          continue;
        }

        const net = netById.get(String(wireRecord.net_id || '').trim());
        const netName = String(net?.name || wireRecord.signal || '?');
        const width = Number.parseInt(String(wireRecord.width || net?.width || ''), 10) || 1;
        const direction = String(wireRecord.direction || '?').toLowerCase();
        rows.push({
          type: String(wireRecord.kind || 'wire'),
          source: pinLabel(fromPinId),
          target: pinLabel(toPinId),
          details: `net=${netName} dir=${direction} w=${width}`
        });
      }
      return rows;
    }
  }

  const raw = node.rawRef;
  if (!raw) {
    return rows;
  }

  const instances = Array.isArray(raw.instances) ? raw.instances : [];
  for (const inst of instances) {
    const instanceRecord = asRecord(inst);
    if (!instanceRecord) {
      continue;
    }
    const instanceName = deriveComponentName(instanceRecord, 'instance');
    const connections = Array.isArray(instanceRecord.connections) ? instanceRecord.connections : [];
    for (const conn of connections) {
      const connectionRecord = asRecord(conn);
      if (!connectionRecord) {
        continue;
      }
      rows.push({
        type: 'port',
        source: `${instanceName}.${String(connectionRecord.port_name || connectionRecord.port || '?')}`,
        target: String(connectionRecord.signal || '?'),
        details: String(connectionRecord.direction || '?')
      });
    }
  }

  const children = Array.isArray(raw.children) ? raw.children : [];
  for (const child of children) {
    const childRecord = asRecord(child);
    if (!childRecord) {
      continue;
    }
    const instanceName = deriveComponentName(childRecord, 'child');
    const ports = Array.isArray(childRecord.ports) ? childRecord.ports : [];
    for (const port of ports) {
      const portRecord = asRecord(port);
      if (!portRecord || typeof portRecord.name !== 'string') {
        continue;
      }
      const direction = String(portRecord.direction || '?').toLowerCase();
      if (direction === 'out') {
        rows.push({
          type: 'child-port',
          source: `${instanceName}.${portRecord.name}`,
          target: portRecord.name,
          details: direction
        });
      } else {
        rows.push({
          type: 'child-port',
          source: portRecord.name,
          target: `${instanceName}.${portRecord.name}`,
          details: direction
        });
      }
    }
  }

  const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
  for (const assign of assigns) {
    const assignRecord = asRecord(assign);
    rows.push({
      type: 'wire',
      source: summarizeExpr(assignRecord?.expr),
      target: String(assignRecord?.target || '?'),
      details: 'assign'
    });
  }

  const writePorts = Array.isArray(raw.write_ports) ? raw.write_ports : [];
  for (const port of writePorts) {
    const portRecord = asRecord(port);
    rows.push({
      type: 'mem-wr',
      source: summarizeExpr(portRecord?.data),
      target: `${String(portRecord?.memory || '?')}[${summarizeExpr(portRecord?.addr)}]`,
      details: `clk=${String(portRecord?.clock || '?')} en=${summarizeExpr(portRecord?.enable)}`
    });
  }

  const syncReadPorts = Array.isArray(raw.sync_read_ports) ? raw.sync_read_ports : [];
  for (const port of syncReadPorts) {
    const portRecord = asRecord(port);
    rows.push({
      type: 'mem-rd',
      source: `${String(portRecord?.memory || '?')}[${summarizeExpr(portRecord?.addr)}]`,
      target: String(portRecord?.data || '?'),
      details: `clk=${String(portRecord?.clock || '?')} en=${summarizeExpr(portRecord?.enable)}`
    });
  }

  return rows;
}
