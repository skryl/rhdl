export function createInitialState() {
  return {
      backend: 'compiler',
      theme: 'shenzhen',
      sidebarCollapsed: false,
      terminalOpen: false,
      running: false,
      cycle: 0,
      uiCyclesPending: 0,
      watches: new Map(),
      watchRows: [],
      breakpoints: [],
      runnerPreset: 'apple2',
      activeTab: 'ioTab',
      apple2: {
        enabled: false,
        keyQueue: [],
        lastSpeakerToggles: 0,
        lastCpuResult: null,
        baseRomBytes: null,
        displayHires: false,
        displayColor: false,
        soundEnabled: false,
        audioCtx: null,
        audioOsc: null,
        audioGain: null
      },
      memory: {
        followPc: false,
        disasmLines: 28,
        lastSavedDump: null
      },
      terminal: {
        history: [],
        historyIndex: -1,
        busy: false
      },
      dashboard: {
        rootElements: new Map(),
        layouts: {},
        draggingItemId: '',
        draggingRootKey: '',
        dropTargetItemId: '',
        dropPosition: '',
        resizeBound: false,
        resizeTeardown: null,
        panelTeardowns: new Map(),
        resizing: {
          active: false,
          rootKey: '',
          rowSignature: '',
          startY: 0,
          startHeight: 140
        }
      },
      components: {
        model: null,
        selectedNodeId: null,
        parseError: '',
        sourceKey: '',
        overrideSource: '',
        overrideMeta: null,
        graph: null,
        graphKey: '',
        graphSelectedId: null,
        graphFocusId: null,
        graphShowChildren: false,
        graphLastTap: null,
        graphHighlightedSignal: null,
        graphLiveValues: new Map(),
        graphLayoutEngine: 'none',
        graphElkAvailable: false,
        sourceBundle: null,
        sourceBundleByClass: new Map(),
        sourceBundleByModule: new Map(),
        schematicBundle: null,
        schematicBundleByPath: new Map()
      }
  };
}
