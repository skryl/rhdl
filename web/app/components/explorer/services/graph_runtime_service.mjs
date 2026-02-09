import { toBigInt } from '../../../core/lib/numeric_utils.mjs';
import { nodeDisplayPath } from '../lib/model_utils.mjs';
import { updateGraphActivity } from '../lib/graph_activity.mjs';
import { createSchematicPalette, createSchematicStyle } from '../controllers/graph/theme.mjs';
import { runElkPortLayout } from '../controllers/graph/layout_elk.mjs';
import { bindGraphInteractions } from '../controllers/graph/interactions.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphRuntimeService requires function: ${name}`);
  }
}

export function createExplorerGraphRuntimeService({
  dom,
  state,
  currentComponentGraphFocusNode,
  renderComponentTree,
  renderComponentViews,
  createSchematicElements,
  signalLiveValueByName
} = {}) {
  if (!dom || !state) {
    throw new Error('createExplorerGraphRuntimeService requires dom/state');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('createSchematicElements', createSchematicElements);
  requireFn('signalLiveValueByName', signalLiveValueByName);

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
    const graphKey =
      `${state.components.sourceKey}:schematic:${state.theme}:` +
      `${schematicKey}:${focusNode.id}:${showChildren ? 1 : 0}:` +
      `${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;
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
    const schematicElements = createSchematicElements(model, focusNode, showChildren);
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

  function renderComponentVisual({ node, model, rerender }) {
    if (!dom.componentVisual) {
      return { ok: false, reason: 'missing-container' };
    }
    if (!node || !model) {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Select a component to visualize.';
      return { ok: false, reason: 'missing-node' };
    }
    if (typeof window.cytoscape !== 'function') {
      destroyComponentGraph();
      dom.componentVisual.textContent = 'Cytoscape not available.';
      return { ok: false, reason: 'missing-cytoscape' };
    }

    const cy = ensureComponentGraph(model);
    if (!cy) {
      if (state.components.graphLayoutEngine === 'missing') {
        dom.componentVisual.textContent = 'ELK layout engine unavailable.';
      } else {
        dom.componentVisual.textContent = 'Unable to render component schematic.';
      }
      return { ok: false, reason: 'graph-unavailable' };
    }

    if (dom.componentVisual.clientWidth < 20 || dom.componentVisual.clientHeight < 20) {
      requestAnimationFrame(() => {
        if (state.activeTab === 'componentGraphTab') {
          rerender();
        }
      });
      return { ok: false, reason: 'small-container' };
    }

    const focusNode = currentComponentGraphFocusNode();
    const findGraphNodeByComponentId = (componentId) => {
      if (!componentId) {
        return null;
      }
      const matches = cy
        .nodes('.schem-component')
        .filter((entry) => String(entry.data('componentId') || '') === String(componentId));
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
        cy.animate(
          {
            center: {
              eles: selectedNode
            }
          },
          {
            duration: 180
          }
        );
      }
    } else {
      cy.resize();
    }

    updateGraphActivity({
      cy,
      state,
      signalLiveValueByName,
      toBigInt
    });

    return { ok: true, cy };
  }

  function describeComponentGraphPanel({ selectedNode, focusNode }) {
    if (!selectedNode || !focusNode) {
      return {
        title: 'Component Schematic',
        meta: state.components.parseError || 'Load IR to inspect component connectivity.',
        focusPath: 'Focus: top',
        topDisabled: true,
        upDisabled: true
      };
    }

    const mode = state.components.graphShowChildren ? 'schematic view' : 'symbol view';
    const layout = state.components.graphLayoutEngine || 'none';
    const elk = state.components.graphElkAvailable ? 'ready' : 'missing';
    const model = state.components.model;
    return {
      title: nodeDisplayPath(focusNode),
      meta:
        `selected=${nodeDisplayPath(selectedNode)} | focus=${nodeDisplayPath(focusNode)}` +
        ` | ${mode} | layout=${layout} | elk=${elk} | dbl-click component to dive`,
      focusPath: `Focus: ${nodeDisplayPath(focusNode)}`,
      topDisabled: !model || focusNode.id === model.rootId,
      upDisabled: !focusNode.parentId
    };
  }

  return {
    destroyComponentGraph,
    renderComponentVisual,
    describeComponentGraphPanel
  };
}
