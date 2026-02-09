import { resolveRedux } from './fallback_redux.mjs';
import { reduceState } from './reducer.mjs';

export function createAppStore(initialState, reduxCandidate = null) {
  if (!initialState || typeof initialState !== 'object') {
    throw new Error('createAppStore requires an initial state object.');
  }
  const redux = resolveRedux(reduxCandidate);
  const reducer = (state = initialState, action = {}) => reduceState(state, action);
  return redux.createStore(reducer, initialState);
}
