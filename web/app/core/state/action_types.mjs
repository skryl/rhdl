import { simActionTypes } from '../../components/sim/state/slice.mjs';
import { shellActionTypes } from '../../components/shell/state/slice.mjs';
import { runnerActionTypes } from '../../components/runner/state/slice.mjs';
import { memoryActionTypes } from '../../components/memory/state/slice.mjs';
import { apple2ActionTypes } from '../../components/apple2/state/slice.mjs';
import { watchActionTypes } from '../../components/watch/state/slice.mjs';

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
