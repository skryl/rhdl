import test from 'node:test';
import assert from 'node:assert/strict';

import { toBigInt, parseNumeric } from '../../../../app/core/lib/numeric_utils.mjs';
import { createWatchManager } from '../../../../app/components/watch/managers/manager.mjs';

function maskForWidth(width) {
  const w = Number(width) || 1;
  if (w >= 64) {
    return (1n << 64n) - 1n;
  }
  return (1n << BigInt(Math.max(1, w))) - 1n;
}

function setupHarness({
  hasSim = true,
  signalMap = new Map([['sig_a', 1]]),
  widths = new Map([['sig_a', 3]])
} = {}) {
  const state = {
    watches: new Map(),
    watchRows: [],
    breakpoints: []
  };

  const traceAdded = [];
  const runtime = {
    irMeta: { widths },
    sim: hasSim
      ? {
          features: { hasSignalIndex: true },
          get_signal_idx: (name) => (signalMap.has(name) ? signalMap.get(name) : -1),
          has_signal: (name) => signalMap.has(name),
          trace_add_signal: (name) => traceAdded.push(name),
          peek_by_idx: (idx) => BigInt(idx),
          peek: () => 0n
        }
      : null
  };

  const scheduleCalls = [];
  const logs = [];
  const renderCalls = {
    table: [],
    list: [],
    bps: []
  };

  const storeActions = {
    watchSet: (name, info) => ({ type: 'watchSet', name, info }),
    watchRemove: (name) => ({ type: 'watchRemove', name }),
    watchClear: () => ({ type: 'watchClear' }),
    breakpointAddOrReplace: (bp) => ({ type: 'breakpointAddOrReplace', bp }),
    breakpointClear: () => ({ type: 'breakpointClear' })
  };

  const appStore = {
    dispatch(action) {
      switch (action.type) {
        case 'watchSet':
          state.watches.set(action.name, action.info);
          break;
        case 'watchRemove':
          state.watches.delete(action.name);
          break;
        case 'watchClear':
          state.watches.clear();
          break;
        case 'breakpointAddOrReplace': {
          const next = state.breakpoints.filter((bp) => bp.name !== action.bp.name);
          next.push(action.bp);
          state.breakpoints = next;
          break;
        }
        case 'breakpointClear':
          state.breakpoints = [];
          break;
        default:
          break;
      }
    }
  };

  const manager = createWatchManager({
    dom: {},
    state,
    runtime,
    appStore,
    storeActions,
    formatValue: (value) => String(value),
    parseNumeric,
    maskForWidth,
    toBigInt,
    log: (message) => logs.push(message),
    scheduleReduxUxSync: (reason) => scheduleCalls.push(reason),
    renderWatchTableRows: (_dom, rows) => renderCalls.table.push(rows),
    renderWatchListItems: (_dom, names) => renderCalls.list.push(names),
    renderBreakpointListItems: (_dom, bps) => renderCalls.bps.push(bps)
  });

  return { manager, state, runtime, logs, scheduleCalls, renderCalls, traceAdded };
}

test('refreshWatchTable clears rows when simulator is unavailable', () => {
  const { manager, state, renderCalls } = setupHarness({ hasSim: false });
  manager.refreshWatchTable();
  assert.deepEqual(state.watchRows, []);
  assert.equal(renderCalls.table.length, 1);
  assert.deepEqual(renderCalls.table[0], []);
});

test('addWatchSignal registers signal and triggers trace/watch rendering', () => {
  const { manager, state, traceAdded, renderCalls, scheduleCalls } = setupHarness();
  const ok = manager.addWatchSignal('sig_a');
  assert.equal(ok, true);
  assert.equal(state.watches.has('sig_a'), true);
  assert.deepEqual(traceAdded, ['sig_a']);
  assert.equal(renderCalls.table.length, 1);
  assert.equal(renderCalls.list.length, 1);
  assert.ok(scheduleCalls.includes('addWatchSignal'));
});

test('addWatchSignal logs and rejects unknown signals', () => {
  const { manager, logs } = setupHarness();
  const ok = manager.addWatchSignal('missing_sig');
  assert.equal(ok, false);
  assert.match(logs.join('\n'), /Unknown signal: missing_sig/);
});

test('addBreakpointSignal masks values and stores breakpoint entry', () => {
  const { manager, state } = setupHarness();
  const value = manager.addBreakpointSignal('sig_a', '0b1111');
  assert.equal(value, 0b111n);
  assert.equal(state.breakpoints.length, 1);
  assert.equal(state.breakpoints[0].name, 'sig_a');
  assert.equal(state.breakpoints[0].value, 0b111n);
});

test('checkBreakpoints returns matching signal and value', () => {
  const { manager, state, runtime } = setupHarness();
  state.breakpoints = [{ name: 'sig_a', idx: 1, width: 1, value: 1n }];
  runtime.sim.peek_by_idx = () => 1n;
  const hit = manager.checkBreakpoints();
  assert.deepEqual(hit, { signal: 'sig_a', value: 1n });
});
