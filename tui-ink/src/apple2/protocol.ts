// JSON Protocol for Apple II emulator <-> Ink TUI communication

// CPU state
export interface CPUState {
  pc: number;      // Program Counter (16-bit)
  a: number;       // Accumulator (8-bit)
  x: number;       // X Register (8-bit)
  y: number;       // Y Register (8-bit)
  sp: number;      // Stack Pointer (8-bit)
  p: number;       // Processor Status (8-bit)
  cycles: number;  // Total cycles executed
  halted: boolean;
}

// Display mode types
export type DisplayMode = 'text' | 'hires' | 'hires_mixed' | 'lores' | 'lores_mixed';

// Screen content (40x24 character codes for text, or braille strings for hires)
export interface ScreenData {
  mode: DisplayMode;      // Current display mode
  rows?: number[][];      // 24 rows of 40 character codes (text mode)
  hires_lines?: string[]; // Braille-rendered hi-res lines (hires mode)
  dirty: boolean;
}

// Memory dump
export interface MemoryDump {
  address: number;
  bytes: number[];
}

// Disassembled instruction
export interface Instruction {
  address: number;
  bytes: number[];
  mnemonic: string;
  operand: string;
  cycles: number;
}

// ROM info
export interface ROMInfo {
  name: string;
  size: number;
  baseAddress: number;
  checksum: string;
}

// Full emulator state
export interface EmulatorState {
  cpu: CPUState;
  screen: ScreenData;
  running: boolean;
  speed: number;          // Cycles per frame
  mode: 'hdl' | 'isa';    // Simulation mode
  display_mode?: DisplayMode; // Current video display mode
  romInfo?: ROMInfo;
}

// Commands from TUI to Ruby
export type Apple2Command =
  | { type: 'init' }
  | { type: 'get_state' }
  | { type: 'step' }                        // Execute one instruction
  | { type: 'step_cycle' }                  // Execute one clock cycle
  | { type: 'run' }                         // Start continuous execution
  | { type: 'stop' }                        // Pause execution
  | { type: 'reset' }                       // Reset CPU
  | { type: 'set_speed'; cycles: number }   // Set cycles per frame
  | { type: 'key_press'; ascii: number }    // Send key to emulator
  | { type: 'read_memory'; address: number; length: number }
  | { type: 'write_memory'; address: number; value: number }
  | { type: 'set_breakpoint'; address: number }
  | { type: 'clear_breakpoint'; address: number }
  | { type: 'disassemble'; address: number; count: number }
  | { type: 'load_program'; path: string; address?: number }
  | { type: 'quit' };

// Events from Ruby to TUI
export type Apple2Event =
  | { type: 'ready'; mode: 'hdl' | 'isa' }
  | { type: 'state'; state: EmulatorState }
  | { type: 'screen_update'; screen: ScreenData }
  | { type: 'memory'; dump: MemoryDump }
  | { type: 'disassembly'; instructions: Instruction[] }
  | { type: 'breakpoint_hit'; address: number }
  | { type: 'halted'; pc: number }
  | { type: 'log'; message: string; level: 'info' | 'warning' | 'error' }
  | { type: 'error'; message: string }
  | { type: 'quit' };

// Helper functions
export function serializeCommand(cmd: Apple2Command): string {
  return JSON.stringify(cmd) + '\n';
}

export function parseEvent(line: string): Apple2Event | null {
  try {
    return JSON.parse(line.trim()) as Apple2Event;
  } catch {
    return null;
  }
}

// Format helpers
export function formatHex8(value: number): string {
  return value.toString(16).toUpperCase().padStart(2, '0');
}

export function formatHex16(value: number): string {
  return value.toString(16).toUpperCase().padStart(4, '0');
}

export function formatBinary8(value: number): string {
  return value.toString(2).padStart(8, '0');
}

// Status flag helpers
export function getFlag(p: number, bit: number): boolean {
  return (p & (1 << bit)) !== 0;
}

export function formatFlags(p: number): string {
  const flags = [
    getFlag(p, 7) ? 'N' : 'n',
    getFlag(p, 6) ? 'V' : 'v',
    '-',
    getFlag(p, 4) ? 'B' : 'b',
    getFlag(p, 3) ? 'D' : 'd',
    getFlag(p, 2) ? 'I' : 'i',
    getFlag(p, 1) ? 'Z' : 'z',
    getFlag(p, 0) ? 'C' : 'c',
  ];
  return flags.join('');
}

// Convert Apple II character code to displayable character
export function apple2CharToAscii(code: number): string {
  // Apple II uses high bit for inverse video
  const char = code & 0x7F;
  if (char >= 0x20 && char < 0x7F) {
    return String.fromCharCode(char);
  }
  return ' ';
}
