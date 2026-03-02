import { createSimStateSlice } from '../../components/sim/state/slice';
import { createShellStateSlice } from '../../components/shell/state/slice';
import { createRunnerStateSlice } from '../../components/runner/state/slice';
import { createMemoryStateSlice } from '../../components/memory/state/slice';
import { createApple2StateSlice } from '../../components/apple2/state/slice';
import { createWatchStateSlice } from '../../components/watch/state/slice';
import { createTerminalStateSlice } from '../../components/terminal/state/slice';
import { createExplorerStateSlice } from '../../components/explorer/state/slice';
import type { AppState } from '../../types/state';

export function createInitialState(): AppState {
  return {
    ...createSimStateSlice(),
    ...createShellStateSlice(),
    ...createRunnerStateSlice(),
    ...createMemoryStateSlice(),
    ...createApple2StateSlice(),
    ...createWatchStateSlice(),
    ...createTerminalStateSlice(),
    ...createExplorerStateSlice()
  } as AppState;
}
