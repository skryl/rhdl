// Wire pulse animation state manager.
// Tracks per-wire toggle animations with configurable duration.

const DEFAULT_PULSE_DURATION_MS = 200;

export function createAnimationState({ pulseDurationMs = DEFAULT_PULSE_DURATION_MS } = {}) {
  // Map<wireId, { elapsedMs: number }>
  const activeAnimations = new Map();

  function markToggled(wireId) {
    activeAnimations.set(wireId, { elapsedMs: 0 });
  }

  function tick(dtMs) {
    for (const [wireId, anim] of activeAnimations) {
      anim.elapsedMs += dtMs;
      if (anim.elapsedMs >= pulseDurationMs) {
        activeAnimations.delete(wireId);
      }
    }
  }

  function getWireAnimation(wireId) {
    const anim = activeAnimations.get(wireId);
    if (!anim) return null;
    return { pulseT: Math.min(anim.elapsedMs / pulseDurationMs, 1.0) };
  }

  return { markToggled, tick, getWireAnimation };
}
