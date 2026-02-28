import { createSimStateSlice } from '../../components/sim/state/slice.mjs';
import { createShellStateSlice } from '../../components/shell/state/slice.mjs';
import { createRunnerStateSlice } from '../../components/runner/state/slice.mjs';
import { createMemoryStateSlice } from '../../components/memory/state/slice.mjs';
import { createApple2StateSlice } from '../../components/apple2/state/slice.mjs';
import { createWatchStateSlice } from '../../components/watch/state/slice.mjs';
import { createTerminalStateSlice } from '../../components/terminal/state/slice.mjs';
import { createExplorerStateSlice } from '../../components/explorer/state/slice.mjs';

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
