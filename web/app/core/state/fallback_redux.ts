import * as Redux from 'redux';
import type { ReduxLike } from '../../types/services';

function isReduxLike(value: unknown): value is ReduxLike {
  return !!value
    && typeof value === 'object'
    && typeof (value as { createStore?: unknown }).createStore === 'function';
}

export function resolveRedux(reduxCandidate: unknown = null): ReduxLike {
  if (isReduxLike(reduxCandidate)) {
    return reduxCandidate;
  }
  return Redux as unknown as ReduxLike;
}
