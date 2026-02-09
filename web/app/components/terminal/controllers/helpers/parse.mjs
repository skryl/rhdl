export function normalizeUiId(value) {
  return String(value || '').trim().replace(/^#/, '');
}

export function parseTabToken(token, tabPanels = []) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  const map = {
    io: 'ioTab',
    'i/o': 'ioTab',
    vcd: 'vcdTab',
    signals: 'vcdTab',
    memory: 'memoryTab',
    mem: 'memoryTab',
    component: 'componentTab',
    components: 'componentTab',
    comp: 'componentTab',
    schematic: 'componentGraphTab',
    graph: 'componentGraphTab'
  };
  if (map[raw]) {
    return map[raw];
  }
  if (Array.isArray(tabPanels) && tabPanels.some((panel) => panel && panel.id === token)) {
    return token;
  }
  return null;
}

export function parseRunnerToken(token, runnerPresets) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (runnerPresets && runnerPresets[raw]) {
    return runnerPresets[raw].id;
  }
  if (raw === 'apple' || raw === 'apple2') {
    return 'apple2';
  }
  return null;
}

export function parseBackendToken(token, backendDefs) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (backendDefs && backendDefs[raw]) {
    return backendDefs[raw].id;
  }
  return null;
}

export function terminalHelpText() {
  return [
    'Commands:',
    '  help',
    '  status',
    '  config <show|hide|toggle>',
    '  terminal <show|hide|toggle|clear>',
    '  tab <io|vcd|memory|components|schematic>',
    '  runner <generic|cpu|apple2> [load]',
    '  backend <interpreter|jit|compiler>',
    '  theme <shenzhen|original>',
    '  init | reset | step [n] | run | pause',
    '  clock <signal|none>',
    '  batch <n> | ui_every <n>',
    '  trace <start|stop|clear|save>',
    '  watch <add NAME|remove NAME|clear|list>',
    '  bp <add NAME VALUE|remove NAME|clear|list>',
    '  io <hires|color|sound> <on|off|toggle>',
    '  key <char|enter|backspace>',
    '  memory view [start] [len]',
    '  memory followpc <on|off|toggle>',
    '  memory write <addr> <value>',
    '  memory reset [vector]',
    '  memory <karateka|load_last|save_dump|save_snapshot|load_selected>',
    '  sample [path]  (generic runner)',
    '  set <elementId> <value>  (generic UI setter)',
    '  click <elementId>        (generic UI button click)'
  ].join('\n');
}
