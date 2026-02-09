import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

export function bindDashboardResizeEvents({ onMouseDown, onMouseMove, onMouseUp, onWindowResize }) {
  const listeners = createListenerGroup();

  listeners.on(document, 'mousedown', onMouseDown);
  listeners.on(document, 'mousemove', onMouseMove);
  listeners.on(document, 'mouseup', onMouseUp);
  listeners.on(window, 'resize', onWindowResize);

  return () => {
    listeners.dispose();
  };
}

export function bindDashboardPanelEvents({ header, panel, onDragStart, onDragEnd, onDragOver, onDrop }) {
  const listeners = createListenerGroup();

  listeners.on(header, 'dragstart', onDragStart);
  listeners.on(header, 'dragend', onDragEnd);
  listeners.on(panel, 'dragover', onDragOver);
  listeners.on(panel, 'drop', onDrop);

  return () => {
    listeners.dispose();
  };
}
