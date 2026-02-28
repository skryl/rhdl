import { resolveRedux } from './fallback_redux';
import { reduceState } from './reducer';

export function createAppStore(initialState: any, reduxCandidate = null) {
  if (!initialState || typeof initialState !== 'object') {
    throw new Error('createAppStore requires an initial state object.');
  }
  const redux = resolveRedux(reduxCandidate);
  const reducer = (state: any = initialState, action: any = {}) => reduceState(state, action);
  return redux.createStore(reducer, initialState);
}
