export const RUNNER_PRESETS = {
  generic: {
    id: 'generic',
    label: 'Generic IR Runner',
    samplePath: './assets/fixtures/cpu/ir/cpu_lib_hdl.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: true
  },
  cpu: {
    id: 'cpu',
    label: 'CPU (lib/rhdl/hdl/cpu)',
    simIrPath: './assets/fixtures/cpu/ir/cpu_lib_hdl.json',
    explorerIrPath: './assets/fixtures/cpu/ir/cpu_hier.json',
    sourceBundlePath: './assets/fixtures/cpu/ir/cpu_sources.json',
    schematicPath: './assets/fixtures/cpu/ir/cpu_schematic.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: false
  },
  apple2: {
    id: 'apple2',
    label: 'Apple II System Runner',
    simIrPath: './assets/fixtures/apple2/ir/apple2.json',
    explorerIrPath: './assets/fixtures/apple2/ir/apple2_hier.json',
    sourceBundlePath: './assets/fixtures/apple2/ir/apple2_sources.json',
    schematicPath: './assets/fixtures/apple2/ir/apple2_schematic.json',
    romPath: './assets/fixtures/apple2/memory/appleiigo.rom',
    preferredTab: 'ioTab',
    enableApple2Ui: true,
    usesManualIr: false,
    autoLoadOnBoot: true,
    defaults: {
      displayHires: true,
      displayColor: true,
      memoryFollowPc: true,
      loadKaratekaDumpOnLoad: true
    }
  }
};
