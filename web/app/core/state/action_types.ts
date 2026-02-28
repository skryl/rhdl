import { simActionTypes } from '../../components/sim/state/slice';
import { shellActionTypes } from '../../components/shell/state/slice';
import { runnerActionTypes } from '../../components/runner/state/slice';
import { memoryActionTypes } from '../../components/memory/state/slice';
import { apple2ActionTypes } from '../../components/apple2/state/slice';
import { watchActionTypes } from '../../components/watch/state/slice';

export const actionTypes = {
  ...simActionTypes,
  ...shellActionTypes,
  ...runnerActionTypes,
  ...memoryActionTypes,
  ...apple2ActionTypes,
  ...watchActionTypes,
  TOUCH: 'app/touch',
  MUTATE: 'state/mutate'
};
