import {
  toBigInt,
  parseNumeric,
  formatValue
} from '../../../core/lib/numeric_utils';
import {
  renderWatchTableRows,
  renderWatchListItems,
  renderBreakpointListItems
} from '../ui/vcd_panel';
import { createWatchManager } from '../managers/manager';

function requireFn(name: Unsafe, fn: Unsafe) {
  if (typeof fn !== 'function') {
    throw new Error(`createWatchLazyGetters requires function: ${name}`);
  }
}

export function createWatchLazyGetters({
  dom,
  state,
  runtime,
  appStore,
  storeActions,
  scheduleReduxUxSync,
  log,
  maskForWidth
}: Unsafe = {}) {
  if (!dom || !state || !runtime || !appStore || !storeActions) {
    throw new Error('createWatchLazyGetters requires dom/state/runtime/appStore/storeActions');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('log', log);
  requireFn('maskForWidth', maskForWidth);

  let watchManager: Unsafe = null;

  function getWatchManager() {
    if (!watchManager) {
      watchManager = createWatchManager({
        dom,
        state,
        runtime,
        appStore,
        storeActions,
        formatValue,
        parseNumeric,
        maskForWidth,
        toBigInt,
        log,
        scheduleReduxUxSync,
        renderWatchTableRows,
        renderWatchListItems,
        renderBreakpointListItems
      });
    }
    return watchManager;
  }

  return {
    getWatchManager
  };
}
