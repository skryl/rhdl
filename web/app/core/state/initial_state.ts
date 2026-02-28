import { createSimStateSlice } from '../../components/sim/state/slice';
import { createShellStateSlice } from '../../components/shell/state/slice';
import { createRunnerStateSlice } from '../../components/runner/state/slice';
import { createMemoryStateSlice } from '../../components/memory/state/slice';
import { createApple2StateSlice } from '../../components/apple2/state/slice';
import { createWatchStateSlice } from '../../components/watch/state/slice';
import { createTerminalStateSlice } from '../../components/terminal/state/slice';
import { createExplorerStateSlice } from '../../components/explorer/state/slice';

export function createInitialState() {
  return {
    ...createSimStateSlice(),
    ...createShellStateSlice(),
    ...createRunnerStateSlice(),
    ...createMemoryStateSlice(),
    ...createApple2StateSlice(),
    ...createWatchStateSlice(),
    ...createTerminalStateSlice(),
    ...createExplorerStateSlice()
  };
}
