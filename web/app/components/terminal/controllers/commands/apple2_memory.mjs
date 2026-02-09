import { parseBooleanToken } from '../../lib/tokens.mjs';

export async function handleApple2MemoryCommand({ cmd, tokens, context }) {
  const { dom, state, actions, helpers } = context;

  if (cmd === 'io') {
    const field = String(tokens[0] || '').toLowerCase();
    const action = String(tokens[1] || '').toLowerCase();
    const targetMap = {
      hires: dom.toggleHires,
      color: dom.toggleColor,
      sound: dom.toggleSound
    };
    const target = targetMap[field];
    if (!(target instanceof HTMLInputElement)) {
      throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
    }
    if (action === 'toggle') {
      target.checked = !target.checked;
    } else {
      const parsed = parseBooleanToken(action);
      if (parsed == null) {
        throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
      }
      target.checked = parsed;
    }
    helpers.dispatchBubbledEvent(target, 'change');
    return `${field}=${target.checked ? 'on' : 'off'}`;
  }

  if (cmd !== 'memory') {
    return undefined;
  }

  const sub = String(tokens[0] || '').toLowerCase();
  if (sub === 'view') {
    if (tokens[1]) {
      helpers.setUiInputValueById('memoryStart', tokens[1]);
    }
    if (tokens[2]) {
      helpers.setUiInputValueById('memoryLength', tokens[2]);
    }
    actions.refreshMemoryView();
    return `memory view start=${dom.memoryStart?.value || ''} len=${dom.memoryLength?.value || ''}`;
  }
  if (sub === 'followpc' || sub === 'follow_pc') {
    const action = String(tokens[1] || '').toLowerCase();
    if (action === 'toggle') {
      actions.setMemoryFollowPcState(!state.memory.followPc);
    } else {
      const parsed = parseBooleanToken(action);
      if (parsed == null) {
        throw new Error('Usage: memory followpc <on|off|toggle>');
      }
      actions.setMemoryFollowPcState(parsed);
    }
    if (dom.memoryFollowPc) {
      dom.memoryFollowPc.checked = state.memory.followPc;
    }
    actions.refreshMemoryView();
    return `memory.followPc=${state.memory.followPc ? 'on' : 'off'}`;
  }
  if (sub === 'write') {
    const addr = tokens[1];
    const value = tokens[2];
    if (!addr || !value) {
      throw new Error('Usage: memory write <addr> <value>');
    }
    helpers.setUiInputValueById('memoryWriteAddr', addr);
    helpers.setUiInputValueById('memoryWriteValue', value);
    dom.memoryWriteBtn?.click();
    return `memory write requested @${addr}=${value}`;
  }
  if (sub === 'reset') {
    if (tokens[1]) {
      helpers.setUiInputValueById('memoryResetVector', tokens[1]);
    }
    await actions.resetApple2WithMemoryVectorOverride();
    return `memory reset vector applied (${dom.memoryResetVector?.value || 'ROM'})`;
  }
  if (sub === 'karateka') {
    await actions.loadKaratekaDump();
    return 'karateka dump load requested';
  }
  if (sub === 'load_last' || sub === 'load-last') {
    await actions.loadLastSavedApple2Dump();
    return 'load last dump requested';
  }
  if (sub === 'save_dump' || sub === 'save-dump') {
    await actions.saveApple2MemoryDump();
    return 'save dump requested';
  }
  if (sub === 'save_snapshot' || sub === 'save-snapshot') {
    await actions.saveApple2MemorySnapshot();
    return 'save snapshot requested';
  }
  if (sub === 'load_selected' || sub === 'load-selected') {
    dom.memoryDumpLoadBtn?.click();
    return 'load selected dump requested';
  }
  throw new Error('Usage: memory <view|followpc|write|reset|karateka|load_last|save_dump|save_snapshot|load_selected> ...');
}
