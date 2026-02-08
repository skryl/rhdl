import test from 'node:test';
import assert from 'node:assert/strict';
import { bindGraphInteractions } from '../../app/controllers/explorer_graph_interactions.mjs';

function createMockCy() {
  const handlers = [];
  return {
    handlers,
    on(event, selectorOrHandler, handler) {
      if (typeof handler === 'function') {
        handlers.push({ event, selector: selectorOrHandler, handler });
        return;
      }
      handlers.push({ event, selector: null, handler: selectorOrHandler });
    },
    emitTapNode(target) {
      for (const entry of handlers) {
        if (entry.event === 'tap' && entry.selector === 'node') {
          entry.handler({ target });
        }
      }
    },
    emitTapEdge(target) {
      for (const entry of handlers) {
        if (entry.event === 'tap' && entry.selector === 'edge') {
          entry.handler({ target });
        }
      }
    },
    emitTapCanvas() {
      for (const entry of handlers) {
        if (entry.event === 'tap' && entry.selector === null) {
          entry.handler({ target: this });
        }
      }
    }
  };
}

function createTarget(dataMap = {}) {
  return {
    data(key) {
      return dataMap[key];
    }
  };
}

function createState() {
  return {
    components: {
      selectedNodeId: null,
      graphLastTap: null,
      graphFocusId: null,
      graphShowChildren: false,
      graphHighlightedSignal: null
    }
  };
}

test('bindGraphInteractions highlights signal taps for net/pin and edges', () => {
  const cy = createMockCy();
  const state = createState();
  const model = { nodes: new Map() };
  let renders = 0;

  bindGraphInteractions({
    cy,
    state,
    model,
    renderComponentTree: () => {},
    renderComponentViews: () => {
      renders += 1;
    }
  });

  cy.emitTapNode(createTarget({ nodeRole: 'net', signalName: 'cpu.bus', liveName: '' }));
  assert.deepEqual(state.components.graphHighlightedSignal, { signalName: 'cpu.bus', liveName: null });

  cy.emitTapEdge(createTarget({ signalName: '', liveName: 'cpu.bus' }));
  assert.deepEqual(state.components.graphHighlightedSignal, { signalName: null, liveName: 'cpu.bus' });

  cy.emitTapCanvas();
  assert.equal(state.components.graphHighlightedSignal, null);
  assert.equal(renders, 3);
});

test('bindGraphInteractions selects components and dives on double tap', () => {
  const cy = createMockCy();
  const state = createState();
  const model = { nodes: new Map([['cpu', {}]]) };
  let treeRenders = 0;
  let viewRenders = 0;
  const timestamps = [1000, 1200];

  bindGraphInteractions({
    cy,
    state,
    model,
    renderComponentTree: () => {
      treeRenders += 1;
    },
    renderComponentViews: () => {
      viewRenders += 1;
    },
    now: () => timestamps.shift() || 1500
  });

  cy.emitTapNode(createTarget({ componentId: 'cpu', nodeRole: 'component' }));
  assert.equal(state.components.selectedNodeId, 'cpu');
  assert.equal(state.components.graphFocusId, null);
  assert.equal(state.components.graphShowChildren, false);

  cy.emitTapNode(createTarget({ componentId: 'cpu', nodeRole: 'component' }));
  assert.equal(state.components.graphFocusId, 'cpu');
  assert.equal(state.components.graphShowChildren, true);
  assert.equal(state.components.graphHighlightedSignal, null);

  assert.equal(treeRenders, 1);
  assert.equal(viewRenders, 2);
});

test('bindGraphInteractions validates required arguments', () => {
  assert.throws(
    () => bindGraphInteractions({ cy: null, state: {}, model: {}, renderComponentTree: () => {}, renderComponentViews: () => {} }),
    /requires cy, state, and model/
  );
  assert.throws(
    () => bindGraphInteractions({ cy: {}, state: {}, model: {}, renderComponentTree: null, renderComponentViews: () => {} }),
    /requires render callbacks/
  );
});

