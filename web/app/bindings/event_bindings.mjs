export function createEventLogger(eventLogEl) {
  return function log(message) {
    const ts = new Date().toLocaleTimeString();
    eventLogEl.textContent = `[${ts}] ${message}\n${eventLogEl.textContent}`;
  };
}
