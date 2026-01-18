// Apple II theme - Green phosphor CRT aesthetic
// Inspired by the Apple II's P1 phosphor green monitors

export const apple2Theme = {
  // Apple II green phosphor colors
  phosphor: '#33ff33',        // Classic Apple II green
  phosphorBright: '#66ff66',  // Bright/highlighted
  phosphorDim: '#1a8c1a',     // Dim/inactive
  phosphorGlow: '#44ff44',    // Glow effect

  // Background - CRT black
  bg: '#0a0f0a',              // Slightly green-tinted black
  bgLight: '#0f1a0f',         // Lighter area

  // Borders and UI
  border: '#227722',          // Medium green border
  borderBright: '#33ff33',    // Active border

  // Text
  text: '#33ff33',            // Main text
  textDim: '#1a6b1a',         // Dimmed text
  textMuted: '#0d3d0d',       // Very dim
  textInverse: '#0a0f0a',     // Inverse text (black on green)

  // Special colors (minimal, Apple II was monochrome)
  cursor: '#33ff33',          // Blinking cursor
  selection: '#227722',       // Selection highlight

  // Status indicators
  running: '#33ff33',
  stopped: '#1a6b1a',
  error: '#ff3333',           // Only non-green color (for errors)
} as const;

// Apple II character set symbols
export const apple2Chars = {
  // Border characters (simple ASCII style like Apple II)
  borderH: '-',
  borderV: '|',
  cornerTL: '+',
  cornerTR: '+',
  cornerBL: '+',
  cornerBR: '+',

  // Box drawing for modern terminal
  boxH: '─',
  boxV: '│',
  boxTL: '┌',
  boxTR: '┐',
  boxBL: '└',
  boxBR: '┘',
  boxCross: '┼',
  boxTeeL: '├',
  boxTeeR: '┤',
  boxTeeU: '┴',
  boxTeeD: '┬',

  // Cursor and indicators
  cursor: '█',
  cursorBlink: '▌',
  prompt: ']',              // Apple II prompt
  arrow: '>',
  bullet: '*',

  // Apple II style decorations
  apple: '@',               // Apple logo substitute
} as const;

// Apple II screen dimensions
export const APPLE2_COLS = 40;
export const APPLE2_ROWS = 24;

// Memory regions
export const MEMORY_REGIONS = {
  zeroPage: { start: 0x0000, end: 0x00FF, name: 'Zero Page' },
  stack: { start: 0x0100, end: 0x01FF, name: 'Stack' },
  textPage1: { start: 0x0400, end: 0x07FF, name: 'Text Page 1' },
  textPage2: { start: 0x0800, end: 0x0BFF, name: 'Text Page 2' },
  program: { start: 0x0800, end: 0xBFFF, name: 'Program' },
  rom: { start: 0xC000, end: 0xFFFF, name: 'ROM/IO' },
} as const;

// 6502 status flags
export const STATUS_FLAGS = {
  N: { bit: 7, name: 'N', desc: 'Negative' },
  V: { bit: 6, name: 'V', desc: 'Overflow' },
  B: { bit: 4, name: 'B', desc: 'Break' },
  D: { bit: 3, name: 'D', desc: 'Decimal' },
  I: { bit: 2, name: 'I', desc: 'Interrupt' },
  Z: { bit: 1, name: 'Z', desc: 'Zero' },
  C: { bit: 0, name: 'C', desc: 'Carry' },
} as const;

// ASCII art header
export const APPLE2_HEADER = `
+----------------------------------------+
|     APPLE ][  EMULATOR                 |
|     RHDL 6502 SIMULATOR                |
+----------------------------------------+
`.trim();

// Compact header
export const APPLE2_HEADER_COMPACT = '+-- APPLE ][ --+';
