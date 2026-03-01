export type UnknownRecord = Record<string, unknown>;

export interface ComponentSignal {
  name: string;
  fullName: string;
  liveName: string | null;
  width: number;
  kind: string;
  direction: string | null;
  declaration: unknown;
  value?: unknown;
  matchesHighlight?: boolean;
}

export interface ComponentNode {
  id: string;
  parentId: string | null;
  name: string;
  kind: string;
  path: string;
  pathTokens: string[];
  children: string[];
  signals: ComponentSignal[];
  rawRef: UnknownRecord | null;
  _signalKeys: Set<string>;
}

export interface SignalInfo {
  width?: number;
  kind?: string;
  direction?: string | null;
  entry?: unknown;
}

export interface IrMetaLike {
  ir?: UnknownRecord;
  names?: string[];
  liveSignalNames?: string[];
  signalInfo?: Map<string, SignalInfo>;
  widths?: Map<string, number>;
}

export interface ComponentModel {
  nextId: number;
  mode: string;
  nodes: Map<string, ComponentNode>;
  rootId: string | null;
  pathMap?: Map<string, string>;
}

export interface SourceBundleEntry extends UnknownRecord {
  component_class?: string;
  module_name?: string;
  source_path?: string;
  rhdl_source?: string;
  verilog_source?: string;
}

export interface SourceBundle extends UnknownRecord {
  top?: SourceBundleEntry;
  components?: SourceBundleEntry[];
}

export interface SchematicBundleEntry extends UnknownRecord {
  schematic?: UnknownRecord;
}

export interface GraphTapState {
  nodeId: string;
  timeMs: number;
}

export interface HighlightedSignal {
  signalName: string | null;
  liveName: string | null;
}

export interface ExplorerGraphLike extends UnknownRecord {
  destroy?: () => void;
  canvas?: HTMLCanvasElement;
  legendCanvas?: HTMLCanvasElement | null;
  renderer?: {
    render: (renderList: RenderList, viewport: GraphViewport, palette: ThemePalette) => void;
    destroy: () => void;
  };
  interactions?: { destroy: () => void };
  viewport?: GraphViewport;
  spatialIndex?: SpatialIndex;
  renderList?: RenderList;
  renderLegendOverlay?: (palette: ThemePalette) => void;
}

export interface ExplorerComponentsState {
  model: ComponentModel | null;
  selectedNodeId: string | null;
  parseError: string;
  sourceKey: string;
  overrideSource?: string;
  overrideMeta: IrMetaLike | null;
  graph: ExplorerGraphLike | null;
  graphKey: string;
  graphSelectedId: string | null;
  graphFocusId: string | null;
  graphShowChildren: boolean;
  graphLastTap: GraphTapState | null;
  graphHighlightedSignal: HighlightedSignal | null;
  graphLiveValues: Map<string, string>;
  graphLayoutEngine: string;
  graphElkAvailable: boolean;
  graphRenderBackend?: string;
  sourceBundle: SourceBundle | null;
  sourceBundleByClass: Map<string, SourceBundleEntry>;
  sourceBundleByModule: Map<string, SourceBundleEntry>;
  schematicBundle: UnknownRecord | null;
  schematicBundleByPath: Map<string, SchematicBundleEntry>;
}

export interface ExplorerStateLike extends UnknownRecord {
  components: ExplorerComponentsState;
  activeTab?: string;
  theme?: string;
}

export interface RuntimeSimLike {
  peek: (name: string) => unknown;
  trace_enabled?: () => boolean;
}

export interface ExplorerRuntimeLike extends UnknownRecord {
  sim?: RuntimeSimLike | null;
  irMeta?: IrMetaLike | null;
}

export interface ExplorerDomRefs extends UnknownRecord {
  componentTree?: (EventTarget & {
    setTree?: (rows: unknown, parseError?: string) => void;
    getFilter?: () => string;
  }) | null;
  componentTitle?: { textContent: string | null } | null;
  componentMeta?: { textContent: string | null } | null;
  componentSignalMeta?: { textContent: string | null } | null;
  componentSignalBody?: (UnknownRecord & {
    setSignals?: (signalRows: unknown, hiddenSignalCount: unknown, formatValue: unknown) => void;
  }) | null;
  componentGraphTitle?: { textContent: string | null } | null;
  componentGraphMeta?: { textContent: string | null } | null;
  componentGraphTopBtn?: (EventTarget & { disabled?: boolean }) | null;
  componentGraphUpBtn?: (EventTarget & { disabled?: boolean }) | null;
  componentGraphZoomInBtn?: EventTarget | null;
  componentGraphZoomOutBtn?: EventTarget | null;
  componentGraphResetViewBtn?: EventTarget | null;
  componentGraphFocusPath?: { textContent: string | null } | null;
  componentVisual?: (HTMLElement & { style: CSSStyleDeclaration }) | null;
  componentLiveSignals?: (UnknownRecord & {
    setData?: (data: unknown, formatValue: unknown) => void;
  }) | null;
  componentConnectionMeta?: { textContent: string | null } | null;
  componentConnectionBody?: (UnknownRecord & {
    setConnections?: (rows: unknown, hiddenCount?: number) => void;
    clear?: () => void;
  }) | null;
  componentCode?: (UnknownRecord & {
    setCodeTexts?: (payload: { rhdl?: string; verilog?: string }) => void;
    textContent?: string | null;
  }) | null;
  irFileInput?: (EventTarget & { files?: FileList | null }) | null;
  irJson?: (EventTarget & { value: string }) | null;
}

export interface TreeRow {
  nodeId: string;
  depth: number;
  name: string;
  kind: string;
  childCount: number;
  signalCount: number;
  isActive: boolean;
}

export interface SchematicElement {
  data: UnknownRecord;
  classes: string;
}

export interface RenderPoint {
  x: number;
  y: number;
}

export interface RenderSymbol {
  id: string;
  label?: string;
  type?: string;
  componentId?: string;
  path?: string;
  direction?: string;
  signalName?: string;
  liveName?: string;
  classes?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

export interface RenderPin {
  id: string;
  type?: string;
  label?: string;
  symbolId?: string;
  side?: string;
  order?: number;
  direction?: string;
  signalName?: string;
  liveName?: string;
  valueKey?: string;
  signalWidth?: number;
  bus?: boolean;
  classes?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  active?: boolean;
  toggled?: boolean;
  selected?: boolean;
}

export interface RenderNet {
  id: string;
  type?: string;
  label?: string;
  signalName?: string;
  liveName?: string;
  valueKey?: string;
  signalWidth?: number;
  group?: string;
  bus?: boolean;
  classes?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  active?: boolean;
  toggled?: boolean;
  selected?: boolean;
}

export interface RenderWire {
  id: string;
  sourceId?: string;
  targetId?: string;
  signalName?: string;
  liveName?: string;
  valueKey?: string;
  signalWidth?: number;
  direction?: string;
  kind?: string;
  segment?: string;
  netId?: string;
  bus?: boolean;
  bidir?: boolean;
  classes?: string;
  active?: boolean;
  toggled?: boolean;
  selected?: boolean;
  bendPoints?: RenderPoint[];
}

export interface RenderList {
  symbols: RenderSymbol[];
  pins: RenderPin[];
  nets: RenderNet[];
  wires: RenderWire[];
  byId: Map<string, unknown>;
}

export interface GraphViewport {
  x: number;
  y: number;
  scale: number;
}

export interface SpatialIndex {
  queryPoint: (x: number, y: number) => RenderSymbol | RenderPin | RenderNet | null;
}

export interface ThemePalette {
  componentBg: string;
  componentBorder: string;
  componentText: string;
  pinBg: string;
  pinBorder: string;
  netBg: string;
  netBorder: string;
  netText: string;
  ioBg: string;
  ioBorder: string;
  ioText?: string;
  opBg: string;
  opBorder?: string;
  opText?: string;
  memoryBg: string;
  memoryBorder?: string;
  wire: string;
  wireActive: string;
  wireToggle: string;
  selected: string;
}

export interface ElementColorResult {
  fill?: string;
  stroke: string;
  text?: string;
  strokeWidth: number;
}

export function asRecord(value: unknown): UnknownRecord | null {
  return value !== null && typeof value === 'object' ? (value as UnknownRecord) : null;
}

export function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((entry) => String(entry)).filter((entry) => entry.length > 0);
}
