import { resolveRedux } from './fallback_redux';
import { reduceState } from './reducer';
import type { ReduxStoreLike, ReduxLike } from '../../types/services';
import type { AppState, ReduxAction } from '../../types/state';

export function createAppStore(
  initialState: AppState,
  reduxCandidate: unknown = null
): ReduxStoreLike<AppState> {
  if (!initialState || typeof initialState !== 'object') {
    throw new Error('createAppStore requires an initial state object.');
  }
  const redux = resolveRedux(reduxCandidate) as ReduxLike;
  const reducer = (state: AppState = initialState, action: ReduxAction<unknown> = {}) => reduceState(state, action);
  return redux.createStore(reducer, initialState);
}
