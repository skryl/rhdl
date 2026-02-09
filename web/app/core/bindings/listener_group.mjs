export function createListenerGroup() {
  const removers = [];

  function on(target, type, handler, options = undefined) {
    if (!target || typeof target.addEventListener !== 'function' || typeof handler !== 'function') {
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
      try {
        off();
      } catch (_err) {
        // Ignore listener cleanup errors; this is best-effort teardown.
      }
    }
  }

  function size() {
    return removers.length;
  }

  return { on, dispose, size };
}
