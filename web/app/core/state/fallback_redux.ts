import * as Redux from 'redux';

export function resolveRedux(reduxCandidate: any = null) {
  if (reduxCandidate && typeof reduxCandidate.createStore === 'function') {
    return reduxCandidate;
  }
  return Redux;
}
