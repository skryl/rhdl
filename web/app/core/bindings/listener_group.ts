import type { EventTargetLike, ListenerGroup } from '../../types/services';

export function createListenerGroup(): ListenerGroup {
  const removers: Array<() => void> = [];

  function on(
    target: EventTargetLike | null | undefined,
    type: string,
    handler: EventListenerOrEventListenerObject,
    options: boolean | AddEventListenerOptions | undefined = undefined
  ) {
    const hasTargetMethods = !!target
      && typeof target.addEventListener === 'function'
      && typeof target.removeEventListener === 'function';
    if (!hasTargetMethods || typeof handler !== 'function') {
      return () => {};
    }

    target.addEventListener(type, handler, options);
    const off = () => {
      target.removeEventListener(type, handler, options);
    };
    removers.push(off);
    return off;
  }

  function dispose() {
    while (removers.length > 0) {
      const off = removers.pop();
      if (!off) {
        continue;
      }
      try {
        off();
      } catch (_err: unknown) {
        // Ignore listener cleanup errors; this is best-effort teardown.
      }
    }
  }

  function size() {
    return removers.length;
  }

  return { on, dispose, size };
}
