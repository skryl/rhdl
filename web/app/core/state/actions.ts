import { actionTypes } from './action_types';
import { simActions } from '../../components/sim/state/slice';
import { shellActions } from '../../components/shell/state/slice';
import { runnerActions } from '../../components/runner/state/slice';
import { memoryActions } from '../../components/memory/state/slice';
import { apple2Actions } from '../../components/apple2/state/slice';
import { watchActions } from '../../components/watch/state/slice';

export const actions = {
  ...simActions,
  ...shellActions,
  ...runnerActions,
  ...memoryActions,
  ...apple2Actions,
  ...watchActions,
  touch: (meta = null) => ({ type: actionTypes.TOUCH, payload: meta }),
  mutate: (mutator: any) => ({ type: actionTypes.MUTATE, payload: mutator })
};
