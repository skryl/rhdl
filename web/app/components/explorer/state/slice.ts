export function createExplorerStateSlice() {
  return {
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

export function reduceExplorerState(_state, _action = {}) {
  return false;
}
