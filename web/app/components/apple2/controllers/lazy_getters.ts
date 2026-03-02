import {
  parseHexOrDec,
  hexWord,
  hexByte
} from '../../../core/lib/numeric_utils';
import { disassemble6502Lines as disassemble6502LinesWithMemory } from '../lib/mos6502_disasm';
import { disassembleRiscvLines as disassembleRiscvLinesWithMemory } from '../../riscv/lib/riscv_disasm';
import { renderApple2DebugRows } from '../ui/panel';
import { renderMemoryPanel } from '../../memory/ui/panel';
import {
  APPLE2_RAM_BYTES,
  APPLE2_ADDR_SPACE,
  KARATEKA_PC,
  LAST_APPLE2_DUMP_KEY
} from '../config/constants';
import { createApple2MemoryController } from './memory_controller';
import { createApple2VisualController } from './visual_controller';
import { createApple2OpsController } from './ops_controller';

function requireFn(name: string, fn: unknown) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2LazyGetters requires function: ${name}`);
  }
}

export function createApple2LazyGetters({
  dom,
  state,
  runtime,
  setApple2SoundEnabledState,
  setMemoryFollowPcState,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  fetchImpl,
  windowRef,
  documentRef,
  log,
  isApple2UiEnabled,
  setMemoryDumpStatus,
  updateIoToggleUi,
  apple2HiresLineAddress,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  refreshWatchTable,
  refreshStatus,
  getApple2ProgramCounter,
  currentRunnerPreset
}: Unsafe = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2LazyGetters requires dom/state/runtime');
  }
  requireFn('setApple2SoundEnabledState', setApple2SoundEnabledState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('fetchImpl', fetchImpl);
  requireFn('log', log);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('apple2HiresLineAddress', apple2HiresLineAddress);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshStatus', refreshStatus);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('currentRunnerPreset', currentRunnerPreset);

  let apple2MemoryController: ReturnType<typeof createApple2MemoryController> | null = null;
  let apple2VisualController: ReturnType<typeof createApple2VisualController> | null = null;
  let apple2OpsController: ReturnType<typeof createApple2OpsController> | null = null;

  function getApple2MemoryController() {
    if (!apple2MemoryController) {
      apple2MemoryController = createApple2MemoryController({
        dom,
        state,
        runtime,
        isApple2UiEnabled,
        parseHexOrDec,
        hexWord,
        hexByte,
        renderMemoryPanel,
        disassemble6502LinesWithMemory,
        disassembleRiscvLinesWithMemory,
        setMemoryDumpStatus,
        addressSpace: APPLE2_ADDR_SPACE
      });
    }
    return apple2MemoryController;
  }

  function getApple2VisualController() {
    if (!apple2VisualController) {
      apple2VisualController = createApple2VisualController({
        dom,
        state,
        runtime,
        isApple2UiEnabled,
        updateIoToggleUi,
        renderApple2DebugRows,
        apple2HiresLineAddress
      });
    }
    return apple2VisualController;
  }

  function getApple2OpsController() {
    if (!apple2OpsController) {
      apple2OpsController = createApple2OpsController({
        dom,
        state,
        runtime,
        APPLE2_RAM_BYTES,
        KARATEKA_PC,
        LAST_APPLE2_DUMP_KEY,
        setApple2SoundEnabledState,
        setMemoryFollowPcState,
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        refreshApple2Screen,
        refreshApple2Debug,
        refreshMemoryView,
        refreshWatchTable,
        refreshStatus,
        getApple2ProgramCounter,
        currentRunnerPreset,
        log,
        fetchImpl,
        windowRef,
        documentRef
      });
    }
    return apple2OpsController;
  }

  return {
    getApple2MemoryController,
    getApple2VisualController,
    getApple2OpsController
  };
}
