import { toBigInt } from '../lib/numeric_utils.mjs';
import {
  nodeDisplayPath,
  ellipsizeText
} from '../lib/model_utils.mjs';
import { createSchematicElementBuilder } from './explorer_schematic_builder.mjs';
import { createSchematicPalette, createSchematicStyle } from './explorer_graph_theme.mjs';
import { runElkPortLayout } from './explorer_graph_layout_elk.mjs';
import { bindGraphInteractions } from './explorer_graph_interactions.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphController requires function: ${name}`);
  }
}

export function createExplorerGraphController({
  dom,
  state,
  runtime,
  currentComponentGraphFocusNode,
  currentSelectedComponentNode,
  renderComponentTree,
  renderComponentViews,
  signalLiveValueByName,
  componentSignalLookup,
  resolveNodeSignalRef,
  collectExprSignalNames,
  findComponentSchematicEntry,
  summarizeExpr,
  renderComponentLiveSignals,
  renderComponentConnections
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createExplorerGraphController requires dom/state/runtime');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('currentSelectedComponentNode', currentSelectedComponentNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('signalLiveValueByName', signalLiveValueByName);
  requireFn('componentSignalLookup', componentSignalLookup);
  requireFn('resolveNodeSignalRef', resolveNodeSignalRef);
  requireFn('collectExprSignalNames', collectExprSignalNames);
  requireFn('findComponentSchematicEntry', findComponentSchematicEntry);
  requireFn('summarizeExpr', summarizeExpr);
  requireFn('renderComponentLiveSignals', renderComponentLiveSignals);
  requireFn('renderComponentConnections', renderComponentConnections);

  const schematicBuilder = createSchematicElementBuilder({
    state,
    runtime,
    componentSignalLookup,
    resolveNodeSignalRef,
    collectExprSignalNames,
    findComponentSchematicEntry,
    summarizeExpr,
    ellipsizeText
  });

  function destroyComponentGraph() {
    if (state.components.graph && typeof state.components.graph.destroy === 'function') {
      state.components.graph.destroy();
    }
    state.components.graph = null;
    state.components.graphKey = '';
    state.components.graphSelectedId = null;
    state.components.graphLastTap = null;
    state.components.graphLayoutEngine = 'none';
    state.components.graphElkAvailable = false;
  }

  function updateComponentGraphActivity(cy) {
    if (!cy) {
      return;
    }
    const nextValues = new Map();
    const highlight = state.components.graphHighlightedSignal;

    cy.batch(() => {
      cy.nodes('.schem-net, .schem-pin').forEach((node) => {
        const valueKey = String(node.data('valueKey') || '');
        const liveName = String(node.data('liveName') || '');
        const signalName = String(node.data('signalName') || '');
        if (!valueKey) {
          return;
        }
        const value = liveName ? signalLiveValueByName(liveName) : null;
        const valueText = value == null ? '' : toBigInt(value).toString();
        const previous = state.components.graphLiveValues.get(valueKey);
        const toggled = previous !== undefined && previous !== valueText;
        const active = valueText !== '' && valueText !== '0';
        const selected = !!highlight && (
          (!!highlight.liveName && liveName === highlight.liveName)
          || (!!highlight.signalName && signalName === highlight.signalName)
        );

        if (node.hasClass('schem-net')) {
          node.toggleClass('net-active', active);
          node.toggleClass('net-toggled', toggled);
          node.toggleClass('net-selected', selected);
        }
        if (node.hasClass('schem-pin')) {
          node.toggleClass('pin-active', active);
          node.toggleClass('pin-toggled', toggled);
          node.toggleClass('pin-selected', selected);
        }
        nextValues.set(valueKey, valueText);
      });

      cy.edges('.schem-wire').forEach((edge) => {
        const valueKey = String(edge.data('valueKey') || '');
        const signalName = String(edge.data('signalName') || '');
        const liveName = String(edge.data('liveName') || '');
        const valueText = valueKey ? (nextValues.get(valueKey) || '') : '';
        const previous = valueKey ? state.components.graphLiveValues.get(valueKey) : undefined;
        const toggled = valueKey && previous !== undefined && previous !== valueText;
        const active = valueText !== '' && valueText !== '0';

        const highlighted = !!highlight && (
          (!!highlight.liveName && liveName === highlight.liveName)
          || (!!highlight.signalName && signalName === highlight.signalName)
        );

        edge.toggleClass('wire-active', active);
        edge.toggleClass('wire-toggled', !!toggled);
        edge.toggleClass('wire-selected', highlighted);
      });
    });

    state.components.graphLiveValues = nextValues;
  }

  function ensureComponentGraph(model) {
    if (!dom.componentVisual || !model) {
      return null;
    }
    if (typeof window.cytoscape !== 'function') {
      return null;
    }

    const focusNode = currentComponentGraphFocusNode();
    if (!focusNode) {
      return null;
    }
    const showChildren = !!state.components.graphShowChildren;
    const schematicKey = state.components.schematicBundle
      ? (state.components.schematicBundle.generated_at || state.components.schematicBundle.runner || 'schem')
      : 'none';
    const elkAvailable = typeof window.ELK === 'function';
    state.components.graphElkAvailable = elkAvailable;
    const graphKey = `${state.components.sourceKey}:schematic:${state.theme}:${schematicKey}:${focusNode.id}:${showChildren ? 1 : 0}:${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;
    if (!elkAvailable) {
      state.components.graphLayoutEngine = 'missing';
      return null;
    }
    if (state.components.graph && state.components.graphKey === graphKey) {
      return state.components.graph;
    }

    destroyComponentGraph();
    dom.componentVisual.innerHTML = '';

    const palette = createSchematicPalette(state.theme);
    const schematicElements = schematicBuilder.createComponentSchematicElements(model, focusNode, showChildren);
    const cy = window.cytoscape({
      container: dom.componentVisual,
      elements: schematicElements,
      style: createSchematicStyle(palette),
      layout: {
        name: 'preset',
        fit: false
      },
      wheelSensitivity: 0.2,
      autoungrabify: true,
      boxSelectionEnabled: false
    });

    state.components.graphLayoutEngine = 'elk';
    runElkPortLayout({ cy, state }).catch((_err) => {
      state.components.graphLayoutEngine = 'error';
    });

    bindGraphInteractions({
      cy,
      state,
      model,
      renderComponentTree,
      renderComponentViews
    });

    state.components.graph = cy;
    state.components.graphKey = graphKey;
    state.components.graphSelectedId = null;
    return cy;
  }

  function renderComponentVisual(node) {
    if (!dom.componentVisual) {
      return;
    }
    if (!node || !state.components.model) {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Select a component to visualize.';
      return;
    }
    if (typeof window.cytoscape !== 'function') {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Cytoscape not available.';
      return;
    }

    const cy = ensureComponentGraph(state.components.model);
    if (!cy) {
      if (state.components.graphLayoutEngine === 'missing') {
        dom.componentVisual.textContent = 'ELK layout engine unavailable.';
      } else {
        dom.componentVisual.textContent = 'Unable to render component schematic.';
      }
      return;
    }

    if (dom.componentVisual.clientWidth < 20 || dom.componentVisual.clientHeight < 20) {
      requestAnimationFrame(() => {
        if (state.activeTab === 'componentGraphTab') {
          renderComponentGraphPanel();
        }
      });
      return;
    }

    const focusNode = currentComponentGraphFocusNode();
    const findGraphNodeByComponentId = (componentId) => {
      if (!componentId) {
        return null;
      }
      const matches = cy.nodes('.schem-component').filter((entry) => String(entry.data('componentId') || '') === String(componentId));
      return matches && matches.length > 0 ? matches[0] : null;
    };
    const selectedComponentId = (() => {
      if (!node) {
        return focusNode?.id || null;
      }
      const selected = findGraphNodeByComponentId(node.id);
      if (selected) {
        return node.id;
      }
      return focusNode?.id || node.id;
    })();
    const selectedNode = selectedComponentId ? findGraphNodeByComponentId(selectedComponentId) : null;
    const selectedCyId = selectedNode ? selectedNode.id() : null;

    cy.batch(() => {
      cy.nodes('.schem-component').removeClass('selected');
      if (selectedNode) {
        selectedNode.addClass('selected');
      }
    });

    if (state.components.graphSelectedId !== selectedCyId) {
      state.components.graphSelectedId = selectedCyId;
      if (selectedNode) {
        cy.animate({
          center: {
            eles: selectedNode
          }
        }, {
          duration: 180
        });
      }
    } else {
      cy.resize();
    }

    updateComponentGraphActivity(cy);
  }

  function renderComponentGraphPanel() {
    const selectedNode = currentSelectedComponentNode();
    const focusNode = currentComponentGraphFocusNode();
    if (!selectedNode || !focusNode) {
      if (dom.componentGraphTitle) {
        dom.componentGraphTitle.textContent = 'Component Schematic';
      }
      if (dom.componentGraphMeta) {
        dom.componentGraphMeta.textContent = state.components.parseError || 'Load IR to inspect component connectivity.';
      }
      if (dom.componentGraphFocusPath) {
        dom.componentGraphFocusPath.textContent = 'Focus: top';
      }
      if (dom.componentGraphTopBtn) {
        dom.componentGraphTopBtn.disabled = true;
      }
      if (dom.componentGraphUpBtn) {
        dom.componentGraphUpBtn.disabled = true;
      }
      renderComponentVisual(null);
      renderComponentLiveSignals(null);
      renderComponentConnections(null);
      return;
    }

    const activeNode = focusNode;

    if (dom.componentGraphTitle) {
      dom.componentGraphTitle.textContent = nodeDisplayPath(activeNode);
    }
    if (dom.componentGraphMeta) {
      const mode = state.components.graphShowChildren ? 'schematic view' : 'symbol view';
      const layout = state.components.graphLayoutEngine || 'none';
      const elk = state.components.graphElkAvailable ? 'ready' : 'missing';
      dom.componentGraphMeta.textContent = `selected=${nodeDisplayPath(selectedNode)} | focus=${nodeDisplayPath(focusNode)} | ${mode} | layout=${layout} | elk=${elk} | dbl-click component to dive`;
    }
    if (dom.componentGraphFocusPath) {
      dom.componentGraphFocusPath.textContent = `Focus: ${nodeDisplayPath(focusNode)}`;
    }
    if (dom.componentGraphTopBtn) {
      const model = state.components.model;
      dom.componentGraphTopBtn.disabled = !model || focusNode.id === model.rootId;
    }
    if (dom.componentGraphUpBtn) {
      dom.componentGraphUpBtn.disabled = !focusNode.parentId;
    }
    renderComponentVisual(selectedNode);
    renderComponentLiveSignals(activeNode);
    renderComponentConnections(focusNode);
  }

  return {
    destroyComponentGraph,
    renderComponentGraphPanel
  };
}
