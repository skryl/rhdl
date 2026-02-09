import { parseBooleanToken } from '../../lib/tokens.mjs';
import { normalizeUiId } from './parse.mjs';

export function createTerminalUiHelpers({
  documentRef = globalThis.document,
  eventCtor = globalThis.Event
} = {}) {
  function dispatchBubbledEvent(target, type) {
    if (!target || typeof target.dispatchEvent !== 'function' || typeof eventCtor !== 'function') {
      return;
    }
    target.dispatchEvent(new eventCtor(type, { bubbles: true }));
  }

  function setUiInputValueById(id, value) {
    const elementId = normalizeUiId(id);
    if (!elementId) {
      throw new Error('Missing element id.');
    }
    const el = documentRef.getElementById(elementId);
    if (!(el instanceof HTMLElement)) {
      throw new Error(`Unknown element: ${elementId}`);
    }

    if (el instanceof HTMLInputElement && el.type === 'checkbox') {
      const parsed = parseBooleanToken(value);
      if (parsed == null) {
        throw new Error(`Invalid checkbox value for ${elementId}: ${value}`);
      }
      el.checked = parsed;
      dispatchBubbledEvent(el, 'change');
      return `set #${elementId}= ${parsed ? 'on' : 'off'}`;
    }

    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
      el.value = String(value ?? '');
      dispatchBubbledEvent(el, 'input');
      if (el instanceof HTMLInputElement && (el.type === 'number' || el.type === 'range')) {
        dispatchBubbledEvent(el, 'change');
      }
      return `set #${elementId}= ${el.value}`;
    }

    if (el instanceof HTMLSelectElement) {
      const next = String(value ?? '');
      const hasOption = Array.from(el.options).some((opt) => opt.value === next);
      if (!hasOption) {
        const options = Array.from(el.options).map((opt) => opt.value).join(', ');
        throw new Error(`Invalid option for ${elementId}. Available: ${options}`);
      }
      el.value = next;
      dispatchBubbledEvent(el, 'change');
      return `set #${elementId}= ${el.value}`;
    }

    throw new Error(`Element does not support value assignment: ${elementId}`);
  }

  function clickUiElementById(id) {
    const elementId = normalizeUiId(id);
    if (!elementId) {
      throw new Error('Missing element id.');
    }
    const el = documentRef.getElementById(elementId);
    if (!(el instanceof HTMLElement)) {
      throw new Error(`Unknown element: ${elementId}`);
    }
    if (typeof el.click !== 'function') {
      throw new Error(`Element is not clickable: ${elementId}`);
    }
    el.click();
    return `clicked #${elementId}`;
  }

  return {
    dispatchBubbledEvent,
    setUiInputValueById,
    clickUiElementById
  };
}
