export function createEventLogger(eventLogEl: any) {
  return function log(message: any) {
    const ts = new Date().toLocaleTimeString();
    eventLogEl.textContent = `[${ts}] ${message}\n${eventLogEl.textContent}`;
  };
}
