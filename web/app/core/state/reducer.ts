import { actionTypes } from './action_types';
import { reduceSimState } from '../../components/sim/state/slice';
import { reduceShellState } from '../../components/shell/state/slice';
import { reduceRunnerState } from '../../components/runner/state/slice';
import { reduceMemoryState } from '../../components/memory/state/slice';
import { reduceApple2State } from '../../components/apple2/state/slice';
import { reduceWatchState } from '../../components/watch/state/slice';
import type { AppState, ReduxAction, ReduxMutator } from '../../types/state';

function isReduxMutator(value: unknown): value is ReduxMutator {
  return typeof value === 'function';
}

export function reduceState(state: AppState, action: ReduxAction<unknown> = {}) {
  switch (action.type) {
    case actionTypes.TOUCH:
      state.__lastReduxMeta = action.payload || null;
      return state;
    case actionTypes.MUTATE:
      if (isReduxMutator(action.payload)) {
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
