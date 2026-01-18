// JSON Protocol for Ruby simulator <-> Ink TUI communication

// Signal/Wire representation
export interface Signal {
  name: string;
  value: number;
  width: number;
  hex: string;
  binary: string;
}

// Waveform sample point
export interface WaveformSample {
  time: number;
  value: number;
}

// Waveform probe data
export interface WaveformProbe {
  name: string;
  width: number;
  samples: WaveformSample[];
}

// Breakpoint representation
export interface Breakpoint {
  id: number;
  enabled: boolean;
  description: string;
  hit_count: number;
}

// Watchpoint representation
export interface Watchpoint {
  id: number;
  enabled: boolean;
  signal: string;
  type: 'change' | 'rising_edge' | 'falling_edge' | 'equals';
  value?: number;
  description: string;
}

// Simulator state
export interface SimulatorState {
  time: number;
  cycle: number;
  running: boolean;
  paused: boolean;
  signals: Signal[];
  waveforms: WaveformProbe[];
  breakpoints: Breakpoint[];
  watchpoints: Watchpoint[];
}

// Commands from TUI to Ruby
export type Command =
  | { type: 'init' }
  | { type: 'step' }
  | { type: 'step_half' }
  | { type: 'run'; cycles?: number }
  | { type: 'stop' }
  | { type: 'reset' }
  | { type: 'continue' }
  | { type: 'set_signal'; path: string; value: number }
  | { type: 'add_breakpoint'; cycle?: number }
  | { type: 'add_watchpoint'; signal: string; watch_type: string; value?: number }
  | { type: 'delete_breakpoint'; id: number }
  | { type: 'clear_breakpoints' }
  | { type: 'clear_waveforms' }
  | { type: 'export_vcd'; filename: string }
  | { type: 'get_state' }
  | { type: 'quit' };

// Events from Ruby to TUI
export type Event =
  | { type: 'state'; state: SimulatorState }
  | { type: 'log'; message: string; level: 'info' | 'success' | 'warning' | 'error' | 'debug' }
  | { type: 'break'; breakpoint: Breakpoint | Watchpoint; message: string }
  | { type: 'error'; message: string }
  | { type: 'ready' }
  | { type: 'quit' };

// Helper to serialize command to JSON line
export function serializeCommand(cmd: Command): string {
  return JSON.stringify(cmd) + '\n';
}

// Helper to parse event from JSON line
export function parseEvent(line: string): Event | null {
  try {
    return JSON.parse(line.trim()) as Event;
  } catch {
    return null;
  }
}
