export const RUNNER_PRESETS = {
  generic: {
    id: 'generic',
    label: 'Generic IR Runner',
    samplePath: './assets/fixtures/cpu/cpu_lib_hdl.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: true
  },
  cpu: {
    id: 'cpu',
    label: 'CPU (lib/rhdl/hdl/cpu)',
    simIrPath: './assets/fixtures/cpu/cpu_lib_hdl.json',
    explorerIrPath: './assets/fixtures/cpu/cpu_hier.json',
    sourceBundlePath: './assets/fixtures/cpu/cpu_sources.json',
    schematicPath: './assets/fixtures/cpu/cpu_schematic.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: false
  },
  apple2: {
    id: 'apple2',
    label: 'Apple II System Runner',
    simIrPath: './assets/fixtures/apple2/apple2.json',
    explorerIrPath: './assets/fixtures/apple2/apple2_hier.json',
    sourceBundlePath: './assets/fixtures/apple2/apple2_sources.json',
    schematicPath: './assets/fixtures/apple2/apple2_schematic.json',
    romPath: './assets/fixtures/apple2/appleiigo.rom',
    preferredTab: 'ioTab',
    enableApple2Ui: true,
    usesManualIr: false
  }
};

export const APPLE2_RAM_BYTES = 48 * 1024;
export const APPLE2_ADDR_SPACE = 0x10000;
export const KARATEKA_PC = 0xB82A;
export const LAST_APPLE2_DUMP_KEY = 'rhdl.apple2.last_memory_dump.v1';
export const SIDEBAR_COLLAPSED_KEY = 'rhdl.ir.web.sidebar.collapsed.v1';
export const TERMINAL_OPEN_KEY = 'rhdl.ir.web.terminal.open.v1';
export const THEME_KEY = 'rhdl.ir.web.theme.v1';
export const COMPONENT_SIGNAL_PREVIEW_LIMIT = 180;
export const COLLAPSIBLE_PANEL_SELECTOR = '#controlsPanel > section, .subpanel';

export const REDUX_STORE_GLOBAL_KEY = '__RHDL_REDUX_STORE__';
export const REDUX_SYNC_GLOBAL_KEY = '__RHDL_REDUX_SYNC__';
export const REDUX_STATE_GLOBAL_KEY = '__RHDL_UX_STATE__';
