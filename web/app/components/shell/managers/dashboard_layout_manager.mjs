import {
  normalizeDashboardPanelSpans,
  dashboardRowsFromPanels,
  snapshotDashboardPanelLayout,
  applyDashboardDropSpanPolicy
} from '../lib/dashboard_layout_model.mjs';

export const DASHBOARD_LAYOUT_KEY = 'rhdl.ir.web.dashboard.layout.v1';
export const DASHBOARD_DROP_POSITIONS = new Set(['left', 'right', 'above', 'below']);
export const DASHBOARD_MIN_ROW_HEIGHT = 140;
export const DASHBOARD_ROOT_CONFIGS = [
  {
    key: 'controls',
    selector: '#controlsPanel',
    panelSelector: ':scope > section',
    flattenPanels: false,
    staticSelectors: [],
    cleanupSelectors: [],
    wrapControls: true
  },
  {
    key: 'ioTab',
    selector: '#ioTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.io-layout']
  },
  {
    key: 'vcdTab',
    selector: '#vcdTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: ['#canvasWrap'],
    cleanupSelectors: ['.vcd-control-grid']
  },
  {
    key: 'memoryTab',
    selector: '#memoryTab',
    panelSelector: ':scope > .subpanel',
    flattenPanels: false,
    staticSelectors: [],
    cleanupSelectors: []
  },
  {
    key: 'componentTab',
    selector: '#componentTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.component-layout', '.component-left', '.component-right']
  },
  {
    key: 'componentGraphTab',
    selector: '#componentGraphTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.component-graph-layout']
  }
];

function noOp() {}

function resetResizingState(state) {
  state.dashboard.resizing.active = false;
  state.dashboard.resizing.rootKey = '';
  state.dashboard.resizing.rowSignature = '';
}

function isHtmlElement(value) {
  return typeof HTMLElement !== 'undefined' && value instanceof HTMLElement;
}

export function createDashboardLayoutManager(options) {
  const {
    state,
    documentRef = globalThis.document,
    windowRef = globalThis.window,
    storage = globalThis.localStorage,
    layoutStorageKey = DASHBOARD_LAYOUT_KEY,
    minRowHeight = DASHBOARD_MIN_ROW_HEIGHT,
    rootConfigs = DASHBOARD_ROOT_CONFIGS,
    parseDashboardLayouts,
    serializeDashboardLayouts,
    withDashboardRowHeight,
    normalizeDashboardSpan,
    safeSlugToken,
    dashboardRowSignature,
    dashboardDropPosition,
    bindDashboardResizeEvents,
    bindDashboardPanelEvents,
    isComponentTabActive = () => false,
    refreshActiveComponentTab = noOp,
    refreshMemoryView = noOp,
    getActiveTab = () => ''
  } = options || {};

  if (!state || !state.dashboard) {
    throw new Error('createDashboardLayoutManager requires state.dashboard');
  }
  if (typeof parseDashboardLayouts !== 'function') {
    throw new Error('createDashboardLayoutManager requires parseDashboardLayouts');
  }
  if (typeof serializeDashboardLayouts !== 'function') {
    throw new Error('createDashboardLayoutManager requires serializeDashboardLayouts');
  }
  if (typeof withDashboardRowHeight !== 'function') {
    throw new Error('createDashboardLayoutManager requires withDashboardRowHeight');
  }
  if (typeof normalizeDashboardSpan !== 'function') {
    throw new Error('createDashboardLayoutManager requires normalizeDashboardSpan');
  }
  if (typeof safeSlugToken !== 'function') {
    throw new Error('createDashboardLayoutManager requires safeSlugToken');
  }
  if (typeof dashboardRowSignature !== 'function') {
    throw new Error('createDashboardLayoutManager requires dashboardRowSignature');
  }
  if (typeof dashboardDropPosition !== 'function') {
    throw new Error('createDashboardLayoutManager requires dashboardDropPosition');
  }
  if (typeof bindDashboardResizeEvents !== 'function') {
    throw new Error('createDashboardLayoutManager requires bindDashboardResizeEvents');
  }
  if (typeof bindDashboardPanelEvents !== 'function') {
    throw new Error('createDashboardLayoutManager requires bindDashboardPanelEvents');
  }

  const requestFrame = (typeof windowRef?.requestAnimationFrame === 'function')
    ? windowRef.requestAnimationFrame.bind(windowRef)
    : ((cb) => setTimeout(cb, 0));

  const dashboard = state.dashboard;

  function readDashboardLayouts() {
    try {
      const raw = storage?.getItem?.(layoutStorageKey) ?? null;
      return parseDashboardLayouts(raw);
    } catch (_err) {
      return {};
    }
  }

  function writeDashboardLayouts() {
    try {
      storage?.setItem?.(layoutStorageKey, serializeDashboardLayouts(dashboard.layouts || {}));
    } catch (_err) {
      // Ignore storage failures.
    }
  }

  function dashboardRootPanels(root) {
    return Array.from(root.children).filter((child) => isHtmlElement(child) && child.classList.contains('dashboard-panel'));
  }

  function panelHeaderTitle(panel) {
    const raw = String(panel.dataset.collapseTitle || '').trim();
    if (raw) {
      return raw;
    }
    const heading = panel.querySelector(':scope > .panel-header-row > .panel-header-title, :scope > h1, :scope > h2, :scope > h3');
    return String(heading?.textContent || '').trim() || 'Panel';
  }

  function defaultDashboardSpan(rootKey, panel) {
    void rootKey;
    void panel;
    return 'full';
  }

  function normalizeDashboardSpansForRoot(root) {
    if (!isHtmlElement(root)) {
      return;
    }
    normalizeDashboardPanelSpans(dashboardRootPanels(root), normalizeDashboardSpan, 'full');
  }

  function dashboardRowsForRoot(root) {
    return dashboardRowsFromPanels(dashboardRootPanels(root), normalizeDashboardSpan, 'full');
  }

  function dashboardLayoutRowHeights(rootKey) {
    const layout = dashboard.layouts?.[rootKey];
    if (!layout || typeof layout !== 'object') {
      return {};
    }
    if (!layout.rowHeights || typeof layout.rowHeights !== 'object') {
      return {};
    }
    return layout.rowHeights;
  }

  function clearDashboardRowSizing(root) {
    if (!isHtmlElement(root)) {
      return;
    }
    const handles = Array.from(root.querySelectorAll(':scope > .dashboard-row-resize-handle'));
    for (const handle of handles) {
      handle.remove();
    }
    for (const panel of dashboardRootPanels(root)) {
      panel.classList.remove('dashboard-row-sized');
      panel.style.removeProperty('--dashboard-row-height');
    }
  }

  function isDashboardRootVisible(rootKey, root) {
    if (!isHtmlElement(root)) {
      return false;
    }
    if (rootKey === 'controls') {
      return !state.sidebarCollapsed && root.offsetParent !== null;
    }
    const tabPanel = root.classList.contains('tab-panel') ? root : root.closest('.tab-panel');
    if (!isHtmlElement(tabPanel)) {
      return root.offsetParent !== null;
    }
    return tabPanel.classList.contains('active');
  }

  function refreshRowSizing(rootKey) {
    const root = dashboard.rootElements.get(rootKey);
    if (!isHtmlElement(root)) {
      return;
    }

    normalizeDashboardSpansForRoot(root);
    clearDashboardRowSizing(root);

    const rows = dashboardRowsForRoot(root);
    const rowHeights = dashboardLayoutRowHeights(rootKey);
    for (const rowPanels of rows) {
      const signature = dashboardRowSignature(rowPanels);
      if (!signature) {
        continue;
      }
      const savedHeight = Number(rowHeights[signature]);
      if (!Number.isFinite(savedHeight) || savedHeight < minRowHeight) {
        continue;
      }
      for (const panel of rowPanels) {
        panel.classList.add('dashboard-row-sized');
        panel.style.setProperty('--dashboard-row-height', `${Math.round(savedHeight)}px`);
      }
    }

    if (!isDashboardRootVisible(rootKey, root)) {
      return;
    }

    const rootRect = root.getBoundingClientRect();
    if (!(rootRect.width > 0 && rootRect.height > 0)) {
      return;
    }

    for (const rowPanels of rows) {
      const signature = dashboardRowSignature(rowPanels);
      if (!signature) {
        continue;
      }
      let minLeft = Infinity;
      let maxRight = -Infinity;
      let maxBottom = -Infinity;
      for (const panel of rowPanels) {
        const rect = panel.getBoundingClientRect();
        if (!(rect.width > 0 && rect.height > 0)) {
          continue;
        }
        minLeft = Math.min(minLeft, rect.left);
        maxRight = Math.max(maxRight, rect.right);
        maxBottom = Math.max(maxBottom, rect.bottom);
      }
      if (!Number.isFinite(minLeft) || !Number.isFinite(maxRight) || !Number.isFinite(maxBottom)) {
        continue;
      }

      const handle = documentRef.createElement('div');
      handle.className = 'dashboard-row-resize-handle';
      handle.dataset.rootKey = rootKey;
      handle.dataset.rowSignature = signature;
      handle.style.left = `${Math.max(0, minLeft - rootRect.left + root.scrollLeft)}px`;
      handle.style.width = `${Math.max(0, maxRight - minLeft)}px`;
      handle.style.top = `${Math.max(0, maxBottom - rootRect.top + root.scrollTop - 4)}px`;
      handle.title = 'Drag to resize row';
      root.appendChild(handle);
    }
  }

  function refreshAllRowSizing() {
    for (const rootKey of dashboard.rootElements.keys()) {
      refreshRowSizing(rootKey);
    }
  }

  function notifyDashboardLayoutChanged(rootKey) {
    if (rootKey === 'vcdTab' && getActiveTab() === 'vcdTab') {
      requestFrame(() => {
        windowRef.dispatchEvent(new Event('resize'));
      });
      return;
    }
    if (rootKey === 'memoryTab' && getActiveTab() === 'memoryTab') {
      requestFrame(() => {
        refreshMemoryView();
      });
      return;
    }
    if ((rootKey === 'componentTab' || rootKey === 'componentGraphTab') && isComponentTabActive()) {
      requestFrame(() => {
        refreshActiveComponentTab();
      });
    }
  }

  function setDashboardRowHeight(rootKey, signature, heightPx) {
    if (!rootKey || !signature) {
      return;
    }
    const existing = dashboard.layouts[rootKey] && typeof dashboard.layouts[rootKey] === 'object'
      ? dashboard.layouts[rootKey]
      : {};
    dashboard.layouts[rootKey] = withDashboardRowHeight(existing, signature, heightPx, minRowHeight);
    writeDashboardLayouts();
    refreshRowSizing(rootKey);
    notifyDashboardLayoutChanged(rootKey);
  }

  function handleDashboardResizeMouseMove(event) {
    if (!dashboard.resizing.active) {
      return;
    }
    const rootKey = dashboard.resizing.rootKey;
    const root = dashboard.rootElements.get(rootKey);
    if (!isHtmlElement(root)) {
      return;
    }
    const rows = dashboardRowsForRoot(root);
    const signature = dashboard.resizing.rowSignature;
    const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
    if (!rowPanels || rowPanels.length === 0) {
      return;
    }

    const delta = event.clientY - dashboard.resizing.startY;
    const nextHeight = Math.max(minRowHeight, dashboard.resizing.startHeight + delta);
    for (const panel of rowPanels) {
      panel.classList.add('dashboard-row-sized');
      panel.style.setProperty('--dashboard-row-height', `${Math.round(nextHeight)}px`);
    }
  }

  function handleDashboardResizeMouseUp() {
    if (!dashboard.resizing.active) {
      return;
    }
    const rootKey = dashboard.resizing.rootKey;
    const signature = dashboard.resizing.rowSignature;
    const root = dashboard.rootElements.get(rootKey);
    if (isHtmlElement(root) && signature) {
      const rows = dashboardRowsForRoot(root);
      const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
      if (rowPanels && rowPanels.length > 0) {
        const maxHeight = Math.max(...rowPanels.map((panel) => panel.getBoundingClientRect().height));
        setDashboardRowHeight(rootKey, signature, maxHeight);
      }
    }
    resetResizingState(state);
  }

  function handleDashboardRowResizeMouseDown(event) {
    const handle = isHtmlElement(event.target)
      ? event.target.closest('.dashboard-row-resize-handle')
      : null;
    if (!isHtmlElement(handle)) {
      return;
    }
    const rootKey = String(handle.dataset.rootKey || '').trim();
    const signature = String(handle.dataset.rowSignature || '').trim();
    if (!rootKey || !signature) {
      return;
    }
    const root = dashboard.rootElements.get(rootKey);
    if (!isHtmlElement(root)) {
      return;
    }
    const rows = dashboardRowsForRoot(root);
    const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
    if (!rowPanels || rowPanels.length === 0) {
      return;
    }

    const startHeight = Math.max(...rowPanels.map((panel) => panel.getBoundingClientRect().height));
    dashboard.resizing.active = true;
    dashboard.resizing.rootKey = rootKey;
    dashboard.resizing.rowSignature = signature;
    dashboard.resizing.startY = event.clientY;
    dashboard.resizing.startHeight = Math.max(minRowHeight, startHeight);
    event.preventDefault();
  }

  function ensureDashboardResizeBinding() {
    if (dashboard.resizeBound) {
      return;
    }
    dashboard.resizeTeardown = bindDashboardResizeEvents({
      onMouseDown: handleDashboardRowResizeMouseDown,
      onMouseMove: handleDashboardResizeMouseMove,
      onMouseUp: handleDashboardResizeMouseUp,
      onWindowResize: () => {
        requestFrame(() => {
          refreshAllRowSizing();
        });
      }
    });
    dashboard.resizeBound = true;
  }

  function ensureControlsDashboardRoot(controlsPanel) {
    if (!isHtmlElement(controlsPanel)) {
      return null;
    }

    let root = controlsPanel.querySelector(':scope > .controls-dashboard-root');
    if (!isHtmlElement(root)) {
      root = documentRef.createElement('div');
      root.className = 'controls-dashboard-root dashboard-layout-root';
      const firstSection = controlsPanel.querySelector(':scope > section');
      if (firstSection) {
        controlsPanel.insertBefore(root, firstSection);
      } else {
        controlsPanel.appendChild(root);
      }
    }

    const sections = Array.from(controlsPanel.querySelectorAll(':scope > section'));
    for (const section of sections) {
      root.appendChild(section);
    }
    return root;
  }

  function flattenDashboardPanelsIntoRoot(root, panelSelector) {
    const panels = Array.from(root.querySelectorAll(panelSelector)).filter((panel) => isHtmlElement(panel));
    for (const panel of panels) {
      if (panel.parentElement !== root) {
        root.appendChild(panel);
      }
    }
  }

  function cleanupDashboardRoots(root, selectors) {
    for (const selector of selectors) {
      const nodes = Array.from(root.querySelectorAll(selector)).filter((entry) => isHtmlElement(entry));
      for (const node of nodes) {
        if (node === root) {
          continue;
        }
        if (!node.querySelector('.subpanel') && !node.querySelector('section')) {
          node.remove();
        }
      }
    }
  }

  function assignDashboardPanelIds(rootKey, panels) {
    const seen = new Set();
    const counts = new Map();
    for (const panel of panels) {
      let itemId = String(panel.dataset.layoutItemId || '').trim();
      if (!itemId) {
        const preferred = String(panel.id || '').trim();
        const base = safeSlugToken(preferred || panelHeaderTitle(panel));
        const n = (counts.get(base) || 0) + 1;
        counts.set(base, n);
        itemId = `${rootKey}:${base}${n > 1 ? `:${n}` : ''}`;
      }
      while (seen.has(itemId)) {
        itemId = `${itemId}_x`;
      }
      panel.dataset.layoutItemId = itemId;
      panel.dataset.layoutRootKey = rootKey;
      seen.add(itemId);
    }
  }

  function applySavedDashboardLayout(rootKey, root) {
    const layout = dashboard.layouts?.[rootKey];
    const panels = dashboardRootPanels(root);
    const panelById = new Map();
    for (const panel of panels) {
      const itemId = String(panel.dataset.layoutItemId || '').trim();
      if (itemId) {
        panelById.set(itemId, panel);
      }
    }

    if (layout && Array.isArray(layout.order)) {
      for (const itemId of layout.order) {
        const key = String(itemId || '');
        const panel = panelById.get(key);
        if (!panel) {
          continue;
        }
        root.appendChild(panel);
        panelById.delete(key);
      }
      for (const panel of panelById.values()) {
        root.appendChild(panel);
      }
    }

    const savedSpans = layout && layout.spans && typeof layout.spans === 'object' ? layout.spans : {};
    for (const panel of dashboardRootPanels(root)) {
      const itemId = String(panel.dataset.layoutItemId || '').trim();
      const fallback = defaultDashboardSpan(rootKey, panel);
      panel.dataset.layoutSpan = normalizeDashboardSpan(savedSpans[itemId], fallback);
    }
    normalizeDashboardSpansForRoot(root);
  }

  function saveDashboardLayout(rootKey) {
    const root = dashboard.rootElements.get(rootKey);
    if (!isHtmlElement(root)) {
      return;
    }
    normalizeDashboardSpansForRoot(root);
    const { order, spans } = snapshotDashboardPanelLayout(
      dashboardRootPanels(root),
      normalizeDashboardSpan,
      (panel) => defaultDashboardSpan(rootKey, panel)
    );
    const prior = dashboard.layouts[rootKey] && typeof dashboard.layouts[rootKey] === 'object'
      ? dashboard.layouts[rootKey]
      : {};
    const rowHeights = prior.rowHeights && typeof prior.rowHeights === 'object'
      ? prior.rowHeights
      : {};
    dashboard.layouts[rootKey] = { order, spans, rowHeights };
    writeDashboardLayouts();
    refreshRowSizing(rootKey);
  }

  function clearDashboardDropState() {
    const highlighted = Array.from(documentRef.querySelectorAll('.dashboard-panel.dashboard-drop-target'));
    for (const panel of highlighted) {
      panel.classList.remove('dashboard-drop-target', 'drop-left', 'drop-right', 'drop-above', 'drop-below');
    }
    dashboard.dropTargetItemId = '';
    dashboard.dropPosition = '';
  }

  function setDashboardDropState(panel, position) {
    if (!isHtmlElement(panel) || !DASHBOARD_DROP_POSITIONS.has(position)) {
      return;
    }
    const itemId = String(panel.dataset.layoutItemId || '').trim();
    if (dashboard.dropTargetItemId === itemId && dashboard.dropPosition === position) {
      return;
    }

    clearDashboardDropState();
    panel.classList.add('dashboard-drop-target', `drop-${position}`);
    dashboard.dropTargetItemId = itemId;
    dashboard.dropPosition = position;
  }

  function findDashboardPanelById(root, itemId) {
    for (const panel of dashboardRootPanels(root)) {
      if (String(panel.dataset.layoutItemId || '').trim() === itemId) {
        return panel;
      }
    }
    return null;
  }

  function applyDashboardDrop(targetPanel, position) {
    if (!isHtmlElement(targetPanel) || !DASHBOARD_DROP_POSITIONS.has(position)) {
      return;
    }
    const rootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
    if (!rootKey || rootKey !== dashboard.draggingRootKey) {
      return;
    }

    const root = dashboard.rootElements.get(rootKey);
    if (!isHtmlElement(root)) {
      return;
    }
    const dragged = findDashboardPanelById(root, dashboard.draggingItemId);
    if (!isHtmlElement(dragged) || dragged === targetPanel) {
      return;
    }

    applyDashboardDropSpanPolicy(position, dragged, targetPanel);

    if (position === 'left' || position === 'above') {
      root.insertBefore(dragged, targetPanel);
    } else {
      root.insertBefore(dragged, targetPanel.nextElementSibling);
    }
    normalizeDashboardSpansForRoot(root);

    saveDashboardLayout(rootKey);
    notifyDashboardLayoutChanged(rootKey);
  }

  function resetDashboardDragState() {
    const draggingPanels = Array.from(documentRef.querySelectorAll('.dashboard-panel.is-dragging'));
    for (const panel of draggingPanels) {
      panel.classList.remove('is-dragging');
    }
    clearDashboardDropState();
    dashboard.draggingItemId = '';
    dashboard.draggingRootKey = '';
  }

  function handleDashboardDragStart(event) {
    const handle = event.currentTarget;
    const panel = isHtmlElement(handle) ? handle.closest('.dashboard-panel') : null;
    if (!isHtmlElement(panel)) {
      return;
    }

    const itemId = String(panel.dataset.layoutItemId || '').trim();
    const rootKey = String(panel.dataset.layoutRootKey || '').trim();
    if (!itemId || !rootKey) {
      return;
    }

    dashboard.draggingItemId = itemId;
    dashboard.draggingRootKey = rootKey;
    panel.classList.add('is-dragging');
    clearDashboardDropState();

    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', itemId);
    }
  }

  function handleDashboardDragEnd() {
    resetDashboardDragState();
  }

  function handleDashboardDragOver(event) {
    const targetPanel = event.currentTarget;
    if (!isHtmlElement(targetPanel)) {
      return;
    }
    const targetRootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
    if (!targetRootKey || !dashboard.draggingItemId || targetRootKey !== dashboard.draggingRootKey) {
      return;
    }
    if (String(targetPanel.dataset.layoutItemId || '').trim() === dashboard.draggingItemId) {
      return;
    }

    event.preventDefault();
    const position = dashboardDropPosition(targetPanel, event);
    setDashboardDropState(targetPanel, position);
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'move';
    }
  }

  function handleDashboardDrop(event) {
    const targetPanel = event.currentTarget;
    if (!isHtmlElement(targetPanel)) {
      return;
    }
    const targetRootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
    if (!targetRootKey || !dashboard.draggingItemId || targetRootKey !== dashboard.draggingRootKey) {
      return;
    }
    if (String(targetPanel.dataset.layoutItemId || '').trim() === dashboard.draggingItemId) {
      resetDashboardDragState();
      return;
    }

    event.preventDefault();
    const position = DASHBOARD_DROP_POSITIONS.has(dashboard.dropPosition)
      ? dashboard.dropPosition
      : dashboardDropPosition(targetPanel, event);
    applyDashboardDrop(targetPanel, position);
    resetDashboardDragState();
  }

  function setupDashboardPanelInteractions(panel) {
    if (!isHtmlElement(panel) || panel.dataset.dashboardReady === '1') {
      return;
    }
    const header = panel.querySelector(':scope > .panel-header-row');
    if (!isHtmlElement(header)) {
      return;
    }

    header.classList.add('panel-drag-handle');
    header.setAttribute('draggable', 'true');
    const teardown = bindDashboardPanelEvents({
      header,
      panel,
      onDragStart: handleDashboardDragStart,
      onDragEnd: handleDashboardDragEnd,
      onDragOver: handleDashboardDragOver,
      onDrop: handleDashboardDrop
    });
    dashboard.panelTeardowns.set(panel, teardown);
    const collapseBtn = panel.querySelector(':scope > .panel-header-row > .panel-collapse-btn');
    if (isHtmlElement(collapseBtn)) {
      collapseBtn.setAttribute('draggable', 'false');
    }
    panel.dataset.dashboardReady = '1';
  }

  function disposePanelTeardowns() {
    if (!(dashboard.panelTeardowns instanceof Map)) {
      dashboard.panelTeardowns = new Map();
      return;
    }
    for (const teardown of dashboard.panelTeardowns.values()) {
      try {
        teardown?.();
      } catch (_err) {
        // Best-effort cleanup.
      }
    }
    dashboard.panelTeardowns.clear();
  }

  function initialize() {
    dashboard.layouts = readDashboardLayouts();
    dashboard.rootElements = new Map();
    disposePanelTeardowns();
    resetDashboardDragState();
    ensureDashboardResizeBinding();

    for (const config of rootConfigs) {
      const baseRoot = documentRef.querySelector(config.selector);
      if (!isHtmlElement(baseRoot)) {
        continue;
      }

      const root = config.wrapControls ? ensureControlsDashboardRoot(baseRoot) : baseRoot;
      if (!isHtmlElement(root)) {
        continue;
      }

      root.classList.add('dashboard-layout-root');
      if (config.wrapControls) {
        root.classList.add('controls-dashboard-root');
      }

      if (config.flattenPanels) {
        flattenDashboardPanelsIntoRoot(root, config.panelSelector);
      }
      cleanupDashboardRoots(root, Array.isArray(config.cleanupSelectors) ? config.cleanupSelectors : []);

      const panels = Array.from(root.querySelectorAll(config.panelSelector))
        .filter((panel) => isHtmlElement(panel) && panel.parentElement === root);
      assignDashboardPanelIds(config.key, panels);

      for (const panel of panels) {
        panel.classList.add('dashboard-panel');
        panel.dataset.layoutSpan = normalizeDashboardSpan(
          panel.dataset.layoutSpan,
          defaultDashboardSpan(config.key, panel)
        );
        setupDashboardPanelInteractions(panel);
      }

      const staticNodes = Array.from(root.children).filter((entry) => isHtmlElement(entry) && !entry.classList.contains('dashboard-panel'));
      for (const node of staticNodes) {
        node.classList.add('dashboard-static');
      }
      for (const selector of config.staticSelectors || []) {
        const nodes = Array.from(root.querySelectorAll(selector)).filter((entry) => isHtmlElement(entry));
        for (const node of nodes) {
          if (node.parentElement === root) {
            node.classList.add('dashboard-static');
          }
        }
      }

      dashboard.rootElements.set(config.key, root);
      applySavedDashboardLayout(config.key, root);
      saveDashboardLayout(config.key);
    }
    refreshAllRowSizing();
  }

  function dispose() {
    if (dashboard.resizeBound) {
      try {
        dashboard.resizeTeardown?.();
      } catch (_err) {
        // Best-effort cleanup.
      }
    }
    dashboard.resizeBound = false;
    dashboard.resizeTeardown = null;
    disposePanelTeardowns();
    resetDashboardDragState();
    resetResizingState(state);
    for (const root of dashboard.rootElements.values()) {
      clearDashboardRowSizing(root);
    }
    dashboard.rootElements = new Map();
  }

  return {
    initialize,
    refreshRowSizing,
    refreshAllRowSizing,
    dispose
  };
}
