import { actionTypes } from './action_types.mjs';
import { simActions } from '../../components/sim/state/slice.mjs';
import { shellActions } from '../../components/shell/state/slice.mjs';
import { runnerActions } from '../../components/runner/state/slice.mjs';
import { memoryActions } from '../../components/memory/state/slice.mjs';
import { apple2Actions } from '../../components/apple2/state/slice.mjs';
import { watchActions } from '../../components/watch/state/slice.mjs';

export const actions = {
  ...simActions,
  ...shellActions,
  ...runnerActions,
  ...memoryActions,
  ...apple2Actions,
  ...watchActions,
  touch: (meta = null) => ({ type: actionTypes.TOUCH, payload: meta }),
  mutate: (mutator) => ({ type: actionTypes.MUTATE, payload: mutator })
};
