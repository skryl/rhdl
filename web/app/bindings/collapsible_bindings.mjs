import { createListenerGroup } from './listener_bindings.mjs';

const COMPONENT_PANEL_CLASSES = new Set([
  'component-tree-panel',
  'component-signal-panel',
  'component-detail-panel',
  'component-visual-panel',
  'component-live-panel',
  'component-connection-panel'
]);

export function isComponentPanel(panel) {
  if (!panel || !panel.classList || typeof panel.classList.contains !== 'function') {
    return false;
  }
  for (const className of COMPONENT_PANEL_CLASSES) {
    if (panel.classList.contains(className)) {
      return true;
    }
  }
  return false;
}

function setPanelCollapsed(panel, button, collapsed) {
  const next = !!collapsed;
  panel.classList.toggle('is-collapsed', next);
  button.textContent = '';
  button.classList.toggle('is-collapsed', next);
  button.setAttribute('aria-expanded', next ? 'false' : 'true');
  button.setAttribute('title', next ? 'Expand' : 'Collapse');
  const title = String(panel.dataset.collapseTitle || 'panel');
  button.setAttribute('aria-label', `${next ? 'Expand' : 'Collapse'} ${title}`);
}

function handlePanelCollapseChanged(panel, collapsed, actions) {
  const rootKey = String(panel?.dataset?.layoutRootKey || '').trim();
  requestAnimationFrame(() => {
    if (rootKey) {
      actions.refreshDashboardRowSizing(rootKey);
    } else {
      actions.refreshAllDashboardRowSizing();
    }
  });

  if (collapsed) {
    return;
  }

  if (isComponentPanel(panel)) {
    requestAnimationFrame(() => {
      if (actions.isComponentTabActive()) {
        actions.refreshActiveComponentTab();
      }
    });
    return;
  }

  const activeTab = actions.getActiveTab();
  if (activeTab === 'vcdTab') {
    requestAnimationFrame(() => {
      window.dispatchEvent(new Event('resize'));
    });
    return;
  }

  if (activeTab === 'memoryTab') {
    requestAnimationFrame(() => {
      actions.refreshMemoryView();
    });
  }
}

export function bindCollapsiblePanels({ selector, actions }) {
  const listeners = createListenerGroup();
  const panels = Array.from(document.querySelectorAll(selector));

  for (const panel of panels) {
    if (!(panel instanceof HTMLElement) || panel.dataset.collapseReady === '1') {
      continue;
    }

    const heading = panel.querySelector(':scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6');
    if (!(heading instanceof HTMLElement)) {
      continue;
    }

    panel.classList.add('collapsible-panel');
    panel.dataset.collapseReady = '1';
    panel.dataset.collapseTitle = String(heading.textContent || '').trim().replace(/\s+/g, ' ') || 'panel';

    heading.classList.add('panel-header-title');

    const headerRow = document.createElement('div');
    headerRow.className = 'panel-header-row';
    panel.insertBefore(headerRow, panel.firstChild);
    headerRow.appendChild(heading);

    const collapseBtn = document.createElement('button');
    collapseBtn.type = 'button';
    collapseBtn.className = 'panel-collapse-btn';
    headerRow.appendChild(collapseBtn);
    setPanelCollapsed(panel, collapseBtn, false);

    listeners.on(collapseBtn, 'click', () => {
      const nextCollapsed = !panel.classList.contains('is-collapsed');
      setPanelCollapsed(panel, collapseBtn, nextCollapsed);
      handlePanelCollapseChanged(panel, nextCollapsed, actions);
    });
  }

  return () => {
    listeners.dispose();
  };
}
