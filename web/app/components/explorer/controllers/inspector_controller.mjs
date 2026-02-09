import { toBigInt, formatValue } from '../../../core/lib/numeric_utils.mjs';
import { createSchematicElementBuilder } from '../lib/schematic_element_builder.mjs';
import { nodeDisplayPath, ellipsizeText } from '../lib/model_utils.mjs';
import {
  formatSourceBackedComponentCode,
  formatComponentCode,
  componentSignalLookup as buildComponentSignalLookup,
  resolveNodeSignalRef as resolveNodeSignalRefModel,
  collectExprSignalNames as collectExprSignalNamesModel,
  findComponentSchematicEntry as findComponentSchematicEntryModel,
  summarizeExpr as summarizeExprModel,
  collectConnectionRows as collectConnectionRowsModel
} from '../lib/inspector_model.mjs';

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

  function componentSignalLookup(node) {
    return buildComponentSignalLookup(node);
  }

  function resolveNodeSignalRef(node, lookup, signalName, width = 1, signalSet = null) {
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

  function collectExprSignalNames(expr, out = new Set(), maxSignals = 20) {
    return collectExprSignalNamesModel(expr, out, maxSignals);
  }

  function findComponentSchematicEntry(node) {
    return findComponentSchematicEntryModel(state, node);
  }

  function summarizeExpr(expr) {
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

  function renderComponentConnections(node) {
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

  function renderComponentInspector(node) {
    const signalRows = node ? node.signals.slice(0, componentSignalPreviewLimit).map((signal) => ({
      ...signal,
      value: signalLiveValue(signal)
    })) : [];
    const hiddenSignalCount = node ? Math.max(0, node.signals.length - signalRows.length) : 0;
    const codeTextRhdl = node
      ? (formatSourceBackedComponentCode(state, node, 'rhdl', state.components.model) || formatComponentCode(node))
      : '';
    const codeTextVerilog = node
      ? (formatSourceBackedComponentCode(state, node, 'verilog', state.components.model) || formatComponentCode(node))
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

  function createSchematicElements(model, focusNode, showChildren) {
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
