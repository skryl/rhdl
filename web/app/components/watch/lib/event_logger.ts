export function createEventLogger(eventLogEl: Unsafe) {
  return function log(message: Unsafe) {
    const ts = new Date().toLocaleTimeString();
    eventLogEl.textContent = `[${ts}] ${message}\n${eventLogEl.textContent}`;
  };
}
