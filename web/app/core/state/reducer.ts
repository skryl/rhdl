import { actionTypes } from './action_types';
import { reduceSimState } from '../../components/sim/state/slice';
import { reduceShellState } from '../../components/shell/state/slice';
import { reduceRunnerState } from '../../components/runner/state/slice';
import { reduceMemoryState } from '../../components/memory/state/slice';
import { reduceApple2State } from '../../components/apple2/state/slice';
import { reduceWatchState } from '../../components/watch/state/slice';

export function reduceState(state: any, action: any = {}) {
  switch (action.type) {
    case actionTypes.TOUCH:
      state.__lastReduxMeta = action.payload || null;
      return state;
    case actionTypes.MUTATE:
      if (typeof action.payload === 'function') {
        action.payload(state);
      }
      return state;
    default:
      break;
  }

  if (reduceSimState(state, action)) {
    return state;
  }
  if (reduceShellState(state, action)) {
    return state;
  }
  if (reduceRunnerState(state, action)) {
    return state;
  }
  if (reduceMemoryState(state, action)) {
    return state;
  }
  if (reduceApple2State(state, action)) {
    return state;
  }
  if (reduceWatchState(state, action)) {
    return state;
  }
  return state;
}
