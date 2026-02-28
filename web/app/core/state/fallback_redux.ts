export const FALLBACK_REDUX = {
  createStore(reducer, preloadedState, enhancer) {
    if (typeof enhancer === 'function') {
      return enhancer(this.createStore.bind(this))(reducer, preloadedState);
    }

    let currentState = preloadedState;
    let listeners = [];
    let isDispatching = false;

    const getState = () => currentState;

    const subscribe = (listener) => {
      if (typeof listener !== 'function') {
        return () => {};
      }
      listeners.push(listener);
      return () => {
        listeners = listeners.filter((entry) => entry !== listener);
      };
    };

    const dispatch = (action) => {
      if (!action || typeof action.type !== 'string') {
        throw new Error('Actions must be plain objects with a string `type`.');
      }
      if (isDispatching) {
        throw new Error('Reducers may not dispatch actions.');
      }

      try {
        isDispatching = true;
        currentState = reducer(currentState, action);
      } finally {
        isDispatching = false;
      }

      const snapshot = listeners.slice();
      for (const listener of snapshot) {
        listener();
      }
      return action;
    };

    dispatch({ type: '@@INIT' });

    return { getState, subscribe, dispatch };
  }
};

export function resolveRedux(reduxCandidate = null) {
  if (reduxCandidate && typeof reduxCandidate.createStore === 'function') {
    return reduxCandidate;
  }
  if (typeof window !== 'undefined' && window.Redux && typeof window.Redux.createStore === 'function') {
    return window.Redux;
  }
  return FALLBACK_REDUX;
}
