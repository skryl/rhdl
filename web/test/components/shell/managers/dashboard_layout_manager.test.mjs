import test from 'node:test';
import assert from 'node:assert/strict';

import { createDashboardLayoutManager } from '../../../../app/components/shell/managers/dashboard_layout_manager.mjs';

function makeState() {
  return {
    sidebarCollapsed: false,
    dashboard: {
      rootElements: new Map(),
      layouts: {},
      draggingItemId: 'dragging',
      draggingRootKey: 'root',
      dropTargetItemId: 'drop',
      dropPosition: 'left',
      resizeBound: false,
      resizeTeardown: null,
      panelTeardowns: new Map(),
      resizing: {
        active: true,
        rootKey: 'r',
        rowSignature: 'sig',
        startY: 100,
        startHeight: 140
      }
    }
  };
}

function commonOptions(overrides = {}) {
  const storage = {
    getItem() {
      return '{"controls":{"order":[],"spans":{},"rowHeights":{"a":200}}}';
    },
    setItem() {}
  };

  return {
    state: makeState(),
    documentRef: {
      querySelector() {
        return null;
      },
      querySelectorAll() {
        return [];
      },
      createElement() {
        return {};
      }
    },
    windowRef: {
      requestAnimationFrame(cb) {
        cb();
        return 1;
      },
      dispatchEvent() {}
    },
    storage,
    rootConfigs: [],
    parseDashboardLayouts: (raw) => {
      if (!raw) {
        return {};
      }
      return JSON.parse(raw);
    },
    serializeDashboardLayouts: (value) => JSON.stringify(value || {}),
    withDashboardRowHeight: (layout, signature, height, min) => ({
      ...(layout || {}),
      rowHeights: {
        ...((layout && layout.rowHeights) || {}),
        [signature]: Math.max(min, Number(height) || 0)
      }
    }),
    normalizeDashboardSpan: (value, fallback = 'full') => (value === 'half' ? 'half' : fallback),
    safeSlugToken: (value) => String(value || '').toLowerCase(),
    dashboardRowSignature: () => 'sig',
    dashboardDropPosition: () => 'left',
    bindDashboardResizeEvents: () => () => {},
    bindDashboardPanelEvents: () => () => {},
    ...overrides
  };
}

test('dashboard layout manager initializes and disposes with empty roots', () => {
  let resizeBindingCount = 0;
  let resizeTeardownCount = 0;

  const options = commonOptions({
    bindDashboardResizeEvents: () => {
      resizeBindingCount += 1;
      return () => {
        resizeTeardownCount += 1;
      };
    }
  });

  const manager = createDashboardLayoutManager(options);
  manager.initialize();

  assert.equal(resizeBindingCount, 1);
  assert.equal(options.state.dashboard.resizeBound, true);
  assert.equal(options.state.dashboard.layouts.controls.rowHeights.a, 200);

  manager.refreshAllRowSizing();

  manager.dispose();
  assert.equal(resizeTeardownCount, 1);
  assert.equal(options.state.dashboard.resizeBound, false);
  assert.equal(options.state.dashboard.draggingItemId, '');
  assert.equal(options.state.dashboard.draggingRootKey, '');
  assert.equal(options.state.dashboard.resizing.active, false);
});

test('dashboard layout manager validates required options', () => {
  const options = commonOptions();
  delete options.parseDashboardLayouts;
  assert.throws(
    () => createDashboardLayoutManager(options),
    /requires parseDashboardLayouts/
  );
});
