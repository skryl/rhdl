import { toBigInt, formatValue } from '../../../core/lib/numeric_utils';
import { createSchematicElementBuilder } from '../lib/schematic_element_builder';
import { nodeDisplayPath, ellipsizeText } from '../lib/model_utils';
import {
  formatSourceBackedComponentCode,
  formatComponentCode,
  componentSignalLookup as buildComponentSignalLookup,
  resolveNodeSignalRef as resolveNodeSignalRefModel,
  collectExprSignalNames as collectExprSignalNamesModel,
  findComponentSchematicEntry as findComponentSchematicEntryModel,
  summarizeExpr as summarizeExprModel,
  collectConnectionRows as collectConnectionRowsModel
} from '../lib/inspector_model';
import type {
  ComponentModel,
  ComponentNode,
  ComponentSignal,
  ExplorerDomRefs,
  ExplorerRuntimeLike,
  ExplorerStateLike,
  SchematicBundleEntry,
  UnknownRecord
} from '../lib/types';

interface SignalRef {
  name: string;
  liveName: string | null;
  width: number;
  valueKey: string;
}

interface InspectorControllerOptions {
  dom: ExplorerDomRefs;
  state: ExplorerStateLike;
  runtime: ExplorerRuntimeLike;
  componentSignalPreviewLimit?: number;
  renderComponentInspectorView: (options: {
    dom: ExplorerDomRefs;
    node: ComponentNode | null;
    parseError: string;
    signalRows: Array<ComponentSignal & { value: unknown }>;
    hiddenSignalCount: number;
    codeTextRhdl: string;
    codeTextVerilog: string;
    title: string;
    metaText: string;
    signalMetaText: string;
    formatValue: typeof formatValue;
  }) => void;
  renderComponentLiveSignalsView: (
    dom: ExplorerDomRefs,
    data: UnknownRecord,
    formatter: typeof formatValue
  ) => void;
  renderComponentConnectionsView: (
    dom: ExplorerDomRefs,
    metaText: string,
    rows: Array<{ type: string; source: string; target: string; details: string }>,
    hiddenCount: number
  ) => void;
  clearComponentConnectionsView: (dom: ExplorerDomRefs, metaText: string) => void;
}

function requireFn(name: string, fn: unknown): void {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerInspectorController requires function: ${name}`);
  }
}

export function createExplorerInspectorController({
  dom,
  state,
  runtime,
  componentSignalPreviewLimit = 180,
  renderComponentInspectorView,
  renderComponentLiveSignalsView,
  renderComponentConnectionsView,
  clearComponentConnectionsView
}: InspectorControllerOptions) {
  if (!dom || !state || !runtime) {
    throw new Error('createExplorerInspectorController requires dom/state/runtime');
  }
  requireFn('renderComponentInspectorView', renderComponentInspectorView);
  requireFn('renderComponentLiveSignalsView', renderComponentLiveSignalsView);
  requireFn('renderComponentConnectionsView', renderComponentConnectionsView);
  requireFn('clearComponentConnectionsView', clearComponentConnectionsView);

  function componentSignalLookup(node: ComponentNode | null): Map<string, ComponentSignal> {
    return buildComponentSignalLookup(node);
  }

  function resolveNodeSignalRef(
    node: ComponentNode | null,
    lookup: Map<string, ComponentSignal>,
    signalName: unknown,
    width = 1,
    signalSet: Set<string> | null = null
  ): SignalRef | null {
    return resolveNodeSignalRefModel({
      state,
      runtime,
      node,
      lookup,
      signalName,
      width,
      signalSet
    });
  }

  function collectExprSignalNames(
    expr: unknown,
    out = new Set<string>(),
    maxSignals = 20
  ): Set<string> {
    return collectExprSignalNamesModel(expr, out, maxSignals);
  }

  function findComponentSchematicEntry(node: ComponentNode | null): SchematicBundleEntry | null {
    return findComponentSchematicEntryModel(state, node);
  }

  function summarizeExpr(expr: unknown): string {
    return summarizeExprModel(expr);
  }

  const schematicElementBuilder = createSchematicElementBuilder({
    state,
    runtime,
    componentSignalLookup,
    resolveNodeSignalRef,
    collectExprSignalNames,
    findComponentSchematicEntry,
    summarizeExpr,
    ellipsizeText
  });

  function signalLiveValue(signal: ComponentSignal): unknown {
    if (!runtime.sim || !signal?.liveName) {
      return null;
    }
    if (!runtime.irMeta?.widths?.has(signal.liveName)) {
      return null;
    }
    try {
      return runtime.sim.peek(signal.liveName);
    } catch {
      return null;
    }
  }

  function signalLiveValueByName(liveName: string): unknown {
    if (!runtime.sim || !liveName) {
      return null;
    }
    try {
      return runtime.sim.peek(liveName);
    } catch {
      return null;
    }
  }

  function renderComponentConnections(node: ComponentNode | null): void {
    if (!node) {
      clearComponentConnectionsView(dom, state.components.parseError || 'Select a component to inspect connections.');
      return;
    }

    const rows = collectConnectionRowsModel(state, node);
    const maxRows = 420;
    renderComponentConnectionsView(
      dom,
      `${rows.length} connections in ${nodeDisplayPath(node)}`,
      rows.slice(0, maxRows),
      Math.max(0, rows.length - maxRows)
    );
  }

  function renderComponentInspector(node: ComponentNode | null): void {
    const signalRows: Array<ComponentSignal & { value: unknown }> = node
      ? node.signals.slice(0, componentSignalPreviewLimit).map((signal) => ({
        ...signal,
        value: signalLiveValue(signal)
      }))
      : [];
    const hiddenSignalCount = node ? Math.max(0, node.signals.length - signalRows.length) : 0;

    const codeTextRhdl = node
      ? (formatSourceBackedComponentCode(state, node, 'rhdl', state.components.model as ComponentModel | null)
        || formatComponentCode(node))
      : '';
    const codeTextVerilog = node
      ? (formatSourceBackedComponentCode(state, node, 'verilog', state.components.model as ComponentModel | null)
        || formatComponentCode(node))
      : '';

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

  function renderComponentLiveSignals(node: ComponentNode | null): void {
    const highlight = state.components.graphHighlightedSignal;
    const limitedSignals = Array.isArray(node?.signals) ? node.signals.slice(0, 120) : [];
    const rows: Array<ComponentSignal & { matchesHighlight: boolean; value: unknown }> = [];
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
      extraSignals: Math.max(0, (node?.signals.length || 0) - limitedSignals.length)
    }, formatValue);
  }

  function createSchematicElements(
    model: ComponentModel,
    focusNode: ComponentNode,
    showChildren: boolean
  ): unknown[] {
    return schematicElementBuilder.createComponentSchematicElements(model, focusNode, showChildren);
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
    renderComponentConnections,
    createSchematicElements
  };
}
