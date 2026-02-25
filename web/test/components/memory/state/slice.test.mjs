import test from 'node:test';
import assert from 'node:assert/strict';
import {
  memoryActionTypes,
  memoryActions,
  createMemoryStateSlice,
  reduceMemoryState
} from '../../../../app/components/memory/state/slice.mjs';

test('createMemoryStateSlice returns initial state with showSource false', () => {
  const state = createMemoryStateSlice();
  assert.equal(state.memory.showSource, false);
});

test('SET_MEMORY_SHOW_SOURCE action sets showSource to true', () => {
  const state = createMemoryStateSlice();
  const changed = reduceMemoryState(state, {
    type: memoryActionTypes.SET_MEMORY_SHOW_SOURCE,
    payload: true
  });
  assert.equal(changed, true);
  assert.equal(state.memory.showSource, true);
});

test('SET_MEMORY_SHOW_SOURCE action sets showSource to false after true', () => {
  const state = createMemoryStateSlice();
  reduceMemoryState(state, {
    type: memoryActionTypes.SET_MEMORY_SHOW_SOURCE,
    payload: true
  });
  assert.equal(state.memory.showSource, true);

  reduceMemoryState(state, {
    type: memoryActionTypes.SET_MEMORY_SHOW_SOURCE,
    payload: false
  });
  assert.equal(state.memory.showSource, false);
});

test('setMemoryShowSource action creator produces correct action', () => {
  const action = memoryActions.setMemoryShowSource(true);
  assert.equal(action.type, memoryActionTypes.SET_MEMORY_SHOW_SOURCE);
  assert.equal(action.payload, true);
});
