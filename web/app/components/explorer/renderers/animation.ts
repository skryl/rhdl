// Wire pulse animation state manager.
// Tracks per-wire toggle animations with configurable duration.

const DEFAULT_PULSE_DURATION_MS = 200;

interface AnimationState {
  elapsedMs: number;
}

interface CreateAnimationOptions {
  pulseDurationMs?: number;
}

export function createAnimationState({ pulseDurationMs = DEFAULT_PULSE_DURATION_MS }: CreateAnimationOptions = {}) {
  const activeAnimations = new Map<string, AnimationState>();

  function markToggled(wireId: unknown): void {
    const id = String(wireId || '').trim();
    if (!id) {
      return;
    }
    activeAnimations.set(id, { elapsedMs: 0 });
  }

  function tick(dtMs: unknown): void {
    const delta = Number(dtMs);
    const step = Number.isFinite(delta) && delta > 0 ? delta : 0;
    for (const [wireId, anim] of activeAnimations) {
      anim.elapsedMs += step;
      if (anim.elapsedMs >= pulseDurationMs) {
        activeAnimations.delete(wireId);
      }
    }
  }

  function getWireAnimation(wireId: unknown): { pulseT: number } | null {
    const id = String(wireId || '').trim();
    if (!id) {
      return null;
    }
    const anim = activeAnimations.get(id);
    if (!anim) {
      return null;
    }
    return { pulseT: Math.min(anim.elapsedMs / pulseDurationMs, 1.0) };
  }

  return { markToggled, tick, getWireAnimation };
}
